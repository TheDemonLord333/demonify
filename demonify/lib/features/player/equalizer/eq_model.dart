import 'dart:math' as math;

/// 10-Band-Equalizer (Oktavbänder 31 Hz – 16 kHz), Verstärkung −12 … +12 dB.
/// Umsetzung: FFmpeg-Filter "equalizer" (Peaking-Biquad, Bandbreite 1 Oktave) in der
/// Audioengine – wirkt auf Streaming und Offline-Wiedergabe, Dateien bleiben unverändert.
const List<int> kEqFrequencies = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
const double kEqMinDb = -12;
const double kEqMaxDb = 12;
const double kPreampMinDb = -12;
const double kPreampMaxDb = 0;

enum EqPreset {
  neutral,
  bassBoost,
  rock,
  pop,
  electronic,
  vocal,
  custom;

  List<double>? get gains => switch (this) {
        EqPreset.neutral => const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        EqPreset.bassBoost => const [6, 5.5, 4.5, 3, 1, 0, 0, 0, 0, 0],
        EqPreset.rock => const [4.5, 3.5, 2, 0, -1.5, -1, 1, 2.5, 3.5, 4],
        EqPreset.pop => const [-1, 0, 1.5, 3, 4, 3, 1.5, 0, -0.5, -1],
        EqPreset.electronic => const [5, 4.5, 2, 0, -1.5, 1, 0.5, 2, 4, 4.5],
        EqPreset.vocal => const [-2, -2, -1, 1, 3.5, 4, 3.5, 2, 0.5, -1],
        EqPreset.custom => null,
      };

  static EqPreset parse(String? s) => EqPreset.values.firstWhere((p) => p.name == s, orElse: () => EqPreset.neutral);
}

class EqSettings {
  const EqSettings({
    this.enabled = false,
    this.preset = EqPreset.neutral,
    this.gains = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.customGains = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.autoHeadroom = true,
    this.manualPreampDb = 0,
  });

  final bool enabled;
  final EqPreset preset;
  final List<double> gains;

  /// Zuletzt eingestellte benutzerdefinierte Kurve (wird automatisch gespeichert)
  final List<double> customGains;

  /// Automatischer Headroom: Vorverstärkung = −(höchste Anhebung) → keine Übersteuerung an den Bandmitten
  final bool autoHeadroom;
  final double manualPreampDb;

  double get maxBoost => gains.fold<double>(0, (m, g) => math.max(m, g));
  double get preampDb => autoHeadroom ? -maxBoost : manualPreampDb.clamp(kPreampMinDb, kPreampMaxDb);
  bool get isFlat => gains.every((g) => g.abs() < 0.05);

  /// Filterkette für die Engine; leer, wenn aus oder neutral
  String get filterString {
    if (!enabled || isFlat) return '';
    final bands = <String>[];
    for (var i = 0; i < kEqFrequencies.length; i++) {
      final g = gains[i];
      if (g.abs() < 0.05) continue;
      bands.add('equalizer=f=${kEqFrequencies[i]}:t=o:w=1:g=${g.toStringAsFixed(1)}');
    }
    return '@demonify-eq:lavfi=[${bands.join(',')}]';
  }

  /// Effektive Vorverstärkung (nur wenn aktiv)
  double get effectivePreampDb => enabled ? preampDb : 0;

  EqSettings copyWith({bool? enabled, EqPreset? preset, List<double>? gains, List<double>? customGains, bool? autoHeadroom, double? manualPreampDb}) => EqSettings(
        enabled: enabled ?? this.enabled,
        preset: preset ?? this.preset,
        gains: gains ?? this.gains,
        customGains: customGains ?? this.customGains,
        autoHeadroom: autoHeadroom ?? this.autoHeadroom,
        manualPreampDb: manualPreampDb ?? this.manualPreampDb,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'preset': preset.name,
        'gains': gains,
        'customGains': customGains,
        'autoHeadroom': autoHeadroom,
        'manualPreampDb': manualPreampDb,
      };

  factory EqSettings.fromJson(Map<String, dynamic> j) {
    List<double> list(Object? v) {
      final l = ((v as List?) ?? const []).map((e) => (e as num).toDouble().clamp(kEqMinDb, kEqMaxDb).toDouble()).toList();
      return l.length == kEqFrequencies.length ? l : List.filled(kEqFrequencies.length, 0);
    }

    return EqSettings(
      enabled: j['enabled'] as bool? ?? false,
      preset: EqPreset.parse(j['preset'] as String?),
      gains: list(j['gains']),
      customGains: list(j['customGains']),
      autoHeadroom: j['autoHeadroom'] as bool? ?? true,
      manualPreampDb: (j['manualPreampDb'] as num?)?.toDouble() ?? 0,
    );
  }
}
