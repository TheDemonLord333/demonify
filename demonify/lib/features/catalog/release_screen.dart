import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/collection_header.dart';
import '../../core/widgets/media_widgets.dart';
import '../../l10n/l10n.dart';
import '../downloads/download_manager.dart';
import '../downloads/download_widgets.dart';
import '../player/player_providers.dart';
import 'catalog_providers.dart';
import 'models.dart';

class ReleaseScreen extends ConsumerWidget {
  const ReleaseScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(releaseDetailProvider(id));
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: AsyncView(
        value: v,
        onRetry: () => ref.invalidate(releaseDetailProvider(id)),
        builder: (d) => _ReleaseBody(detail: d),
      ),
    );
  }
}

class _ReleaseBody extends ConsumerWidget {
  const _ReleaseBody({required this.detail});
  final ReleaseDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final r = detail.release;
    final player = ref.read(playerProvider);
    final snap = ref.watch(playerSnapshotProvider);
    final isThisPlaying = snap.playing && detail.tracks.any((t) => t.id == snap.current?.id);
    final multiDisc = detail.tracks.any((t) => t.discNumber > 1);
    final total = Duration(milliseconds: detail.tracks.fold(0, (s, t) => s + t.durationMs));
    final children = <Widget>[];
    int? lastDisc;
    for (var i = 0; i < detail.tracks.length; i++) {
      final t = detail.tracks[i];
      if (multiDisc && t.discNumber != lastDisc) {
        lastDisc = t.discNumber;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(DSpacing.l, DSpacing.l, DSpacing.l, DSpacing.xs),
          child: Row(children: [const Icon(Icons.album_rounded, size: 18, color: DColors.textMuted), const SizedBox(width: 8), Text(s.discNumber(t.discNumber), style: const TextStyle(color: DColors.textMuted, fontWeight: FontWeight.w700))]),
        ));
      }
      children.add(TrackTile(
        track: t,
        leadingNumber: t.trackNumber,
        // Individuelles Songcover, sonst Veröffentlichungscover
        showCover: true,
        onTap: () => player.playTracks(detail.tracks, index: i, contextType: 'release', contextId: r.id),
      ));
    }
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: CollectionHeader(
            imageId: r.coverImageId,
            title: r.title,
            overline: releaseTypeLabel(context, r.type),
            subtitle: InkWell(
              onTap: () => context.push('/artist/${r.albumArtist.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(r.albumArtist.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            meta: [if (r.year != null) '${r.year}', s.trackCount(detail.tracks.length), formatLongDuration(total)].join(' • '),
            playing: isThisPlaying,
            onPlay: detail.tracks.isEmpty
                ? null
                : () => isThisPlaying ? player.pause() : player.playTracks(detail.tracks, contextType: 'release', contextId: r.id),
            actions: [
              _SaveButton(releaseId: r.id, saved: detail.saved),
              ReleaseDownloadButton(detail: detail),
              IconButton(
                tooltip: s.shuffle,
                icon: const Icon(Icons.shuffle_rounded),
                onPressed: detail.tracks.isEmpty
                    ? null
                    : () => player.playTracks(detail.tracks, index: Random().nextInt(detail.tracks.length), shuffle: true, contextType: 'release', contextId: r.id),
              ),
              IconButton(
                tooltip: s.addToQueue,
                icon: const Icon(Icons.queue_music_rounded),
                onPressed: () {
                  player.addToQueue(detail.tracks);
                  showSnack(context, s.addedToQueue);
                },
              ),
            ],
          ),
        ),
        SliverList(delegate: SliverChildListDelegate(children)),
        if (r.genre != null)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(DSpacing.l), child: Text(r.genre!, style: const TextStyle(color: DColors.textDim)))),
        const SliverToBoxAdapter(child: SizedBox(height: DSpacing.xxl)),
      ],
    );
  }
}

class _SaveButton extends ConsumerStatefulWidget {
  const _SaveButton({required this.releaseId, required this.saved});
  final String releaseId;
  final bool saved;
  @override
  ConsumerState<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends ConsumerState<_SaveButton> {
  late bool _saved = widget.saved;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return IconButton(
      tooltip: _saved ? s.saved : s.save,
      icon: Icon(_saved ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: _saved ? DColors.primary : null),
      onPressed: () async {
        final next = !_saved;
        setState(() => _saved = next);
        try {
          await ref.read(libraryActionsProvider).setSaved(widget.releaseId, next);
        } catch (e) {
          setState(() => _saved = !next);
          if (context.mounted) showSnack(context, errorText(e));
        }
      },
    );
  }
}

/// Download-Schaltfläche für eine ganze Veröffentlichung
class ReleaseDownloadButton extends ConsumerWidget {
  const ReleaseDownloadButton({super.key, required this.detail});
  final ReleaseDetail detail;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dl = ref.watch(downloadsProvider);
    final progress = dl.collectionProgress('release', detail.release.id);
    return CollectionDownloadButton(
      progress: progress,
      onDownload: () => ref.read(downloadsProvider.notifier).downloadRelease(detail),
      onRemove: () => ref.read(downloadsProvider.notifier).removeCollection('release', detail.release.id),
    );
  }
}
