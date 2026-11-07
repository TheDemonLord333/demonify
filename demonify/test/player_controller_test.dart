import 'dart:io';

import 'package:demonify/features/downloads/download_manager.dart';
import 'package:demonify/features/player/equalizer/eq_model.dart';
import 'package:demonify/features/player/player_controller.dart';
import 'package:demonify/features/player/player_providers.dart';
import 'package:demonify/features/player/queue_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeEngine engine;
  late ProviderContainer container;
  late File local;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    engine = FakeEngine();
    local = File('${Directory.systemTemp.createTempSync('dmf').path}/t1.flac')..writeAsBytesSync([1, 2, 3]);
    container = ProviderContainer(overrides: [
      audioEngineProvider.overrideWithValue(engine),
      downloadsProvider.overrideWith(() => FakeDownloads({'t1': local})),
    ]);
  });
  tearDown(() => container.dispose());

  test('Heruntergeladene Titel werden aus der lokalen Datei gespielt – auch ohne Server', () async {
    final player = container.read(playerProvider);
    await player.playTracks([fakeTrack('t1')]);
    expect(engine.opened.single, Uri.file(local.path).toString());
    expect(player.state.source, PlaybackSource.local);
    expect(player.state.error, isNull);
  });

  test('Nicht heruntergeladene Titel ohne Server werden übersprungen statt die App zu blockieren', () async {
    final player = container.read(playerProvider);
    await player.playTracks([fakeTrack('t0'), fakeTrack('t1')]);
    // t0 ist nicht lokal und kein Server verfügbar → automatisch zu t1
    expect(player.state.current!.id, 't1');
    expect(engine.opened.single, Uri.file(local.path).toString());
  });

  test('Nicht verfügbare Titel landen nicht in der Warteschlange', () async {
    final player = container.read(playerProvider);
    await player.playTracks([fakeTrack('x', available: false), fakeTrack('t1')]);
    expect(player.state.queue.length, 1);
  });

  test('Wiederholung eines Titels startet ihn am Ende neu', () async {
    final player = container.read(playerProvider);
    await player.playTracks([fakeTrack('t1')]);
    player.setRepeat(RepeatMode.one);
    engine.complete();
    await Future<void>.delayed(Duration.zero);
    expect(player.state.current!.id, 't1');
    expect(engine.isPlaying, isTrue);
  });

  test('Equalizer wird an die Engine übergeben, Vorverstärkung als Headroom', () async {
    final player = container.read(playerProvider);
    await player.applyEqualizer(EqSettings(enabled: true, gains: EqPreset.rock.gains!));
    expect(engine.filter, contains('equalizer=f=31'));
    expect(engine.gainDb, -4.5);
    await player.applyEqualizer(const EqSettings());
    expect(engine.filter, '');
    expect(engine.gainDb, 0);
  });
}
