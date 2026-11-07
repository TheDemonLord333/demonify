import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/cover_image.dart';
import '../../l10n/l10n.dart';
import '../player/player_providers.dart';
import 'download_manager.dart';
import 'download_models.dart';

/// Downloadverwaltung: Fortschritt, Wiederholen, Abbrechen, Entfernen, Speicherverbrauch.
/// Funktioniert vollständig offline.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final st = ref.watch(downloadsProvider);
    final mgr = ref.read(downloadsProvider.notifier);
    final items = st.items.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final done = items.where((i) => i.status == DownloadStatus.done).toList();
    final active = items.where((i) => i.status != DownloadStatus.done).toList();
    final failed = items.where((i) => i.status == DownloadStatus.failed).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.downloads),
        actions: [
          PopupMenuButton<String>(
            tooltip: s.moreActions,
            onSelected: (v) async {
              if (v == 'retry') mgr.retryFailed();
              if (v == 'all') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(s.downloadsRemoveAll),
                    content: Text(s.downloadsRemoveAllConfirm),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.cancel)),
                      FilledButton(style: FilledButton.styleFrom(backgroundColor: DColors.danger), onPressed: () => Navigator.pop(c, true), child: Text(s.delete)),
                    ],
                  ),
                );
                if (ok == true) await mgr.removeAll();
              }
            },
            itemBuilder: (c) => [
              if (failed > 0) PopupMenuItem(value: 'retry', child: Text(s.downloadsRetryFailed)),
              PopupMenuItem(value: 'all', child: Text(s.downloadsRemoveAll, style: const TextStyle(color: DColors.danger))),
            ],
          ),
        ],
      ),
      body: !st.loaded
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? EmptyView(icon: Icons.download_for_offline_outlined, title: s.downloadsEmpty, message: s.downloadsEmptyHint)
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(DSpacing.l),
                      child: Row(
                        children: [
                          const Icon(Icons.sd_storage_rounded, color: DColors.secondary),
                          const SizedBox(width: DSpacing.s),
                          Expanded(child: Text(s.storageUsed(formatBytes(st.totalBytes)), style: const TextStyle(fontWeight: FontWeight.w700))),
                          if (done.isNotEmpty)
                            FilledButton.icon(
                              onPressed: () => ref.read(playerProvider).playTracks(done.map((d) => d.track).toList(), contextType: 'downloads'),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(s.play),
                            ),
                        ],
                      ),
                    ),
                    if (st.collections.isNotEmpty) ...[
                      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text(s.downloadCollections, style: Theme.of(context).textTheme.titleMedium)),
                      for (final c in st.collections.values)
                        ListTile(
                          leading: CoverImage(imageId: c.coverImageId, size: 48, icon: c.kind == 'playlist' ? Icons.queue_music_rounded : Icons.album_rounded),
                          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text([if (c.subtitle != null) c.subtitle!, s.trackCount(c.trackIds.length)].join(' • ')),
                          trailing: IconButton(tooltip: s.removeDownload, icon: const Icon(Icons.delete_outline_rounded), onPressed: () => mgr.removeCollection(c.kind, c.id)),
                          onTap: () => context.push(c.kind == 'playlist' ? '/playlist/${c.id}' : '/release/${c.id}'),
                        ),
                    ],
                    if (active.isNotEmpty) ...[
                      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(s.downloadsInProgress, style: Theme.of(context).textTheme.titleMedium)),
                      for (final i in active) _ActiveTile(item: i),
                    ],
                    Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(s.songs, style: Theme.of(context).textTheme.titleMedium)),
                    for (var idx = 0; idx < done.length; idx++)
                      ListTile(
                        leading: CoverImage(imageId: done[idx].track.coverImageId, size: 44),
                        title: Text(done[idx].track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${done[idx].track.artistLine} • ${formatBytes(done[idx].bytes)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => ref.read(playerProvider).playTracks(done.map((d) => d.track).toList(), index: idx, contextType: 'downloads'),
                        trailing: IconButton(tooltip: s.removeDownload, icon: const Icon(Icons.delete_outline_rounded), onPressed: () => mgr.remove(done[idx].track.id, force: true)),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(DSpacing.l),
                      child: Text(s.downloadsServerNote, style: const TextStyle(color: DColors.textDim, fontSize: 12)),
                    ),
                  ],
                ),
    );
  }
}

class _ActiveTile extends ConsumerWidget {
  const _ActiveTile({required this.item});
  final DownloadItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final mgr = ref.read(downloadsProvider.notifier);
    final failed = item.status == DownloadStatus.failed;
    return ListTile(
      leading: CoverImage(imageId: item.track.coverImageId, size: 44),
      title: Text(item.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failed ? (item.error ?? s.downloadFailed) : (item.status == DownloadStatus.queued ? s.downloadQueued : s.downloading),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: failed ? DColors.danger : DColors.textMuted),
          ),
          if (!failed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: item.status == DownloadStatus.queued ? null : item.progress, color: DColors.secondary, minHeight: 3),
            ),
        ],
      ),
      trailing: failed
          ? IconButton(tooltip: s.retry, icon: const Icon(Icons.refresh_rounded), onPressed: () => mgr.retry(item.track.id))
          : IconButton(tooltip: s.cancel, icon: const Icon(Icons.close_rounded), onPressed: () => mgr.cancel(item.track.id)),
    );
  }
}
