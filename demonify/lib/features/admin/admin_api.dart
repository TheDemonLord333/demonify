import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../auth/auth_controller.dart';
import '../catalog/models.dart';

/// Gleiche Verwaltungs-APIs wie die Webseite (/api/v1/admin/...). Der Server prüft die Adminrolle.
class AdminApi {
  AdminApi(this.api);
  final ApiClient api;

  Future<Map<String, dynamic>> stats() => api.get('admin/stats');

  Future<({List<ArtistRef> items, ArtistRef? exact})> suggestArtists(String q, {CancelToken? cancel}) async {
    final r = await api.get('admin/artists/suggest', query: {'q': q, 'limit': 8}, cancel: cancel);
    return (
      items: (r['items'] as List).map((e) => ArtistRef.fromJson(e as Map<String, dynamic>)).toList(),
      exact: r['exactMatch'] == null ? null : ArtistRef.fromJson(r['exactMatch'] as Map<String, dynamic>),
    );
  }

  Future<({bool exists, ArtistRef? artist, List<ArtistRef> similar})> checkArtist(String name) async {
    final r = await api.get('admin/artists/check', query: {'name': name});
    return (
      exists: r['exists'] as bool,
      artist: r['artist'] == null ? null : ArtistRef.fromJson(r['artist'] as Map<String, dynamic>),
      similar: (r['similar'] as List).map((e) => ArtistRef.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<ArtistRef> createArtist(String name) async {
    final r = await api.post('admin/artists', {'name': name});
    return ArtistRef.fromJson(r['artist'] as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> listArtists({String? q, int offset = 0}) async {
    final r = await api.get('admin/artists', query: {'offset': offset, 'limit': 100, if (q != null && q.isNotEmpty) 'q': q});
    return (r['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> renameArtist(String id, String name) => api.patch('admin/artists/$id', {'name': name});
  Future<void> setArtistImage(String id, String uploadId, Map<String, int>? crop) =>
      api.put('admin/artists/$id/image', {'uploadId': uploadId, 'crop': ?crop});
  Future<void> removeArtistImage(String id) => api.delete('admin/artists/$id/image');

  Future<List<Release>> releases({String? artistId, ReleaseType? type, String? q}) async {
    final r = await api.get('admin/releases', query: {
      'limit': 100,
      'artistId': ?artistId,
      if (type != null) 'type': type.apiName,
      if (q != null && q.isNotEmpty) 'q': q,
    });
    return (r['items'] as List).map((e) => Release.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> releaseDetail(String id) => api.get('admin/releases/$id');
  Future<void> updateRelease(String id, Map<String, dynamic> body) => api.patch('admin/releases/$id', body);
  Future<void> setReleaseCover(String id, String uploadId) => api.put('admin/releases/$id/cover', {'uploadId': uploadId});
  Future<void> setReleaseOrder(String id, List<Map<String, dynamic>> tracks) => api.put('admin/releases/$id/order', {'tracks': tracks});
  Future<void> updateTrack(String id, Map<String, dynamic> body) => api.patch('admin/tracks/$id', body);
  Future<void> setTrackCover(String id, String uploadId) => api.put('admin/tracks/$id/cover', {'uploadId': uploadId});
  Future<void> removeTrackCover(String id) => api.delete('admin/tracks/$id/cover');

  Future<Map<String, dynamic>> commit(Map<String, dynamic> body) => api.post('admin/releases/commit', body);

  Future<List<Map<String, dynamic>>> users() async => ((await api.get('admin/users'))['items'] as List).cast<Map<String, dynamic>>();
  Future<void> createUser(Map<String, dynamic> body) => api.post('admin/users', body);
  Future<void> updateUser(String id, Map<String, dynamic> body) => api.patch('admin/users/$id', body);
  Future<void> revokeSessions(String id) => api.post('admin/users/$id/revoke-sessions');
  Future<List<Map<String, dynamic>>> invites() async => ((await api.get('admin/invites'))['items'] as List).cast<Map<String, dynamic>>();
  Future<String> createInvite({required String role, required int hours, String? note}) async {
    final r = await api.post('admin/invites', {'role': role, 'expiresInHours': hours, if (note != null && note.isNotEmpty) 'note': note});
    return r['link'] as String;
  }

  Future<void> revokeInvite(String id) => api.delete('admin/invites/$id');

  Future<List<Map<String, dynamic>>> jobs() async => ((await api.get('admin/jobs', query: {'limit': 30}))['items'] as List).cast<Map<String, dynamic>>();
  Future<void> startScan() => api.post('admin/library/scan');
  Future<void> cancelJob(String id) => api.post('admin/jobs/$id/cancel');
  Future<List<Map<String, dynamic>>> issues() async => ((await api.get('admin/issues', query: {'limit': 100}))['items'] as List).cast<Map<String, dynamic>>();
  Future<void> resolveIssue(String id) => api.post('admin/issues/$id/resolve');
  Future<List<Map<String, dynamic>>> tracks({bool? available, bool? needsReview}) async {
    final r = await api.get('admin/tracks', query: {
      'limit': 100,
      if (available != null) 'available': '$available',
      if (needsReview != null) 'needsReview': '$needsReview',
    });
    return (r['items'] as List).cast<Map<String, dynamic>>();
  }

  /// Wiederaufnehmbarer Abschnitts-Upload. Abschnitte bleiben unter den Cloudflare-Grenzen.
  Future<UploadResult> upload(
    File file, {
    required String kind,
    required String filename,
    required void Function(double progress, String phase) onProgress,
    CancelToken? cancel,
    String? resumeId,
  }) async {
    final size = await file.length();
    String id;
    int chunk;
    int offset;
    if (resumeId != null) {
      final st = await api.get('admin/uploads/$resumeId');
      final cfg = await api.get('admin/uploads/config');
      id = resumeId;
      chunk = (cfg['chunkSize'] as num).toInt();
      offset = ((st['upload'] as Map)['receivedSize'] as num).toInt();
    } else {
      final r = await api.post('admin/uploads', {'kind': kind, 'filename': filename, 'size': size});
      id = (r['upload'] as Map)['id'] as String;
      chunk = (r['chunkSize'] as num).toInt();
      offset = 0;
    }
    var retries = 0;
    while (offset < size) {
      final end = (offset + chunk).clamp(0, size);
      try {
        final res = await api.dio.put<dynamic>(
          'admin/uploads/$id/content',
          data: file.openRead(offset, end),
          cancelToken: cancel,
          options: Options(
            headers: {
              'content-type': 'application/octet-stream',
              'content-length': end - offset,
              'upload-offset': offset,
            },
            sendTimeout: const Duration(minutes: 5),
          ),
          onSendProgress: (sent, _) => onProgress((offset + sent) / size, 'upload'),
        );
        offset = (((res.data as Map)['upload'] as Map)['receivedSize'] as num).toInt();
        retries = 0;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        final ex = ApiException.fromDio(e);
        if (ex.code == 'OFFSET_MISMATCH') {
          offset = ((ex.details as Map)['receivedSize'] as num).toInt();
          continue;
        }
        if ((ex.isNetwork || (ex.status ?? 0) >= 500) && retries < 5) {
          retries++;
          await Future<void>.delayed(Duration(seconds: 1 << retries));
          final st = await api.get('admin/uploads/$id');
          offset = ((st['upload'] as Map)['receivedSize'] as num).toInt();
          continue;
        }
        throw ex;
      }
    }
    onProgress(1, 'validate');
    final done = await api.post('admin/uploads/$id/complete');
    final u = done['upload'] as Map<String, dynamic>;
    return UploadResult(id: id, valid: u['status'] == 'VALIDATED', error: u['error'] as String?, probe: (u['probe'] as Map?)?.cast<String, dynamic>());
  }

  Future<void> abortUpload(String id) async {
    try {
      await api.delete('admin/uploads/$id');
    } catch (_) {}
  }
}

class UploadResult {
  UploadResult({required this.id, required this.valid, this.error, this.probe});
  final String id;
  final bool valid;
  final String? error;
  final Map<String, dynamic>? probe;
}

final adminApiProvider = Provider<AdminApi?>((ref) {
  final api = ref.watch(apiProvider);
  return api == null ? null : AdminApi(api);
});
