import 'dart:async';
import 'dart:io';

import '../catalog/models.dart';

/// Cover für die Systemmediensteuerung (iOS-Sperrbildschirm/Control Center, Android-Benachrichtigung).
///
/// - Effektives Cover des Titels: individuelles Songcover, sonst Veröffentlichungscover
///   (`Track.coverImageId` liefert der Server bereits so).
/// - Lokal vorhandene Dateien (Cache oder Offline-Kopie eines Downloads) werden sofort verwendet,
///   sonst wird authentifiziert geladen.
/// - Ein verspätet geladenes Bild wird nur übernommen, wenn noch derselbe Titel läuft.
/// - Schlägt das Laden fehl, wird nach [retryDelay] erneut versucht (höchstens [maxAttempts]-mal pro Titel).
class NowPlayingArt {
  NowPlayingArt({
    required this.resolve,
    required this.local,
    required this.onChanged,
    this.retryDelay = const Duration(seconds: 8),
    this.maxAttempts = 4,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// Lädt das Cover (Netz/Cache); null oder Ausnahme = fehlgeschlagen
  final Future<File?> Function(String coverId) resolve;

  /// Sofort verfügbare lokale Datei, sonst null
  final File? Function(String coverId) local;

  /// Cover des aktuellen Titels ist nachträglich verfügbar oder ein neuer Versuch ist fällig
  final void Function() onChanged;
  final Duration retryDelay;
  final int maxAttempts;
  final DateTime Function() _now;

  String? _key;
  Uri? _uri;
  bool _loading = false;
  int _attempts = 0;
  DateTime? _retryAt;
  int _generation = 0;
  Timer? _retryTimer;

  /// Bild für [track] (null, solange keins bekannt ist). Startet bei Bedarf das Laden.
  Uri? artFor(Track track) {
    final id = track.coverImageId ?? track.release.coverImageId;
    final key = '${track.id}:${id ?? '-'}';
    if (key != _key) {
      _key = key;
      _uri = null;
      _loading = false;
      _attempts = 0;
      _retryAt = null;
      _retryTimer?.cancel();
      _generation++;
      if (id != null) {
        final f = local(id);
        if (f != null) _uri = Uri.file(f.path);
      }
    }
    if (_uri == null && id != null && !_loading && _attempts < maxAttempts && (_retryAt == null || !_now().isBefore(_retryAt!))) {
      unawaited(_load(id, _generation));
    }
    return _uri;
  }

  Future<void> _load(String id, int generation) async {
    _loading = true;
    _attempts++;
    File? file;
    try {
      file = await resolve(id) ?? local(id);
    } catch (_) {
      file = local(id);
    }
    // Inzwischen läuft ein anderer Titel → Ergebnis verwerfen
    if (generation != _generation) return;
    _loading = false;
    if (file == null) {
      _retryAt = _now().add(retryDelay);
      if (_attempts < maxAttempts) {
        _retryTimer?.cancel();
        _retryTimer = Timer(retryDelay, () {
          if (generation == _generation) onChanged();
        });
      }
      return;
    }
    _uri = Uri.file(file.path);
    onChanged();
  }

  void dispose() => _retryTimer?.cancel();
}
