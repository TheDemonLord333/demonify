import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/network/api_exception.dart';
import '../../core/storage/providers.dart';
import '../../core/storage/user_paths.dart';
import '../auth/auth_controller.dart';
import '../catalog/models.dart';
import '../settings/settings_controller.dart';
import 'download_models.dart';

final downloadsProvider = NotifierProvider<DownloadManager, DownloadsState>(DownloadManager.new);

/// Offline-Downloads im privaten App-Speicher, eindeutig dem angemeldeten Benutzer zugeordnet.
/// Originaldateien bzw. Serverdateien werden unverändert gespeichert (der Equalizer wirkt nur
/// bei der Wiedergabe, nie auf die Datei).
class DownloadManager extends Notifier<DownloadsState> {
  static const _maxParallel = 2;
  final _cancelTokens = <String, CancelToken>{};
  final _active = <String>{};
  UserPaths? _paths;
  Timer? _saveTimer;

  @override
  DownloadsState build() {
    final paths = ref.watch(userPathsProvider).value;
    _paths = paths;
    ref.onDispose(() {
      for (final t in _cancelTokens.values) {
        t.cancel();
      }
      _saveTimer?.cancel();
    });
    if (paths != null) Future.microtask(() => _load(paths));
    return const DownloadsState();
  }

  Future<void> _load(UserPaths paths) async {
    try {
      final f = paths.indexFile;
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final items = <String, DownloadItem>{};
        for (final e in ((j['items'] as Map?) ?? {}).entries) {
          final item = DownloadItem.fromJson((e.value as Map).cast<String, dynamic>());
          // Datei muss tatsächlich vorhanden sein
          if (item.status == DownloadStatus.done && (item.fileName == null || !File(p.join(paths.downloads.path, item.fileName!)).existsSync())) {
            items[e.key as String] = item.copyWith(status: DownloadStatus.queued, progress: 0);
          } else {
            items[e.key as String] = item;
          }
        }
        final cols = <String, DownloadCollection>{};
        for (final c in ((j['collections'] as List?) ?? const [])) {
          final col = DownloadCollection.fromJson((c as Map).cast<String, dynamic>());
          cols[col.key] = col;
        }
        state = DownloadsState(items: items, collections: cols, loaded: true);
      } else {
        state = state.copyWith(loaded: true);
      }
    } catch (_) {
      state = state.copyWith(loaded: true);
    }
    _pump();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final paths = _paths;
    if (paths == null) return;
    final data = {
      'version': 1,
      'items': state.items.map((k, v) => MapEntry(k, v.toJson())),
      'collections': state.collections.values.map((c) => c.toJson()).toList(),
    };
    final tmp = File('${paths.indexFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(paths.indexFile.path);
  }

  /// Lokale Datei eines heruntergeladenen Tracks (oder null)
  File? localFile(String trackId) {
    final item = state.items[trackId];
    final paths = _paths;
    if (item == null || item.status != DownloadStatus.done || item.fileName == null || paths == null) return null;
    final f = File(p.join(paths.downloads.path, item.fileName!));
    return f.existsSync() ? f : null;
  }

  void downloadTracks(List<Track> tracks, {bool explicit = true}) {
    final items = Map<String, DownloadItem>.from(state.items);
    for (final t in tracks) {
      if (!t.available) continue;
      final existing = items[t.id];
      if (existing == null) {
        items[t.id] = DownloadItem(track: t, status: DownloadStatus.queued, explicit: explicit);
      } else {
        items[t.id] = existing.copyWith(
          track: t,
          explicit: existing.explicit || explicit,
          status: existing.status == DownloadStatus.failed ? DownloadStatus.queued : existing.status,
        );
      }
    }
    state = state.copyWith(items: items);
    _scheduleSave();
    _pump();
  }

  void downloadRelease(ReleaseDetail d) {
    _addCollection(DownloadCollection(
      kind: 'release',
      id: d.release.id,
      title: d.release.title,
      subtitle: d.release.albumArtist.name,
      coverImageId: d.release.coverImageId,
      trackIds: d.tracks.where((t) => t.available).map((t) => t.id).toList(),
    ));
    downloadTracks(d.tracks, explicit: false);
  }

  void downloadPlaylist(PlaylistDetail d) {
    _addCollection(DownloadCollection(
      kind: 'playlist',
      id: d.playlist.id,
      title: d.playlist.name,
      coverImageId: d.playlist.coverImageIds.isEmpty ? null : d.playlist.coverImageIds.first,
      trackIds: d.entries.where((e) => e.track.available).map((e) => e.track.id).toList(),
    ));
    downloadTracks(d.entries.map((e) => e.track).toList(), explicit: false);
  }

  void _addCollection(DownloadCollection c) {
    state = state.copyWith(collections: {...state.collections, c.key: c});
    final cache = ref.read(coverCacheProvider);
    if (c.coverImageId != null) unawaited(cache?.keepOffline(c.coverImageId!));
  }

  Future<void> removeCollection(String kind, String id) async {
    final key = '$kind:$id';
    final col = state.collections[key];
    if (col == null) return;
    final cols = Map<String, DownloadCollection>.from(state.collections)..remove(key);
    state = state.copyWith(collections: cols);
    final stillNeeded = cols.values.expand((c) => c.trackIds).toSet();
    for (final t in col.trackIds) {
      final item = state.items[t];
      if (item != null && !item.explicit && !stillNeeded.contains(t)) await remove(t, force: true);
    }
    _scheduleSave();
  }

