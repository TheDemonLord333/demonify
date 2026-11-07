import 'dart:math';

import '../catalog/models.dart';

enum RepeatMode { off, all, one }

/// Reine Warteschlangenlogik (ohne Audio) – unabhängig testbar.
///
/// [items] ist die sichtbare Reihenfolge. Beim Einschalten von Shuffle wird die
/// ursprüngliche Reihenfolge gemerkt und der aktuelle Titel an den Anfang gesetzt;
/// beim Ausschalten wird die ursprüngliche Reihenfolge wiederhergestellt.
class QueueModel {
  QueueModel({Random? random}) : _random = random ?? Random();

  final Random _random;
  List<QueueEntry> _items = [];
  List<QueueEntry>? _unshuffled;
  int _index = -1;
  bool shuffle = false;
  RepeatMode repeat = RepeatMode.off;
  int _uidCounter = 0;

  List<QueueEntry> get items => List.unmodifiable(_items);
  int get index => _index;
  bool get isEmpty => _items.isEmpty;
  QueueEntry? get current => (_index >= 0 && _index < _items.length) ? _items[_index] : null;

  QueueEntry _entry(Track t) => QueueEntry(uid: ++_uidCounter, track: t);

  void setQueue(List<Track> tracks, {int startIndex = 0, bool shuffled = false}) {
    _items = tracks.map(_entry).toList();
    _index = tracks.isEmpty ? -1 : startIndex.clamp(0, tracks.length - 1);
    _unshuffled = null;
    shuffle = false;
    if (shuffled) setShuffle(true);
  }

  /// Wiederherstellung eines gespeicherten Zustands
  void restore({required List<Track> tracks, required int index, List<Track>? unshuffled, required bool shuffle, required RepeatMode repeat}) {
    _items = tracks.map(_entry).toList();
    _unshuffled = unshuffled?.map(_entry).toList();
    _index = tracks.isEmpty ? -1 : index.clamp(0, tracks.length - 1);
    this.shuffle = shuffle && _unshuffled != null;
    this.repeat = repeat;
  }

  List<Track>? get unshuffledTracks => _unshuffled?.map((e) => e.track).toList();

  void setShuffle(bool on) {
    if (on == shuffle) return;
    if (on) {
      _unshuffled = List.of(_items);
      final cur = current;
      final rest = List.of(_items);
      if (cur != null) rest.remove(cur);
      rest.shuffle(_random);
      _items = [?cur, ...rest];
      _index = cur == null ? -1 : 0;
      shuffle = true;
    } else {
      final cur = current;
      final original = _unshuffled ?? _items;
      // Später hinzugefügte Einträge hinten anhängen, entfernte weglassen
      final present = _items.toSet();
      final restored = [...original.where(present.contains), ..._items.where((e) => !original.contains(e))];
      _items = restored;
      _index = cur == null ? -1 : _items.indexOf(cur);
      _unshuffled = null;
      shuffle = false;
    }
  }

  RepeatMode cycleRepeat() {
    repeat = switch (repeat) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    return repeat;
  }

  /// Index des nächsten Titels; [auto] = automatisches Weiterschalten am Titelende
  int? nextIndex({bool auto = false}) {
    if (_items.isEmpty) return null;
    if (auto && repeat == RepeatMode.one) return _index;
    if (_index + 1 < _items.length) return _index + 1;
    if (repeat == RepeatMode.all || (!auto && repeat == RepeatMode.one)) return 0;
    return null;
  }

  int? previousIndex() {
    if (_items.isEmpty) return null;
    if (_index > 0) return _index - 1;
    if (repeat != RepeatMode.off) return _items.length - 1;
    return null;
  }

  void jumpTo(int i) {
    if (i >= 0 && i < _items.length) _index = i;
  }

  void playNext(List<Track> tracks) {
    final entries = tracks.map(_entry).toList();
    _items.insertAll(_index + 1, entries);
    _unshuffled?.insertAll(_unshuffled!.length, entries);
    if (_index < 0) _index = 0;
  }

  void addToQueue(List<Track> tracks) {
    final entries = tracks.map(_entry).toList();
    _items.addAll(entries);
    _unshuffled?.addAll(entries);
    if (_index < 0) _index = 0;
  }

  /// Entfernt einen Eintrag; liefert true, wenn der aktuelle Titel entfernt wurde
  bool removeAt(int i) {
    if (i < 0 || i >= _items.length) return false;
    final removed = _items.removeAt(i);
    _unshuffled?.remove(removed);
    if (i < _index) {
      _index--;
      return false;
    }
    if (i == _index) {
      if (_index >= _items.length) _index = _items.length - 1;
      return true;
    }
    return false;
  }

  void move(int from, int to) {
    if (from < 0 || from >= _items.length) return;
    final cur = current;
    final e = _items.removeAt(from);
    final target = to.clamp(0, _items.length);
    _items.insert(target, e);
    _index = cur == null ? -1 : _items.indexOf(cur);
  }

  void clear() {
    _items = [];
    _unshuffled = null;
    _index = -1;
  }
}

class QueueEntry {
  QueueEntry({required this.uid, required this.track});
  final int uid;
  final Track track;
}
