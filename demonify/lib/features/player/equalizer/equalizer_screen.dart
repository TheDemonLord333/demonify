import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/l10n.dart';
import '../player_providers.dart';
import 'eq_controller.dart';
import 'eq_model.dart';

/// Einstellungen → Klang → Equalizer
class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  String _presetLabel(BuildContext c, EqPreset p) => switch (p) {
        EqPreset.neutral => c.s.presetNeutral,
        EqPreset.bassBoost => c.s.presetBassBoost,
        EqPreset.rock => c.s.presetRock,
        EqPreset.pop => c.s.presetPop,
        EqPreset.electronic => c.s.presetElectronic,
        EqPreset.vocal => c.s.presetVocal,
        EqPreset.custom => c.s.presetCustom,
      };

  static String freqLabel(int f) => f >= 1000 ? '${f ~/ 1000}k' : '$f';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final eq = ref.watch(equalizerProvider);
    final ctrl = ref.read(equalizerProvider.notifier);
    final supported = ref.watch(playerProvider).equalizerSupported;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.equalizer),
        actions: [TextButton(onPressed: eq.enabled ? ctrl.reset : null, child: Text(s.reset))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: DSpacing.xxl),
        children: [
          SwitchListTile(
            title: Text(s.eqEnabled, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(eq.enabled ? s.eqActiveHint : s.eqInactiveHint),
            value: eq.enabled,
            onChanged: ctrl.setEnabled,
          ),
          if (!supported)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
              child: Container(
                padding: const EdgeInsets.all(DSpacing.m),
                decoration: BoxDecoration(color: DColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(DRadius.m)),
                child: Text(s.eqUnavailable),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(DSpacing.l, DSpacing.m, DSpacing.l, DSpacing.s),
            child: Text(s.eqPresets, style: Theme.of(context).textTheme.titleMedium),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
            child: Row(
              children: [
                for (final p in EqPreset.values)
                  Padding(
                    padding: const EdgeInsets.only(right: DSpacing.s),
                    child: ChoiceChip(
                      label: Text(_presetLabel(context, p)),
                      selected: eq.enabled && eq.preset == p,
                      showCheckmark: false,
                      labelStyle: TextStyle(color: eq.enabled && eq.preset == p ? Colors.white : DColors.text, fontWeight: FontWeight.w600),
                      onSelected: (_) => ctrl.selectPreset(p),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: DSpacing.l),
          _EqCurve(settings: eq),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: eq.enabled ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !eq.enabled,
              child: SizedBox(
                height: 280,
                child: LayoutBuilder(builder: (context, c) {
                  return Row(
                    children: [
                      for (var i = 0; i < kEqFrequencies.length; i++)
                        Expanded(
                          child: _BandSlider(
                            label: freqLabel(kEqFrequencies[i]),
                            hz: kEqFrequencies[i],
                            value: eq.gains[i],
                            onChanged: (v) => ctrl.setBand(i, v),
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const Divider(height: DSpacing.xxl),
          SwitchListTile(
            title: Text(s.eqHeadroom),
            subtitle: Text(s.eqHeadroomHint(eq.preampDb.toStringAsFixed(1))),
            value: eq.autoHeadroom,
            onChanged: eq.enabled ? ctrl.setAutoHeadroom : null,
          ),
          if (!eq.autoHeadroom)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
              child: Row(
                children: [
                  Text(s.eqPreamp),
                  Expanded(
                    child: Slider(
                      value: eq.manualPreampDb,
                      min: kPreampMinDb,
                      max: kPreampMaxDb,
                      divisions: 24,
                      label: '${eq.manualPreampDb.toStringAsFixed(1)} dB',
                      onChanged: eq.enabled ? ctrl.setManualPreamp : null,
                    ),
                  ),
                  SizedBox(width: 64, child: Text('${eq.manualPreampDb.toStringAsFixed(1)} dB', textAlign: TextAlign.end)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(DSpacing.l),
            child: Container(
              padding: const EdgeInsets.all(DSpacing.l),
              decoration: BoxDecoration(color: DColors.surface2, borderRadius: BorderRadius.circular(DRadius.m), border: Border.all(color: DColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.info_outline_rounded, size: 18, color: DColors.secondary),
                    const SizedBox(width: 8),
                    Text(s.eqInfoTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: DSpacing.s),
                  Text(s.eqInfoBody, style: const TextStyle(color: DColors.textMuted)),
                  const SizedBox(height: DSpacing.s),
                  Text(Platform.isIOS ? s.eqInfoAirplay : s.eqInfoCast, style: const TextStyle(color: DColors.textMuted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({required this.label, required this.hz, required this.value, required this.onChanged});
  final String label;
  final int hz;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value >= 0 ? '+${value.toStringAsFixed(0)}' : value.toStringAsFixed(0), style: TextStyle(fontSize: 11, color: value.abs() > 0.05 ? DColors.primaryHover : DColors.textDim)),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                activeTrackColor: DColors.primary,
                inactiveTrackColor: DColors.surface3,
              ),
              child: Slider(
                value: value,
                min: kEqMinDb,
                max: kEqMaxDb,
                divisions: 48,
                semanticFormatterCallback: (v) => '$hz Hz: ${v.toStringAsFixed(1)} dB',
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: DColors.textMuted)),
      ],
    );
  }
}

/// Vorschau der Kurve (Lila = Anhebung/Absenkung, Grün = Nulllinie)
class _EqCurve extends StatelessWidget {
  const _EqCurve({required this.settings});
  final EqSettings settings;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
      child: SizedBox(height: 72, child: CustomPaint(painter: _CurvePainter(settings.gains, settings.enabled), size: Size.infinite)),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.gains, this.enabled);
  final List<double> gains;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()
      ..color = DColors.secondary.withValues(alpha: 0.4)
      ..strokeWidth = 1);
    final step = size.width / (gains.length - 1);
    final pts = [for (var i = 0; i < gains.length; i++) Offset(i * step, mid - gains[i] / kEqMaxDb * (mid - 4))];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p0 = pts[i - 1];
      final p1 = pts[i];
      final cx = (p0.dx + p1.dx) / 2;
      path.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(path, Paint()
      ..color = enabled ? DColors.primary : DColors.textDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => old.gains != gains || old.enabled != enabled;
}