  Future<void> remove(String trackId, {bool force = false}) async {
    final item = state.items[trackId];
    if (item == null) return;
    final referenced = state.collections.values.any((c) => c.trackIds.contains(trackId));
    if (referenced && !force) {
      // In einer heruntergeladenen Sammlung enthalten → nur Einzelmarkierung entfernen
      state = state.copyWith(items: {...state.items, trackId: item.copyWith(explicit: false)});
      _scheduleSave();
      return;
    }
    _cancelTokens.remove(trackId)?.cancel();
    final paths = _paths;
    if (paths != null && item.fileName != null) {
      final f = File(p.join(paths.downloads.path, item.fileName!));
      if (await f.exists()) await f.delete();
    }
    final items = Map<String, DownloadItem>.from(state.items)..remove(trackId);
    state = state.copyWith(items: items);
    _scheduleSave();
  }

  void cancel(String trackId) {
    _cancelTokens.remove(trackId)?.cancel();
    final items = Map<String, DownloadItem>.from(state.items)..remove(trackId);
    state = state.copyWith(items: items);
    _scheduleSave();
  }

  void retry(String trackId) {
    final item = state.items[trackId];
    if (item == null) return;
    state = state.copyWith(items: {...state.items, trackId: item.copyWith(status: DownloadStatus.queued, progress: 0)});
    _pump();
  }

  void retryFailed() {
    final items = state.items.map((k, v) => MapEntry(k, v.status == DownloadStatus.failed ? v.copyWith(status: DownloadStatus.queued, progress: 0) : v));
    state = state.copyWith(items: items);
    _pump();
  }

  /// Alle Downloads dieses Benutzers löschen (z. B. beim Abmelden)
  Future<void> removeAll() async {
    for (final t in _cancelTokens.values) {
      t.cancel();
    }
    _cancelTokens.clear();
    final paths = _paths;
    if (paths != null && await paths.downloads.exists()) {
      await paths.downloads.delete(recursive: true);
    }
    state = const DownloadsState(loaded: true);
  }

  void _pump() {
    if (_paths == null) return;
    final queued = state.items.values.where((i) => i.status == DownloadStatus.queued && !_active.contains(i.track.id)).toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    for (final item in queued) {
      if (_active.length >= _maxParallel) break;
      _active.add(item.track.id);
      unawaited(_download(item.track).whenComplete(() {
        _active.remove(item.track.id);
        _pump();
      }));
    }
  }

  void _update(String id, DownloadItem Function(DownloadItem) f) {
    final cur = state.items[id];
    if (cur == null) return;
    state = state.copyWith(items: {...state.items, id: f(cur)});
  }

  Future<void> _download(Track track) async {
    final api = ref.read(apiProvider);
    final paths = _paths;
    if (api == null || paths == null) return;
    final cancel = CancelToken();
    _cancelTokens[track.id] = cancel;
    _update(track.id, (i) => i.copyWith(status: DownloadStatus.downloading, progress: 0));
    final quality = ref.read(settingsProvider).downloadQuality.api;
    final tmp = File(p.join(paths.audioDir.path, '${track.id}.part'));
    try {
      final res = await api.post('tracks/${track.id}/stream-url', {'quality': quality});
      final url = api.absolute(res['url'] as String);
      var lastTick = DateTime.now();
      final response = await api.dio.download(
        url,
        tmp.path,
        cancelToken: cancel,
        options: Options(extra: {'noAuth': true}, receiveTimeout: const Duration(minutes: 5)),
        onReceiveProgress: (received, total) {
          final now = DateTime.now();
          if (total > 0 && now.difference(lastTick).inMilliseconds > 200) {
            lastTick = now;
            _update(track.id, (i) => i.copyWith(progress: received / total));
          }
        },
      );
      final mime = response.headers.value('content-type') ?? '';
      final served = response.headers.value('x-demonify-quality') ?? quality;
      final ext = _extFor(mime);
      final fileName = p.join('audio', '${track.id}$ext');
      final dest = File(p.join(paths.downloads.path, fileName));
      if (await dest.exists()) await dest.delete();
      await tmp.rename(dest.path);
      final bytes = await dest.length();
      // Cover offline sichern (Song- und Veröffentlichungscover)
      final cache = ref.read(coverCacheProvider);
      if (track.coverImageId != null) await cache?.keepOffline(track.coverImageId!);
      if (track.release.coverImageId != null) await cache?.keepOffline(track.release.coverImageId!);
      _update(track.id, (i) => i.copyWith(status: DownloadStatus.done, progress: 1, bytes: bytes, fileName: fileName, quality: served));
    } on DioException catch (e) {
      if (await tmp.exists()) await tmp.delete();
      if (CancelToken.isCancel(e)) return;
      _update(track.id, (i) => i.copyWith(status: DownloadStatus.failed, error: ApiException.fromDio(e).message));
    } on ApiException catch (e) {
      if (await tmp.exists()) await tmp.delete();
      _update(track.id, (i) => i.copyWith(status: DownloadStatus.failed, error: e.message));
    } catch (e) {
      if (await tmp.exists()) await tmp.delete();
      _update(track.id, (i) => i.copyWith(status: DownloadStatus.failed, error: e.toString()));
    } finally {
      _cancelTokens.remove(track.id);
      _scheduleSave();
    }
  }

  static String _extFor(String mime) {
    if (mime.contains('flac')) return '.flac';
    if (mime.contains('mpeg')) return '.mp3';
    if (mime.contains('mp4') || mime.contains('aac')) return '.m4a';
    if (mime.contains('ogg')) return '.ogg';
    if (mime.contains('wav')) return '.wav';
    return '.audio';
  }
}
