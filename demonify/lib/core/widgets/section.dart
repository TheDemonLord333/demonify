import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DSpacing.l, DSpacing.xl, DSpacing.s, DSpacing.s),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// Horizontale Leiste mit Karten (z. B. „Neu hinzugefügt“)
class Shelf extends StatelessWidget {
  const Shelf({super.key, required this.itemCount, required this.itemBuilder, this.itemWidth = 152, this.height});
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemWidth;
  final double? height;

  @override
  Widget build(BuildContext context) {
    // Höhe berücksichtigt die Textskalierung (zwei Textzeilen unter dem Cover)
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: height ?? itemWidth + 64 * scale.clamp(1.0, 2.0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: DSpacing.l),
        itemBuilder: (c, i) => SizedBox(width: itemWidth, child: itemBuilder(c, i)),
      ),
    );
  }
}
