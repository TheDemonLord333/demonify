import 'dart:math';

import 'package:demonify/features/player/queue_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  final tracks = List.generate(5, (i) => fakeTrack('t$i'));

  test('Weiter/Zurück und Ende der Warteschlange', () {
    final q = QueueModel()..setQueue(tracks, startIndex: 3);
    expect(q.current!.track.id, 't3');
    expect(q.nextIndex(), 4);
    q.jumpTo(4);
    expect(q.nextIndex(auto: true), isNull);
    q.repeat = RepeatMode.all;
    expect(q.nextIndex(auto: true), 0);
    q.repeat = RepeatMode.one;
    expect(q.nextIndex(auto: true), 4);
    expect(q.previousIndex(), 3);
  });

  test('Shuffle behält aktuellen Titel und stellt Reihenfolge wieder her', () {
    final q = QueueModel(random: Random(1))..setQueue(tracks, startIndex: 2);
    q.setShuffle(true);
    expect(q.index, 0);
    expect(q.current!.track.id, 't2');
    expect(q.items.map((e) => e.track.id).toSet(), tracks.map((t) => t.id).toSet());
    q.setShuffle(false);
    expect(q.items.map((e) => e.track.id).toList(), ['t0', 't1', 't2', 't3', 't4']);
    expect(q.current!.track.id, 't2');
  });

  test('Umsortieren und Entfernen halten den aktuellen Titel', () {
    final q = QueueModel()..setQueue(tracks, startIndex: 2);
    q.move(0, 4);
    expect(q.current!.track.id, 't2');
    expect(q.removeAt(0), isFalse);
    expect(q.current!.track.id, 't2');
    expect(q.removeAt(q.index), isTrue);
    expect(q.items.length, 3);
  });

  test('Wiederholungsmodi rotieren aus → alle → einer → aus', () {
    final q = QueueModel();
    expect(q.cycleRepeat(), RepeatMode.all);
    expect(q.cycleRepeat(), RepeatMode.one);
    expect(q.cycleRepeat(), RepeatMode.off);
  });

  test('Als Nächstes spielen fügt hinter dem aktuellen Titel ein', () {
    final q = QueueModel()..setQueue(tracks, startIndex: 1);
    q.playNext([fakeTrack('x')]);
    expect(q.items[2].track.id, 'x');
  });
}
