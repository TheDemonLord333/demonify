import 'package:demonify/features/player/equalizer/eq_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('10 Bänder von 31 Hz bis 16 kHz', () {
    expect(kEqFrequencies.length, 10);
    expect(kEqFrequencies.first, 31);
    expect(kEqFrequencies.last, 16000);
  });

  test('Voreinstellungen liegen im Bereich −12 … +12 dB', () {
    for (final p in EqPreset.values.where((p) => p != EqPreset.custom)) {
      expect(p.gains!.length, 10, reason: p.name);
      expect(p.gains!.every((g) => g >= kEqMinDb && g <= kEqMaxDb), isTrue, reason: p.name);
    }
  });

  test('Aus oder neutral → keine Filterkette, keine Vorverstärkung', () {
    expect(const EqSettings().filterString, '');
    expect(EqSettings(enabled: true, gains: EqPreset.neutral.gains!).filterString, '');
    expect(EqSettings(enabled: false, gains: EqPreset.bassBoost.gains!).effectivePreampDb, 0);
  });

  test('Filterkette für die FFmpeg-Engine', () {
    final s = EqSettings(enabled: true, gains: EqPreset.bassBoost.gains!);
    expect(s.filterString, startsWith('@demonify-eq:lavfi=[equalizer=f=31:t=o:w=1:g=6.0,'));
    expect(s.filterString, contains('equalizer=f=500:t=o:w=1:g=1.0'));
    expect(s.filterString, isNot(contains('f=16000')));
  });

  test('Automatischer Headroom senkt um die stärkste Anhebung', () {
    final s = EqSettings(enabled: true, gains: EqPreset.bassBoost.gains!);
    expect(s.preampDb, -6);
    final manual = s.copyWith(autoHeadroom: false, manualPreampDb: -3);
    expect(manual.preampDb, -3);
  });

  test('JSON-Roundtrip und Begrenzung ungültiger Werte', () {
    final s = EqSettings.fromJson({'enabled': true, 'preset': 'rock', 'gains': [20, -20, 0, 0, 0, 0, 0, 0, 0, 0]});
    expect(s.gains.first, 12);
    expect(s.gains[1], -12);
    expect(EqSettings.fromJson(s.toJson()).preset, EqPreset.rock);
  });
}
