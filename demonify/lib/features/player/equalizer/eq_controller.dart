import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_controller.dart';
import '../player_providers.dart';
import 'eq_model.dart';

final equalizerProvider = NotifierProvider<EqController, EqSettings>(EqController.new);

/// Equalizer-Einstellungen – lokal pro Benutzer und Gerät gespeichert und unmittelbar
/// (entprellt) auf die laufende Wiedergabe angewendet.
class EqController extends Notifier<EqSettings> {
  Timer? _applyTimer;
  Timer? _saveTimer;

  String? get _key {
    final id = ref.read(currentUserProvider)?.id;
    return id == null ? null : 'eq.$id';
  }

  @override
  EqSettings build() {
    ref.watch(currentUserProvider.select((u) => u?.id));
    ref.onDispose(() {
      _applyTimer?.cancel();
      _saveTimer?.cancel();
    });
    Future.microtask(_load);
    return const EqSettings();
  }

  Future<void> _load() async {
    final key = _key;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    final s = raw == null ? const EqSettings() : EqSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    state = s;
    await ref.read(playerProvider).applyEqualizer(s);
  }

  void _set(EqSettings s, {bool immediate = false}) {
    state = s;
    _applyTimer?.cancel();
    // Kurze Entprellung beim Ziehen der Regler: die Filterkette wird nicht bei jedem Pixel neu aufgebaut
    _applyTimer = Timer(Duration(milliseconds: immediate ? 0 : 60), () => ref.read(playerProvider).applyEqualizer(state));
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      final key = _key;
      if (key == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(state.toJson()));
    });
  }

  void setEnabled(bool on) => _set(state.copyWith(enabled: on), immediate: true);

  void selectPreset(EqPreset p) {
    final gains = p == EqPreset.custom ? state.customGains : p.gains!;
    _set(state.copyWith(preset: p, gains: List.of(gains), enabled: true), immediate: true);
  }

  void setBand(int index, double db) {
    final gains = List.of(state.gains);
    gains[index] = db.clamp(kEqMinDb, kEqMaxDb);
    // Manuelle Änderung → benutzerdefinierte Einstellung (wird automatisch gespeichert)
    _set(state.copyWith(gains: gains, customGains: gains, preset: EqPreset.custom));
  }

  void reset() => _set(state.copyWith(gains: List.filled(kEqFrequencies.length, 0), customGains: List.filled(kEqFrequencies.length, 0), preset: EqPreset.custom), immediate: true);

  void setAutoHeadroom(bool on) => _set(state.copyWith(autoHeadroom: on), immediate: true);

  void setManualPreamp(double db) => _set(state.copyWith(manualPreampDb: db.clamp(kPreampMinDb, kPreampMaxDb)));
}
