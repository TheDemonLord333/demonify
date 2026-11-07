import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../network/api_client.dart';
import 'user_paths.dart';

enum CoverSize { thumb, small, medium, large }

/// Lädt Cover authentifiziert vom Server und legt sie im benutzergebundenen Cache ab.
/// Für Downloads werden Cover zusätzlich dauerhaft im Download-Ordner gespeichert (offline verfügbar).
class CoverCache {
  CoverCache(this.paths, this.api);

  final UserPaths paths;
  final ApiClient? api;
  final _inflight = <String, Future<File?>>{};

  File _cacheFile(String id, CoverSize size) => File(p.join(paths.coverCache.path, '$id-${size.name}.jpg'));
  File offlineFile(String id) => File(p.join(paths.coverDir.path, '$id.jpg'));

  /// Sofort verfügbare lokale Datei (ohne Netzwerk), sonst null
  File? localSync(String id, CoverSize size) {
    final c = _cacheFile(id, size);
    if (c.existsSync()) return c;
    final o = offlineFile(id);
    if (o.existsSync()) return o;
    return null;
  }

  Future<File?> get(String id, CoverSize size) {
    final key = '$id-${size.name}';
    return _inflight[key] ??= _load(id, size).whenComplete(() => _inflight.remove(key));
  }

  Future<File?> _load(String id, CoverSize size) async {
    final cached = _cacheFile(id, size);
    if (await cached.exists()) return cached;
    final offline = offlineFile(id);
    if (await offline.exists()) return offline;
    final client = api;
    if (client == null) return null;
    try {
      final tmp = File('${cached.path}.part');
      await client.dio.download('images/$id', tmp.path, queryParameters: {'size': size.name});
      await tmp.rename(cached.path);
      return cached;
    } on DioException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Cover dauerhaft für Offline-Nutzung sichern
  Future<void> keepOffline(String id) async {
    final target = offlineFile(id);
    if (await target.exists()) return;
    final f = await get(id, CoverSize.medium);
    if (f != null) await f.copy(target.path);
  }

  Future<void> clearCache() async {
    if (await paths.coverCache.exists()) await paths.coverCache.delete(recursive: true);
    await paths.coverCache.create(recursive: true);
  }
}
