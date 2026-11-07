import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'cover_image.dart';

/// Kopfbereich für Veröffentlichung, Playlist und Künstler mit großem Cover und Aktionen.
class CollectionHeader extends StatelessWidget {
  const CollectionHeader({
    super.key,
    required this.imageId,
    required this.title,
    this.overline,
    this.subtitle,
    this.meta,
    this.circle = false,
    this.icon = Icons.album_rounded,
    required this.actions,
    this.onPlay,
    this.playing = false,
  });

  final String? imageId;
  final String title;
  final String? overline;
  final Widget? subtitle;
  final String? meta;
  final bool circle;
  final IconData icon;
  final List<Widget> actions;
  final VoidCallback? onPlay;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= DBreakpoints.wide;
    final coverSize = wide ? 232.0 : (width * 0.62).clamp(160.0, 280.0);
    final cover = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(circle ? coverSize : DRadius.m),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: CoverImage(imageId: imageId, size: coverSize, circle: circle, radius: DRadius.m, coverSize: null, icon: icon, semanticLabel: title),
    );
    final text = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (overline != null) Text(overline!.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: DColors.textMuted)),
        const SizedBox(height: DSpacing.xs),
        Text(
          title,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: (wide ? Theme.of(context).textTheme.displaySmall : Theme.of(context).textTheme.headlineMedium),
        ),
        if (subtitle != null) ...[const SizedBox(height: DSpacing.s), subtitle!],
        if (meta != null) ...[
          const SizedBox(height: DSpacing.xs),
          Text(meta!, style: const TextStyle(color: DColors.textMuted, fontSize: 13), textAlign: wide ? TextAlign.start : TextAlign.center),
        ],
      ],
    );
    final actionRow = Row(
      children: [
        ...actions,
        const Spacer(),
        if (onPlay != null)
          Semantics(
            button: true,
            label: playing ? context.s.pause : context.s.play,
            child: SizedBox(
              width: 60,
              height: 60,
              child: FloatingActionButton(
                heroTag: null,
                onPressed: onPlay,
                backgroundColor: DColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const CircleBorder(),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 34),
              ),
            ),
          ),
      ],
    );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2B1452), DColors.background]),
      ),
      padding: EdgeInsets.fromLTRB(DSpacing.l, MediaQuery.paddingOf(context).top + kToolbarHeight, DSpacing.l, DSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [cover, const SizedBox(width: DSpacing.xl), Expanded(child: text)])
          else ...[
            Center(child: cover),
            const SizedBox(height: DSpacing.l),
            text,
          ],
          const SizedBox(height: DSpacing.m),
          actionRow,
        ],
      ),
    );
  }
}
