import 'package:shared_preferences/shared_preferences.dart';

/// API-Basisadresse.
///
/// Vorbelegt mit der Produktionsadresse; beim Build überschreibbar:
///   flutter run --dart-define=DEMONIFY_API_BASE=http://192.168.1.20:1340/api/v1/
/// Zusätzlich kann die Serveradresse in der App (Login/Einstellungen) geändert werden.
/// Es werden keine Secrets in Build-Parametern oder im Quellcode hinterlegt.
class AppConfig {
  static const String defaultApiBase = String.fromEnvironment(
    'DEMONIFY_API_BASE',
    defaultValue: 'https://demonify.thedemonlord333.me/api/v1/',
  );

  static const _prefsKey = 'server.apiBase';

  /// Normalisiert Eingaben wie "demonify.example.org" oder "https://host/" zu ".../api/v1/".
  static String normalizeApiBase(String input) {
    var s = input.trim();
    if (s.isEmpty) return defaultApiBase;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    final uri = Uri.parse(s);
    var path = uri.path;
    if (!path.contains('/api/v1')) {
      path = '${path.endsWith('/') ? path.substring(0, path.length - 1) : path}/api/v1/';
    }
    if (!path.endsWith('/')) path = '$path/';
    return uri.replace(path: path, query: null, fragment: null).toString();
  }

  static Future<String> loadApiBase() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey) ?? defaultApiBase;
  }

  static Future<void> saveApiBase(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, normalizeApiBase(value));
  }

  /// Ursprung (Schema + Host + Port) zur Auflösung relativer Pfade wie "/api/v1/stream/…"
  static String originOf(String apiBase) {
    final u = Uri.parse(apiBase);
    return u.replace(path: '', query: null, fragment: null).toString().replaceAll(RegExp(r'/$'), '');
  }
}
