import 'package:dio/dio.dart';

/// Einheitliche Fehlerdarstellung der API: { "error": { "code", "message", "details" } }
class ApiException implements Exception {
  ApiException({required this.code, required this.message, this.status, this.details});

  final String code;
  final String message;
  final int? status;
  final Object? details;

  bool get isNetwork => code == 'NETWORK' || code == 'TIMEOUT';
  bool get isUnauthorized => status == 401;

  factory ApiException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(code: 'TIMEOUT', message: 'Zeitüberschreitung – der Server antwortet nicht.');
      case DioExceptionType.connectionError:
        return ApiException(code: 'NETWORK', message: 'Keine Verbindung zum Server.');
      case DioExceptionType.cancel:
        return ApiException(code: 'CANCELLED', message: 'Abgebrochen.');
      case DioExceptionType.badCertificate:
        return ApiException(code: 'TLS', message: 'Das Serverzertifikat ist ungültig.');
      default:
        break;
    }
    final res = e.response;
    final data = res?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        code: err['code']?.toString() ?? 'ERROR',
        message: err['message']?.toString() ?? 'Unbekannter Fehler.',
        status: res?.statusCode,
        details: err['details'],
      );
    }
    // Keine JSON-Fehlerantwort (z. B. HTML einer falschen Serveradresse) → nicht als Erfolg werten
    return ApiException(
      code: 'HTTP_${res?.statusCode ?? 0}',
      message: res == null
          ? 'Keine Verbindung zum Server.'
          : 'Unerwartete Serverantwort (${res.statusCode}). Stimmt die Serveradresse?',
      status: res?.statusCode,
    );
  }

  @override
  String toString() => message;
}

String errorText(Object e) => e is ApiException ? e.message : e.toString();
