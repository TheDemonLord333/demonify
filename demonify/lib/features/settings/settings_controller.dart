import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_controller.dart';

/// Streaming-/Downloadqualität. "original" liefert die Originaldatei (alle Formate werden
/// von der Audioengine auf Android/iOS/Windows dekodiert); andere Stufen sind AAC-Transkodierungen.
enum AudioQuality {
  original('original'),
  high('high'),
  normal('normal'),
  low('low');

  const AudioQuality(this.api);
  final String api;
  static AudioQuality parse(String? s) => AudioQuality.values.firstWhere((q) => q.api == s, orElse: () => AudioQuality.original);
}

class UserSettings {
  const UserSettings({this.streamingQuality = AudioQuality.original, this.downloadQuality = AudioQuality.original});
  final AudioQuality streamingQuality;
  final AudioQuality downloadQuality;

  UserSettings copyWith({AudioQuality? streamingQuality, AudioQuality? downloadQuality}) =>
      UserSettings(streamingQuality: streamingQuality ?? this.streamingQuality, downloadQuality: downloadQuality ?? this.downloadQuality);

  Map<String, dynamic> toJson() => {'streamingQuality': streamingQuality.api, 'downloadQuality': downloadQuality.api};
  factory UserSettings.fromJson(Map<String, dynamic> j) => UserSettings(
        streamingQuality: AudioQuality.parse(j['streamingQuality'] as String?),
        downloadQuality: AudioQuality.parse(j['downloadQuality'] as String?),
      );
}

final settingsProvider = NotifierProvider<SettingsController, UserSettings>(SettingsController.new);

/// Benutzerbezogene Einstellungen: auf dem Server gespeichert, lokal zwischengespeichert (offline).
class SettingsController extends Notifier<UserSettings> {
  String? get _key {
    final id = ref.read(currentUserProvider)?.id;
    return id == null ? null : 'settings.$id';
  }

  @override
  UserSettings build() {
    ref.watch(currentUserProvider.select((u) => u?.id));
    Future.microtask(_load);
    return const UserSettings();
  }

  Future<void> _load() async {
    final key = _key;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw != null) state = UserSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final api = ref.read(apiProvider);
    if (api == null) return;
    try {
      final res = await api.get('me/settings');
      state = UserSettings.fromJson(res['settings'] as Map<String, dynamic>);
      await prefs.setString(key, jsonEncode(state.toJson()));
    } catch (_) {
      // offline → lokaler Stand
    }
  }

  Future<void> update(UserSettings next) async {
    state = next;
    final key = _key;
    if (key != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(next.toJson()));
    }
    try {
      await ref.read(apiProvider)?.put('me/settings', next.toJson());
    } catch (_) {
      // wird beim nächsten Laden erneut vom Server gelesen
    }
  }
}
