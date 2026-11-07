import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Gespeicherte Anmeldung. Tokens liegen ausschließlich im sicheren Plattformspeicher
/// (Android Keystore / iOS Keychain / Windows Credential Manager).
class StoredSession {
  StoredSession({
    required this.apiBase,
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.user,
  });

  final String apiBase;
  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final Map<String, dynamic> user;

  Map<String, dynamic> toJson() => {
        'apiBase': apiBase,
        'accessToken': accessToken,
        'accessExpiresAt': accessExpiresAt.toIso8601String(),
        'refreshToken': refreshToken,
        'user': user,
      };

  factory StoredSession.fromJson(Map<String, dynamic> j) => StoredSession(
        apiBase: j['apiBase'] as String,
        accessToken: j['accessToken'] as String,
        accessExpiresAt: DateTime.parse(j['accessExpiresAt'] as String),
        refreshToken: j['refreshToken'] as String,
        user: (j['user'] as Map).cast<String, dynamic>(),
      );

  StoredSession copyWith({String? accessToken, DateTime? accessExpiresAt, String? refreshToken, Map<String, dynamic>? user}) =>
      StoredSession(
        apiBase: apiBase,
        accessToken: accessToken ?? this.accessToken,
        accessExpiresAt: accessExpiresAt ?? this.accessExpiresAt,
        refreshToken: refreshToken ?? this.refreshToken,
        user: user ?? this.user,
      );
}

class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // Zugriff auch bei gesperrtem Gerät nach erstem Entsperren (Hintergrundwiedergabe),
              // aber nicht in Backups/auf andere Geräte übertragbar.
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _storage;
  static const _key = 'demonify.session';

  Future<StoredSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return StoredSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(StoredSession s) => _storage.write(key: _key, value: jsonEncode(s.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
