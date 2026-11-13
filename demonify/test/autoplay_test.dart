import 'dart:async';
import 'dart:io';

import 'package:demonify/features/catalog/models.dart';
import 'package:demonify/features/downloads/download_manager.dart';
import 'package:demonify/features/player/autoplay.dart';
import 'package:demonify/features/player/player_controller.dart';
import 'package:demonify/features/player/player_providers.dart';
import 'package:demonify/features/player/queue_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Steuerbare Autoplay-Quelle: Antwort erst nach [release] (für Wettlauf-Tests)
class FakeAutoplay implements AutoplaySource {
  FakeAutoplay(this.result);
  List<Track> result;
  final calls = <String>[];
  final recent = <List<String>>[];
  Completer<void>? gate;

  @override
  Future<List<Track>> candidates(Track finished, {List<String> recentIds = const []}) async {
    calls.add(finished.id);
    recent.add(recentIds);
    if (gate != null) await gate!.future;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeEngine engine;
  late ProviderContainer container;
  late FakeAutoplay autoplay;
  late PlayerController player;

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    engine = FakeEngine();
    final dir = Directory.systemTemp.createTempSync('dmf');
    final files = {for (final id in ['t1', 't2', 't3', 'sim']) id: File('${dir.path}/$id.flac')..writeAsBytesSync([1])};
    autoplay = FakeAutoplay([fakeTrack('t1'), fakeTrack('sim')]);
    container = ProviderContainer(overrides: [
      audioEngineProvider.overrideWithValue(engine),
      downloadsProvider.overrideWith(() => FakeDownloads(files)),
      autoplaySourceProvider.overrideWithValue(autoplay),
    ]);
    player = container.read(playerProvider);
  });
  tearDown(() => container.dispose());

  test('Ende einer Single ohne Wiederholung → zufälliger ähnlicher Titel, nie der gerade beendete', () async {
    await player.playTracks([fakeTrack('t1')]);
    engine.complete();
    await settle();
    expect(autoplay.calls, ['t1']);
    expect(autoplay.recent.single, contains('t1'));
    expect(player.state.current!.id, 'sim'); // t1 (beendet) wird übersprungen
    expect(player.state.queue.map((e) => e.track.id), ['t1', 'sim']);
    expect(engine.isPlaying, isTrue);
    expect(engine.opened.last, contains('sim.flac'));
  });

  test('Album läuft erst vollständig, Autoplay nur am Ende der Warteschlange', () async {
    await player.playTracks([fakeTrack('t1'), fakeTrack('t2')]);
    engine.complete();
    await settle();
    expect(player.state.current!.id, 't2');
    expect(autoplay.calls, isEmpty);
    engine.complete();
    await settle();
    expect(autoplay.calls, ['t2']);
    expect(player.state.current!.id, 't1'); // erster abspielbarer Kandidat ≠ t2
  });

  test('Song wiederholen hat Vorrang', () async {
    await player.playTracks([fakeTrack('t1')]);
    player.setRepeat(RepeatMode.one);
    engine.complete();
    await settle();
    expect(autoplay.calls, isEmpty);
    expect(player.state.current!.id, 't1');
  });

  test('Playlist wiederholen hat Vorrang', () async {
    await player.playTracks([fakeTrack('t1'), fakeTrack('t2')], index: 1);
    player.setRepeat(RepeatMode.all);
    engine.complete();
    await settle();
    expect(autoplay.calls, isEmpty);
    expect(player.state.current!.id, 't1');
    expect(player.state.queue.length, 2);
  });

  test('kein passender Titel → Wiedergabe endet regulär', () async {
    autoplay.result = [fakeTrack('t1'), fakeTrack('nope', available: false)];
    await player.playTracks([fakeTrack('t1')]);
    engine.complete();
    await settle();
    expect(autoplay.calls, ['t1']);
    expect(player.state.queue.length, 1);
    expect(engine.isPlaying, isFalse);
  });

  test('Stopp und Wiedergabefehler lösen kein Autoplay aus', () async {
    await player.playTracks([fakeTrack('t1')]);
    await player.stop();
    engine.complete();
    await settle();
    expect(autoplay.calls, isEmpty);

    // Fehler: Titel weder lokal noch per Server abspielbar
    await player.playTracks([fakeTrack('kaputt')]);
    expect(player.state.error, isNotNull);
    engine.complete();
    await settle();
    expect(autoplay.calls, isEmpty);
  });

  test('Pause löst kein Autoplay aus', () async {
    await player.playTracks([fakeTrack('t1')]);
    await player.pause();
    await settle();
    expect(autoplay.calls, isEmpty);
    expect(player.state.current!.id, 't1');
  });

  test('neue Wiedergabe während der Titelsuche wird nicht überschrieben', () async {
    autoplay.gate = Completer<void>();
    await player.playTracks([fakeTrack('t1')]);
    engine.complete();
    await settle();
    expect(player.autoplaySearching, isTrue);
    // Nutzer startet etwas anderes, bevor die Suche fertig ist
    await player.playTracks([fakeTrack('t3')]);
    autoplay.gate!.complete();
    await settle();
    expect(player.state.current!.id, 't3');
    expect(player.state.queue.map((e) => e.track.id), ['t3']);
    expect(engine.opened.last, contains('t3.flac'));
  });
}
