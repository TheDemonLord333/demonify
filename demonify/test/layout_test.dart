import 'dart:io';
import 'dart:ui' as ui;

import 'package:demonify/core/theme/theme.dart';
import 'package:demonify/features/catalog/catalog_providers.dart';
import 'package:demonify/features/catalog/models.dart';
import 'package:demonify/features/catalog/release_screen.dart';
import 'package:demonify/features/downloads/download_manager.dart';
import 'package:demonify/features/home/home_screen.dart';
import 'package:demonify/features/player/equalizer/equalizer_screen.dart';
import 'package:demonify/features/player/player_controller.dart';
import 'package:demonify/features/player/player_providers.dart';
import 'package:demonify/features/player/player_widgets.dart';
import 'package:demonify/features/player/queue_model.dart';
import 'package:demonify/features/shell/app_shell.dart';
import 'package:demonify/l10n/l10n.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Prüft die Hauptansichten auf Layoutüberläufe (Smartphone + breiter Bildschirm, große Schrift).
void main() {
  final tracks = [for (var i = 1; i <= 8; i++) fakeTrack('t$i', title: 'Ein ziemlich langer Songtitel Nummer', cover: i.isEven ? 'c$i' : null)];
  final release = Release(id: 'r1', title: 'Albumtitel mit sehr langem Namen zum Testen', type: ReleaseType.album, year: 2026, albumArtist: const ArtistRef(id: 'a1', name: 'TheDemonLord333'), trackCount: 8);
  final home = HomeData(
    recentlyPlayed: tracks,
    newReleases: [release, release],
    playlists: const [PlaylistSummary(id: 'p1', name: 'Meine Playlist', trackCount: 3)],
    favoritesCount: 4,
    followedArtists: const [ArtistRef(id: 'a1', name: 'TheDemonLord333')],
  );
  final snap = PlayerSnapshot(queue: [for (var i = 0; i < tracks.length; i++) QueueEntry(uid: i, track: tracks[i])], index: 1, playing: true, duration: const Duration(minutes: 3), repeat: RepeatMode.all);

  Future<void> pump(WidgetTester tester, Widget child, Size size, double scale, String shot) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        audioEngineProvider.overrideWithValue(FakeEngine()),
        downloadsProvider.overrideWith(() => FakeDownloads({})),
        homeProvider.overrideWith((ref) async => home),
        releaseDetailProvider.overrideWith((ref, id) async => ReleaseDetail(release: release, saved: true, tracks: tracks)),
        playerSnapshotProvider.overrideWithValue(snap),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: buildDemonifyTheme(),
          locale: const Locale('de'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: MediaQuery(data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)), child: child),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull, reason: shot);
    final dir = Directory('build/layout_shots')..createSync(recursive: true);
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/$shot.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  const phone = Size(360, 720);
  const wide = Size(1280, 800);
  for (final (name, size, scale) in [('phone', phone, 1.0), ('phone_large_text', phone, 1.5), ('wide', wide, 1.0)]) {
    testWidgets('Start ($name)', (t) => pump(t, AppShell(location: '/home', child: const HomeScreen()), size, scale, 'home_$name'));
    testWidgets('Veröffentlichung ($name)', (t) => pump(t, AppShell(location: '/release/r1', child: const ReleaseScreen(id: 'r1')), size, scale, 'release_$name'));
    testWidgets('Player ($name)', (t) => pump(t, const PlayerScreen(), size, scale, 'player_$name'));
    testWidgets('Equalizer ($name)', (t) => pump(t, const EqualizerScreen(), size, scale, 'eq_$name'));
  }
}
