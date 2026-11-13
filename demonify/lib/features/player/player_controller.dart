import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_exception.dart';
import '../auth/auth_controller.dart';
import '../catalog/models.dart';
import '../downloads/download_manager.dart';
import '../settings/settings_controller.dart';
import 'audio_engine.dart';
import 'autoplay.dart';
import 'equalizer/eq_model.dart';
import 'queue_model.dart';

/// Herkunft der aktuellen Wiedergabe
enum PlaybackSource { none, local, stream }

class PlayerSnapshot {
  const PlayerSnapshot({
    this.queue = const [],
    this.index = -1,
    this.playing = false,
    this.buffering = false,
    this.loading = false,
    this.duration = Duration.zero,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
    this.error,
    this.source = PlaybackSource.none,
  });

  final List<QueueEntry> queue;
  final int index;
  final bool playing;
  final bool buffering;
  final bool loading;
  final Duration duration;
  final bool shuffle;
  final RepeatMode repeat;
  final String? error;
  final PlaybackSource source;

  Track? get current => index >= 0 && index < queue.length ? queue[index].track : null;
  bool get hasNext => index + 1 < queue.length || repeat != RepeatMode.off;
  bool get hasPrevious => index > 0 || repeat != RepeatMode.off;

  PlayerSnapshot copyWith({
    List<QueueEntry>? queue,
    int? index,
    bool? playing,
    bool? buffering,
    bool? loading,
    Duration? duration,
    bool? shuffle,
    RepeatMode? repeat,
    String? error,
    bool clearError = false,
    PlaybackSource? source,
  }) =>
      PlayerSnapshot(
        queue: queue ?? this.queue,
        index: index ?? this.index,
        playing: playing ?? this.playing,
        buffering: buffering ?? this.buffering,
        loading: loading ?? this.loading,
        duration: duration ?? this.duration,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        error: clearError ? null : (error ?? this.error),
        source: source ?? this.source,
      );
}

class PositionInfo {
  const PositionInfo(this.position, this.buffered, this.duration);
  final Duration position;
  final Duration buffered;
  final Duration duration;
  static const zero = PositionInfo(Duration.zero, Duration.zero, Duration.zero);
}

/// Zentraler Player: Warteschlange, Shuffle, Wiederholung, Quellenwahl (lokal vor Stream),
/// Audiofokus, Equalizer und Wiederherstellung. Lebt unabhängig von der Navigation.
class PlayerController {
  PlayerController(this._ref, this._engine) {
    _subs.addAll([
      _engine.playing.listen((p) => _emit(_state.copyWith(playing: p))),
      _engine.buffering.listen((b) => _emit(_state.copyWith(buffering: b))),
      _engine.duration.listen((d) {
        if (d > Duration.zero) _emit(_state.copyWith(duration: d));
      }),
      _engine.position.listen(_onPosition),
      _engine.buffer.listen((b) {
        _buffered = b;
      }),
      _engine.completed.listen((done) {
        if (done) unawaited(_onCompleted());
      }),
      _engine.errors.listen((e) {
        if (_state.loading || _state.current == null) return;
        _emit(_state.copyWith(error: 'Wiedergabefehler: $e'));
      }),
    ]);
  }

  final Ref _ref;
  final AudioEngine _engine;
  final QueueModel _queue = QueueModel();
  final _subs = <StreamSubscription<dynamic>>[];
  final _stateCtrl = StreamController<PlayerSnapshot>.broadcast();
  final _posCtrl = StreamController<PositionInfo>.broadcast();

  PlayerSnapshot _state = const PlayerSnapshot();
  Duration _position = Duration.zero;
  Duration _buffered = Duration.zero;
  int _loadToken = 0;

  /// Wird bei jeder Änderung der Warteschlange erhöht (Erkennung von Nutzeraktionen während Autoplay)
  int _queueRevision = 0;

  /// Läuft gerade eine Autoplay-Suche? (für UI/Tests)
  bool _autoplaySearching = false;
  bool get autoplaySearching => _autoplaySearching;
  bool _prepared = false;
  Duration _resumeAt = Duration.zero;
  String? _contextType;
  String? _contextId;
  bool _historySent = false;
  Timer? _persistTimer;
  String? _userId;
  AudioSession? _session;
  bool _wasPlayingBeforeInterruption = false;
  double _eqPreampDb = 0;
  double _duckDb = 0;
  EqSettings _eq = const EqSettings();
  bool _eqSupported = true;

  PlayerSnapshot get state => _state;
  Stream<PlayerSnapshot> get stateStream => _stateCtrl.stream;
  Stream<PositionInfo> get positionStream => _posCtrl.stream;
  PositionInfo get positionInfo => PositionInfo(_position, _buffered, _state.duration);
  bool get equalizerSupported => _eqSupported;

