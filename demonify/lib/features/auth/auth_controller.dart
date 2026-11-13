import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/secure_store.dart';
import '../catalog/models.dart';

class AuthSession {
  AuthSession({required this.api, required this.user, this.offline = false, this.setup = const SetupInfo()});
  final ApiClient api;
  final AppUser user;

  /// Server beim Start nicht erreichbar – gespeicherte Anmeldung wird für Offline-Musik genutzt
  final bool offline;
  final SetupInfo setup;

  /// Ersteinrichtung offen: Startpasswort ändern und/oder E-Mail bestätigen.
  /// Offline nie (heruntergeladene Musik bleibt immer erreichbar).
  bool get needsPasswordSetup => !offline && user.mustChangePassword;
  bool get needsEmailSetup => !offline && setup.emailRequired && !user.emailVerified;
  bool get needsSetup => needsPasswordSetup || needsEmailSetup;

  AuthSession copyWith({AppUser? user, SetupInfo? setup}) => AuthSession(api: api, user: user ?? this.user, offline: offline, setup: setup ?? this.setup);
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
      return AuthSession(api: api, user: user, setup: SetupInfo.fromJson((me['setup'] as Map?)?.cast<String, dynamic>()));
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

  /// Passwort der letzten Anmeldung – nur im Arbeitsspeicher, damit die Ersteinrichtung
  /// (Startpasswort, E-Mail mit erneuter Authentifizierung) nicht erneut danach fragen muss.
  String? _recentPassword;
  String? get recentPassword => _recentPassword;

  /// [identifier]: Anmeldename oder bestätigte E-Mail-Adresse
  Future<void> login({required String server, required String identifier, required String password}) async {
    final apiBase = AppConfig.normalizeApiBase(server);
    final (session, setup) = await ApiClient.login(apiBase: apiBase, identifier: identifier.trim(), password: password, deviceName: _deviceName());
    await AppConfig.saveApiBase(apiBase);
    await _store.write(session);
    final user = AppUser.fromJson(session.user);
    _recentPassword = (user.mustChangePassword || (SetupInfo.fromJson(setup).emailRequired && !user.emailVerified)) ? password : null;
    state = AsyncData(AuthSession(api: _makeClient(session), user: user, setup: SetupInfo.fromJson(setup)));
  }

  void _update(AuthSession Function(AuthSession s) f) {
    final cur = state.value;
    if (cur == null) return;
    final next = f(cur);
    state = AsyncData(next);
    unawaited(_store.write(cur.api.session.copyWith(user: next.user.toJson())));
    if (!next.needsSetup) _recentPassword = null;
  }

  /// Ersteinrichtung: Anzeigename + eigenes Passwort statt Startpasswort
  Future<void> completeSetup({required String displayName, required String currentPassword, required String newPassword}) async {
    final api = state.value?.api;
    if (api == null) return;
    final r = await api.post('me/setup', {'displayName': displayName, 'currentPassword': currentPassword, 'newPassword': newPassword});
    _recentPassword = newPassword;
    _update(
      (s) => s.copyWith(
        user: AppUser.fromJson((r['user'] as Map).cast<String, dynamic>()),
        setup: SetupInfo.fromJson((r['setup'] as Map?)?.cast<String, dynamic>()),
      ),
    );
  }

  /// E-Mail erfassen/ändern (Passwort zur Bestätigung). Aktiv erst nach Klick auf den Link in der Mail.
  Future<String> requestEmail({required String email, required String password}) async {
    final api = state.value?.api;
    if (api == null) throw ApiException(code: 'OFFLINE', message: 'Nicht angemeldet.');
    final r = await api.post('me/email', {'email': email, 'password': password});
    final pending = r['pendingEmail'] as String?;
    _recentPassword ??= password;
    _update((s) => s.copyWith(setup: s.setup.withPending(pending)));
    return pending ?? email;
  }

  /// Konto neu vom Server laden (z. B. nach Bestätigung der E-Mail im Browser)
  Future<void> refreshAccount() async {
    final api = state.value?.api;
    if (api == null) return;
    final me = await api.get('me');
    _update(
      (s) => s.copyWith(
        user: AppUser.fromJson((me['user'] as Map).cast<String, dynamic>()),
        setup: SetupInfo.fromJson((me['setup'] as Map?)?.cast<String, dynamic>()),
      ),
    );
  }

  /// Anzeigename selbst ändern (Anmeldename bleibt)
  Future<void> updateDisplayName(String? name) async {
    final api = state.value?.api;
    if (api == null) return;
    final r = await api.patch('me', {'displayName': (name?.trim().isEmpty ?? true) ? null : name!.trim()});
    _update((s) => s.copyWith(user: AppUser.fromJson((r['user'] as Map).cast<String, dynamic>())));
  }

  /// Erneuter Verbindungsversuch nach Offline-Start
  Future<void> reconnect() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> logout() async {
    _recentPassword = null;
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
