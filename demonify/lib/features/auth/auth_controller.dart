import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/secure_store.dart';
import '../catalog/models.dart';

class AuthSession {
  AuthSession({required this.api, required this.user, this.offline = false});
  final ApiClient api;
  final AppUser user;

  /// Server beim Start nicht erreichbar – gespeicherte Anmeldung wird für Offline-Musik genutzt
  final bool offline;
}

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final authProvider = AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

/// Bequemer Zugriff auf den API-Client der aktuellen Sitzung (null, wenn abgemeldet)
final apiProvider = Provider<ApiClient?>((ref) => ref.watch(authProvider).value?.api);

final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(authProvider).value?.user);

class AuthController extends AsyncNotifier<AuthSession?> {
  SecureStore get _store => ref.read(secureStoreProvider);

  @override
  Future<AuthSession?> build() async {
    final stored = await _store.read();
    if (stored == null) return null;
    final api = _makeClient(stored);
    final cachedUser = AppUser.fromJson(stored.user);
    try {
      final me = await api.get('me');
      final user = AppUser.fromJson(me['user'] as Map<String, dynamic>);
      await _store.write(api.session.copyWith(user: user.toJson()));
      return AuthSession(api: api, user: user);
    } on ApiException catch (e) {
      if (e.isNetwork || (e.status ?? 0) >= 500) {
        // Offline: gespeicherte Sitzung verwenden, damit heruntergeladene Musik spielbar bleibt
        return AuthSession(api: api, user: cachedUser, offline: true);
      }
      if (e.status == 401 || e.status == 403) {
        await _store.clear();
        return null;
      }
      return AuthSession(api: api, user: cachedUser, offline: true);
    }
  }

  ApiClient _makeClient(StoredSession s) => ApiClient(
        session: s,
        store: _store,
        onSessionExpired: () {
          // Refresh-Token ungültig/widerrufen → abmelden (Downloads bleiben, bis der Benutzer entscheidet)
          _store.clear();
          state = const AsyncData(null);
        },
      );

  Future<void> login({required String server, required String username, required String password}) async {
    final apiBase = AppConfig.normalizeApiBase(server);
    final session = await ApiClient.login(
      apiBase: apiBase,
      username: username.trim(),
      password: password,
      deviceName: _deviceName(),
    );
    await AppConfig.saveApiBase(apiBase);
    await _store.write(session);
    state = AsyncData(AuthSession(api: _makeClient(session), user: AppUser.fromJson(session.user)));
  }

  /// Erneuter Verbindungsversuch nach Offline-Start
  Future<void> reconnect() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> logout() async {
    final current = state.value;
    if (current != null) {
      try {
        await current.api.post('auth/logout');
      } catch (_) {
        // Server nicht erreichbar – lokale Abmeldung trotzdem durchführen
      }
      current.api.close();
    }
    await _store.clear();
    state = const AsyncData(null);
  }

  /// Schritt 1: Eigenes Konto auf dem Server endgültig löschen (Passwort zur Bestätigung).
  /// Die Sitzung bleibt lokal noch bestehen, damit der Aufrufer die lokalen Daten
  /// dieses Kontos (Downloads, Warteschlange, Einstellungen) entfernen kann.
  Future<void> deleteAccountOnServer(String password) async {
    final current = state.value;
    if (current == null) return;
    await current.api.delete('me', {'password': password});
  }

  /// Schritt 2: Nach dem Aufräumen lokal abmelden.
  Future<void> finishDeletedAccount() async {
    state.value?.api.close();
    await _store.clear();
    state = const AsyncData(null);
  }

  static String _deviceName() {
    final os = Platform.operatingSystem;
    final name = switch (os) {
      'android' => 'Android',
      'ios' => 'iPhone/iPad',
      'windows' => 'Windows',
      'macos' => 'macOS',
      _ => os,
    };
    return 'Demonify-App ($name)';
  }
}