  void _emit(PlayerSnapshot s) {
    _state = s;
    _stateCtrl.add(s);
  }

  void _syncQueue({int? index}) {
    _queueRevision++;
    _emit(_state.copyWith(queue: _queue.items, index: index ?? _queue.index, shuffle: _queue.shuffle, repeat: _queue.repeat));
    _schedulePersist();
  }

  // ───────────────────────── Audio-Sitzung (Fokus, Anrufe, Kopfhörer)

  Future<void> initSession() async {
    final session = await AudioSession.instance;
    _session = session;
    await session.configure(const AudioSessionConfiguration.music());
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _duckDb = -12;
            unawaited(_applyGain());
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            _wasPlayingBeforeInterruption = _state.playing;
            if (_state.playing) unawaited(pause());
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _duckDb = 0;
            unawaited(_applyGain());
          case AudioInterruptionType.pause:
            // z. B. nach einem Anruf fortsetzen, wenn vorher gespielt wurde
            if (_wasPlayingBeforeInterruption) unawaited(play());
            _wasPlayingBeforeInterruption = false;
          case AudioInterruptionType.unknown:
            _wasPlayingBeforeInterruption = false;
        }
      }
    });
    // Kopfhörer abgezogen / Bluetooth getrennt → pausieren
    session.becomingNoisyEventStream.listen((_) {
      if (_state.playing) unawaited(pause());
    });
  }

  // ───────────────────────── Öffentliche Steuerung

  Future<void> playTracks(List<Track> tracks, {int index = 0, bool shuffle = false, String? contextType, String? contextId}) async {
    final playable = tracks.where((t) => t.available).toList();
    if (playable.isEmpty) return;
    final start = index < tracks.length ? playable.indexOf(tracks[index]) : 0;
    _queue.setQueue(playable, startIndex: start < 0 ? 0 : start, shuffled: shuffle);
    _contextType = contextType;
    _contextId = contextId;
    _syncQueue();
    await _loadCurrent(autoplay: true);
  }

  Future<void> play() async {
    if (_state.current == null) return;
    await _session?.setActive(true);
    if (!_prepared) {
      await _loadCurrent(autoplay: true, start: _resumeAt);
      return;
    }
    await _engine.play();
  }

  Future<void> pause() => _engine.pause();

  Future<void> togglePlay() => _state.playing ? pause() : play();

  Future<void> stop() async {
    await _engine.stop();
    _prepared = false;
    _emit(_state.copyWith(playing: false));
    await _session?.setActive(false);
  }

  Future<void> seek(Duration position) async {
    if (!_prepared) {
      _resumeAt = position;
      _position = position;
      _posCtrl.add(positionInfo);
      return;
    }
    await _engine.seek(position);
  }

  Future<void> next() async {
    final i = _queue.nextIndex();
    if (i == null) return;
    _queue.jumpTo(i);
    _syncQueue();
    await _loadCurrent(autoplay: true);
  }

  /// Wie bei Spotify: nach 3 Sekunden springt „Zurück“ an den Titelanfang
  Future<void> previous() async {
    if (_position > const Duration(seconds: 3) || _queue.previousIndex() == null) {
      await seek(Duration.zero);
      return;
    }
    _queue.jumpTo(_queue.previousIndex()!);
    _syncQueue();
    await _loadCurrent(autoplay: true);
  }

  Future<void> jumpTo(int index) async {
    _queue.jumpTo(index);
    _syncQueue();
    await _loadCurrent(autoplay: true);
  }

  void setShuffle(bool on) {
    _queue.setShuffle(on);
    _syncQueue();
  }

  void cycleRepeat() {
    _queue.cycleRepeat();
    _syncQueue();
  }

  void setRepeat(RepeatMode mode) {
    while (_queue.repeat != mode) {
      _queue.cycleRepeat();
    }
    _syncQueue();
  }

  Future<void> playNext(List<Track> tracks) async {
    final wasEmpty = _queue.isEmpty;
    _queue.playNext(tracks.where((t) => t.available).toList());
    _syncQueue();
    if (wasEmpty) await _loadCurrent(autoplay: true);
  }

  Future<void> addToQueue(List<Track> tracks) async {
    final wasEmpty = _queue.isEmpty;
    _queue.addToQueue(tracks.where((t) => t.available).toList());
    _syncQueue();
    if (wasEmpty) await _loadCurrent(autoplay: true);
  }

  Future<void> removeAt(int index) async {
    final wasCurrent = _queue.removeAt(index);
    _syncQueue();
    if (_queue.isEmpty) {
      await stop();
    } else if (wasCurrent) {
      await _loadCurrent(autoplay: _state.playing);
    }
  }

  void move(int from, int to) {
    _queue.move(from, to);
    _syncQueue();
  }

  Future<void> clear() async {
    _queue.clear();
    await stop();
    _syncQueue(index: -1);
  }

  // ───────────────────────── Laden & Quellenwahl

  /// Lokale Datei (Download) hat immer Vorrang – auch ohne Netz. Sonst kurzlebige Streaming-URL.
  Future<(String, PlaybackSource)> _resolveUri(Track t) async {
    final local = _ref.read(downloadsProvider.notifier).localFile(t.id);
    if (local != null) return (Uri.file(local.path).toString(), PlaybackSource.local);
    final api = _ref.read(apiProvider);
    if (api == null) throw ApiException(code: 'OFFLINE', message: 'Nicht angemeldet.');
    final quality = _ref.read(settingsProvider).streamingQuality.api;
    try {
      final res = await api.post('tracks/${t.id}/stream-url', {'quality': quality});
      return (api.absolute(res['url'] as String), PlaybackSource.stream);
    } on ApiException catch (e) {
      if (e.isNetwork) {
        throw ApiException(code: 'OFFLINE', message: '„${t.title}“ ist nicht heruntergeladen und der Server ist nicht erreichbar.');
      }
      rethrow;
    }
  }

  Future<void> _loadCurrent({required bool autoplay, Duration start = Duration.zero, int skipBudget = -1}) async {
    final entry = _queue.current;
    if (entry == null) return;
    final token = ++_loadToken;
    _prepared = false;
    _historySent = false;
    _position = start;
    _posCtrl.add(positionInfo);
    _emit(_state.copyWith(loading: true, clearError: true, duration: entry.track.duration));
    try {
      final (uri, source) = await _resolveUri(entry.track);
      if (token != _loadToken) return; // inzwischen anderer Titel gewählt
      if (autoplay) await _session?.setActive(true);
      await _engine.open(uri, play: autoplay, start: start);
      if (token != _loadToken) return;
      _prepared = true;
      _resumeAt = Duration.zero;
      await _applyEq();
      _emit(_state.copyWith(loading: false, source: source));
    } catch (e) {
      if (token != _loadToken) return;
      _emit(_state.copyWith(loading: false, error: errorText(e), playing: false));
      // Beim automatischen Weiterschalten nicht abspielbare Titel überspringen (z. B. offline)
      final budget = skipBudget < 0 ? _queue.items.length - 1 : skipBudget;
      if (autoplay && budget > 0) {
        final nextI = _queue.nextIndex();
        if (nextI != null && nextI != _queue.index) {
          _queue.jumpTo(nextI);
          _syncQueue();
          await _loadCurrent(autoplay: true, skipBudget: budget - 1);
        }
      }
    }
  }

  Future<void> _onCompleted() async {
    // Nur reguläres Titelende: nach Stopp/Fehler/Laden kein Weiterschalten und kein Autoplay
    if (!_prepared || _state.loading || _state.error != null) return;
    if (_queue.repeat == RepeatMode.one) {
      await _engine.seek(Duration.zero);
      await _engine.play();
      _historySent = false;
      return;
    }
    final i = _queue.nextIndex(auto: true);
    if (i == null) {
      // Ende der Warteschlange (Wiederholen aus): anhalten, Position zurücksetzen
      final finished = _queue.current?.track;
      await _engine.pause();
      _prepared = false;
      _resumeAt = Duration.zero;
      _position = Duration.zero;
      _posCtrl.add(positionInfo);
      if (finished != null) await _autoplayAfter(finished);
      return;
    }
    _queue.jumpTo(i);
    _syncQueue();
    await _loadCurrent(autoplay: true);
  }

  /// Autoplay: einen zufälligen, ähnlichen Titel anhängen und spielen. Startet der Nutzer währenddessen
  /// etwas anderes (Warteschlange oder Ladevorgang geändert), wird das Ergebnis verworfen.
  Future<void> _autoplayAfter(Track finished) async {
    final revision = _queueRevision;
    final token = _loadToken;
    bool userActed() => revision != _queueRevision || token != _loadToken || _state.playing;
    _autoplaySearching = true;
    List<Track> candidates;
    try {
      final recent = _queue.items.reversed.take(100).map((e) => e.track.id).toList();
      candidates = await _ref.read(autoplaySourceProvider).candidates(finished, recentIds: recent);
    } catch (_) {
      candidates = const [];
    } finally {
      _autoplaySearching = false;
    }
    if (userActed()) return;
    final next = candidates.where((t) => t.available && t.id != finished.id).firstOrNull;
    if (next == null) return; // nichts Passendes → Wiedergabe endet regulär
    _queue.addToQueue([next]);
    _queue.jumpTo(_queue.items.length - 1);
    _contextType = 'autoplay';
    _contextId = finished.id;
    _syncQueue();
    await _loadCurrent(autoplay: true);
  }

  void _onPosition(Duration p) {
    if (!_prepared) return;
    _position = p;
    _posCtrl.add(positionInfo);
    final dur = _state.duration;
    if (!_historySent && dur > Duration.zero && (p >= const Duration(seconds: 30) || p.inMilliseconds >= dur.inMilliseconds * 0.5)) {
      _historySent = true;
      unawaited(_reportHistory(_state.current));
    }
    _schedulePersist();
  }

  // ───────────────────────── Hörverlauf (offline nachreichen)

  Future<void> _reportHistory(Track? t) async {
    if (t == null) return;
    final entry = {
      'trackId': t.id,
      'playedAt': DateTime.now().toUtc().toIso8601String(),
      if (_contextType != null) 'contextType': _contextType,
      if (_contextId != null) 'contextId': _contextId,
    };
    final prefs = await SharedPreferences.getInstance();
    final key = 'history.pending.${_userId ?? 'x'}';
    final pending = (prefs.getStringList(key) ?? [])..add(jsonEncode(entry));
    await prefs.setStringList(key, pending.length > 500 ? pending.sublist(pending.length - 500) : pending);
    await flushHistory();
  }

  Future<void> flushHistory() async {
    final api = _ref.read(apiProvider);
    if (api == null || _userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'history.pending.$_userId';
    final pending = prefs.getStringList(key) ?? [];
    final remaining = <String>[];
    for (var i = 0; i < pending.length; i++) {
      try {
        await api.post('library/history', jsonDecode(pending[i]));
      } on ApiException catch (e) {
        if (e.isNetwork) {
          remaining.addAll(pending.sublist(i));
          break;
        }
        // Ungültige Einträge (z. B. gelöschter Titel) verwerfen
      }
    }
    await prefs.setStringList(key, remaining);
  }

  // ───────────────────────── Equalizer & Lautstärke

  Future<void> applyEqualizer(EqSettings eq) async {
    _eq = eq;
    _eqPreampDb = eq.effectivePreampDb;
    await _applyEq();
  }

  Future<void> _applyEq() async {
    _eqSupported = await _engine.setAudioFilter(_eq.filterString);
    await _applyGain();
  }

  Future<void> _applyGain() => _engine.setGainDb(_eqPreampDb + _duckDb);

  // ───────────────────────── Benutzerwechsel & Wiederherstellung

  /// Bei Anmeldung/Abmeldung: Warteschlange des Benutzers laden bzw. leeren
  Future<void> onUserChanged(String? userId) async {
    if (userId == _userId) return;
    await _persistNow();
    _userId = userId;
    _queue.clear();
    await _engine.stop();
    _prepared = false;
    _emit(const PlayerSnapshot());
    if (userId != null) {
      await _restore();
      unawaited(flushHistory());
    }
  }

  void _schedulePersist() {
    if (_persistTimer?.isActive ?? false) return;
    _persistTimer = Timer(const Duration(seconds: 5), _persistNow);
  }

  Future<void> _persistNow() async {
    _persistTimer?.cancel();
    final uid = _userId;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (_queue.isEmpty) {
      await prefs.remove('player.$uid');
      return;
    }
    final data = {
      'queue': _queue.items.map((e) => e.track.toJson()).toList(),
      'unshuffled': _queue.unshuffledTracks?.map((t) => t.toJson()).toList(),
      'index': _queue.index,
      'position': _position.inMilliseconds,
      'shuffle': _queue.shuffle,
      'repeat': _queue.repeat.name,
      'contextType': _contextType,
      'contextId': _contextId,
    };
    await prefs.setString('player.$uid', jsonEncode(data));
  }

  /// Letzte Warteschlange und Position wiederherstellen – ohne automatischen Start
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('player.$_userId');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      List<Track> parse(Object? l) => ((l as List?) ?? const []).map((e) => Track.fromJson((e as Map).cast<String, dynamic>())).toList();
      _queue.restore(
        tracks: parse(j['queue']),
        index: (j['index'] as num?)?.toInt() ?? 0,
        unshuffled: j['unshuffled'] == null ? null : parse(j['unshuffled']),
        shuffle: j['shuffle'] as bool? ?? false,
        repeat: RepeatMode.values.firstWhere((r) => r.name == j['repeat'], orElse: () => RepeatMode.off),
      );
      _contextType = j['contextType'] as String?;
      _contextId = j['contextId'] as String?;
      _resumeAt = Duration(milliseconds: (j['position'] as num?)?.toInt() ?? 0);
      _position = _resumeAt;
      _prepared = false;
      final cur = _queue.current;
      _emit(_state.copyWith(duration: cur?.track.duration ?? Duration.zero));
      _syncQueue();
      _posCtrl.add(positionInfo);
    } catch (_) {
      await prefs.remove('player.$_userId');
    }
  }

  Future<void> dispose() async {
    await _persistNow();
    for (final s in _subs) {
      await s.cancel();
    }
    await _engine.dispose();
  }
}

bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;
