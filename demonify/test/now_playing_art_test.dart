import 'dart:async';
import 'dart:io';

import 'package:demonify/features/player/now_playing_art.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  final dir = Directory.systemTemp.createTempSync('art');
  File file(String name) => File('${dir.path}/$name.jpg')..writeAsBytesSync([1]);

  test('lokales Bild (Cache/Download) wird sofort verwendet – auch offline', () {
    var resolved = 0;
    final art = NowPlayingArt(
      resolve: (id) async {
        resolved++;
        return null;
      },
      local: (id) => id == 'c1' ? file('c1') : null,
      onChanged: () {},
    );
    expect(art.artFor(fakeTrack('t1', cover: 'c1')), Uri.file('${dir.path}/c1.jpg'));
    expect(resolved, 0);
  });

  test('ohne eigenes Songcover wird das Veröffentlichungscover verwendet', () {
    final requested = <String>[];
    final art = NowPlayingArt(resolve: (id) async => null, local: (id) {
      requested.add(id);
      return null;
    }, onChanged: () {});
    art.artFor(fakeTrack('t1')); // fakeTrack: Veröffentlichungscover „relcover“
    expect(requested.first, 'relcover');
  });

  test('nach einem Fehlversuch wird dasselbe Cover erneut geladen', () async {
    var calls = 0;
    var changed = 0;
    final art = NowPlayingArt(
      resolve: (id) async => ++calls == 1 ? null : file('c2'),
      local: (_) => null,
      onChanged: () => changed++,
      retryDelay: const Duration(milliseconds: 20),
    );
    final t = fakeTrack('t1', cover: 'c2');
    expect(art.artFor(t), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(calls, 1);
    // Wiederholung wird über onChanged angestoßen
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(changed, 1);
    expect(art.artFor(t), isNull); // zweiter Versuch läuft
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(calls, 2);
    expect(changed, 2);
    expect(art.artFor(t), Uri.file('${dir.path}/c2.jpg'));
  });

  test('verspätet geladenes Bild wird nach einem Titelwechsel nicht dem neuen Titel zugeordnet', () async {
    final pending = <String, Completer<File?>>{};
    var changed = 0;
    final art = NowPlayingArt(
      resolve: (id) => (pending[id] = Completer<File?>()).future,
      local: (_) => null,
      onChanged: () => changed++,
    );
    final a = fakeTrack('a', cover: 'ca');
    final b = fakeTrack('b', cover: 'cb');
    expect(art.artFor(a), isNull);
    expect(art.artFor(b), isNull); // schneller Wechsel am Sperrbildschirm
    pending['ca']!.complete(file('ca'));
    await Future<void>.delayed(Duration.zero);
    expect(changed, 0);
    expect(art.artFor(b), isNull); // A's Bild landet nicht bei B
    pending['cb']!.complete(file('cb'));
    await Future<void>.delayed(Duration.zero);
    expect(changed, 1);
    expect(art.artFor(b), Uri.file('${dir.path}/cb.jpg'));
  });

  test('begrenzte Anzahl Versuche, wenn das Cover dauerhaft fehlt', () async {
    var calls = 0;
    final art = NowPlayingArt(
      resolve: (id) async {
        calls++;
        throw const SocketException('offline');
      },
      local: (_) => null,
      onChanged: () {},
      retryDelay: Duration.zero,
      maxAttempts: 3,
    );
    final t = fakeTrack('t', cover: 'cx');
    for (var i = 0; i < 10; i++) {
      art.artFor(t);
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(calls, 3);
    art.dispose();
  });
}
