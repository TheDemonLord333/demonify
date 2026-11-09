import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/secure_store.dart';
import 'api_exception.dart';

/// Zentrale API-Anbindung: Timeouts, Bearer-Token, sichere Token-Erneuerung (Single-Flight)
/// und einheitliche Fehler. Die App spricht ausschließlich über diese API mit dem Server.
class ApiClient {
  ApiClient({required StoredSession session, required this.store, required this.onSessionExpired})
      : _session = session,
        dio = Dio(BaseOptions(
          baseUrl: session.apiBase,
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 30),
          responseType: ResponseType.json,
          headers: {'accept': 'application/json'},
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.extra['noAuth'] == true) return handler.next(options);
        try {
          final token = await validAccessToken();
          options.headers['authorization'] = 'Bearer $token';
          handler.next(options);
        } on ApiException catch (e) {
          handler.reject(DioException(requestOptions: options, error: e, type: DioExceptionType.unknown));
        }
      },
      onError: (err, handler) async {
        final retried = err.requestOptions.extra['retried'] == true;
        if (err.response?.statusCode == 401 && !retried && err.requestOptions.extra['noAuth'] != true) {
          try {
            await _refresh(force: true);
            final opts = err.requestOptions..extra['retried'] = true;
            opts.headers['authorization'] = 'Bearer ${_session.accessToken}';
            final res = await dio.fetch<dynamic>(opts);
            return handler.resolve(res);
          } catch (_) {
            // fällt durch zum Fehler
          }
        }
        handler.next(err);
      },
    ));
  }

  final Dio dio;
  final SecureStore store;
  StoredSession _session;
  Future<void>? _refreshing;
  final void Function() onSessionExpired;

  StoredSession get session => _session;
  String get apiBase => _session.apiBase;
  String get origin => AppConfig.originOf(_session.apiBase);

  /// Absolute URL für relative Serverpfade wie "/api/v1/stream/…"
  String absolute(String pathOrUrl) => pathOrUrl.startsWith('http') ? pathOrUrl : '$origin$pathOrUrl';

  Future<String> validAccessToken() async {
    if (_session.accessExpiresAt.isBefore(DateTime.now().add(const Duration(seconds: 30)))) {
      await _refresh();
    }
    return _session.accessToken;
  }

  Future<void> _refresh({bool force = false}) {
    if (!force && _session.accessExpiresAt.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return Future.value();
    }
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    try {
      final res = await dio.post<Map<String, dynamic>>(
        'auth/refresh',
        data: {'refreshToken': _session.refreshToken},
        options: Options(extra: {'noAuth': true}),
      );
      final d = res.data!;
      _session = _session.copyWith(
        accessToken: d['accessToken'] as String,
        accessExpiresAt: DateTime.parse(d['accessTokenExpiresAt'] as String),
        refreshToken: d['refreshToken'] as String,
        user: (d['user'] as Map).cast<String, dynamic>(),
      );
      await store.write(_session);
    } on DioException catch (e) {
      final ex = ApiException.fromDio(e);
      if (ex.status == 401 || ex.status == 403) {
        onSessionExpired();
      }
      throw ex;
    }
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query, CancelToken? cancel}) =>
      _wrap(() => dio.get<dynamic>(path, queryParameters: query, cancelToken: cancel));
  Future<Map<String, dynamic>> post(String path, [Object? body]) => _wrap(() => dio.post<dynamic>(path, data: body ?? {}));
  Future<Map<String, dynamic>> put(String path, [Object? body]) => _wrap(() => dio.put<dynamic>(path, data: body ?? {}));
  Future<Map<String, dynamic>> patch(String path, Object body) => _wrap(() => dio.patch<dynamic>(path, data: body));
  Future<Map<String, dynamic>> delete(String path, [Object? body]) => _wrap(() => dio.delete<dynamic>(path, data: body));

  Future<Map<String, dynamic>> _wrap(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      // HTML statt JSON (z. B. falsch konfigurierter Proxy) nicht als Erfolg werten
      throw ApiException(code: 'UNEXPECTED_RESPONSE', message: 'Unerwartete Serverantwort. Stimmt die Serveradresse?', status: res.statusCode);
    } on DioException catch (e) {
      if (e.error is ApiException) throw e.error as ApiException;
      throw ApiException.fromDio(e);
    }
  }

  /// Anmeldung ohne bestehende Session
  static Future<StoredSession> login({
    required String apiBase,
    required String username,
    required String password,
    required String deviceName,
  }) async {
    final dio = Dio(BaseOptions(
      baseUrl: apiBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'accept': 'application/json'},
    ));
    try {
      final res = await dio.post<dynamic>('auth/login', data: {
        'username': username,
        'password': password,
        'client': 'app',
        'deviceName': deviceName,
      });
      final d = res.data;
      if (d is! Map<String, dynamic> || d['accessToken'] == null) {
        throw ApiException(code: 'UNEXPECTED_RESPONSE', message: 'Unerwartete Serverantwort. Stimmt die Serveradresse?');
      }
      return StoredSession(
        apiBase: apiBase,
        accessToken: d['accessToken'] as String,
        accessExpiresAt: DateTime.parse(d['accessTokenExpiresAt'] as String),
        refreshToken: d['refreshToken'] as String,
        user: (d['user'] as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } finally {
      dio.close();
    }
  }

  static Future<void> redeemInvite({
    required String apiBase,
    required String code,
    required String username,
    required String password,
    String? displayName,
  }) async {
    final dio = Dio(BaseOptions(baseUrl: apiBase, connectTimeout: const Duration(seconds: 10)));
    try {
      await dio.post<dynamic>('auth/invites/redeem', data: {
        'code': code,
        'username': username,
        'password': password,
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } finally {
      dio.close();
    }
  }

  void close() => dio.close(force: true);
}
