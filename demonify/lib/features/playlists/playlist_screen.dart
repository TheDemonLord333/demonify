import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/collection_header.dart';
import '../../core/widgets/cover_image.dart';
import '../../core/widgets/media_widgets.dart';
import '../../l10n/l10n.dart';
import '../catalog/catalog_providers.dart';
import '../catalog/models.dart';
import '../downloads/download_manager.dart';
import '../downloads/download_widgets.dart';
import '../player/player_providers.dart';
import 'add_to_playlist_sheet.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(playlistDetailProvider(id));
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          if (v.hasValue) _PlaylistMenu(detail: v.value!),
        ],
      ),
      body: AsyncView(value: v, onRetry: () => ref.invalidate(playlistDetailProvider(id)), builder: (d) => _PlaylistBody(detail: d)),
    );
  }
}

class _PlaylistMenu extends ConsumerWidget {
  const _PlaylistMenu({required this.detail});
  final PlaylistDetail detail;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    return PopupMenuButton<String>(
      tooltip: s.moreActions,
      onSelected: (v) async {
        final actions = ref.read(playlistActionsProvider);
        try {
          if (v == 'rename') {
            final name = await askPlaylistName(context, initial: detail.playlist.name, title: s.playlistRename, action: s.save);
            if (name != null && name.isNotEmpty) await actions.rename(detail.playlist.id, name);
          } else if (v == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(s.playlistDelete),
                content: Text(s.playlistDeleteConfirm(detail.playlist.name)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.cancel)),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: DColors.danger), onPressed: () => Navigator.pop(c, true), child: Text(s.delete)),
                ],
              ),
            );
            if (ok == true) {
              await ref.read(downloadsProvider.notifier).removeCollection('playlist', detail.playlist.id);
              await actions.delete(detail.playlist.id);
              if (context.mounted) context.pop();
            }
          } else if (v == 'order') {
            if (context.mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistReorderScreen(detail: detail)));
          }
        } catch (e) {
          if (context.mounted) showSnack(context, errorText(e));
        }
      },
      itemBuilder: (c) => [
        PopupMenuItem(value: 'rename', child: Text(s.playlistRename)),
        PopupMenuItem(value: 'order', child: Text(s.playlistEditOrder)),
        PopupMenuItem(value: 'delete', child: Text(s.playlistDelete, style: const TextStyle(color: DColors.danger))),
      ],
    );
  }
}

class _PlaylistBody extends ConsumerWidget {
  const _PlaylistBody({required this.detail});
  final PlaylistDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final p = detail.playlist;
    final tracks = detail.entries.map((e) => e.track).toList();
    final player = ref.read(playerProvider);
    final snap = ref.watch(playerSnapshotProvider);
    final isThisPlaying = snap.playing && tracks.any((t) => t.id == snap.current?.id);
    final dl = ref.watch(downloadsProvider);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: CollectionHeader(
            imageId: p.coverImageIds.isEmpty ? null : p.coverImageIds.first,
            icon: Icons.queue_music_rounded,
            title: p.name,
            overline: s.playlist,
            meta: [s.trackCount(tracks.length), formatLongDuration(Duration(milliseconds: detail.durationMs))].join(' • '),
            playing: isThisPlaying,
            onPlay: tracks.isEmpty ? null : () => isThisPlaying ? player.pause() : player.playTracks(tracks, contextType: 'playlist', contextId: p.id),
            actions: [
              CollectionDownloadButton(
                progress: dl.collectionProgress('playlist', p.id),
                onDownload: () => ref.read(downloadsProvider.notifier).downloadPlaylist(detail),
                onRemove: () => ref.read(downloadsProvider.notifier).removeCollection('playlist', p.id),
              ),
              IconButton(
                tooltip: s.shuffle,
                icon: const Icon(Icons.shuffle_rounded),
                onPressed: tracks.isEmpty ? null : () => player.playTracks(tracks, index: Random().nextInt(tracks.length), shuffle: true, contextType: 'playlist', contextId: p.id),
              ),
            ],
          ),
        ),
        if (tracks.isEmpty)
          SliverToBoxAdapter(child: EmptyView(icon: Icons.queue_music_rounded, title: s.playlistEmpty, message: s.playlistEmptyHint)),
        SliverList.builder(
          itemCount: detail.entries.length,
          itemBuilder: (c, i) {
            final e = detail.entries[i];
            return TrackTile(
              track: e.track,
              showRelease: true,
              onTap: () => player.playTracks(tracks, index: i, contextType: 'playlist', contextId: p.id),
              onRemoveFromPlaylist: () async {
                try {
                  await ref.read(playlistActionsProvider).removeEntry(p.id, e.entryId);
                } catch (err) {
                  if (context.mounted) showSnack(context, errorText(err));
                }
              },
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: DSpacing.xxl)),
      ],
    );
  }
}

/// Reihenfolge per Ziehen ändern; wird beim Speichern serverseitig übernommen.
class PlaylistReorderScreen extends ConsumerStatefulWidget {
  const PlaylistReorderScreen({super.key, required this.detail});
  final PlaylistDetail detail;
  @override
  ConsumerState<PlaylistReorderScreen> createState() => _PlaylistReorderScreenState();
}

class _PlaylistReorderScreenState extends ConsumerState<PlaylistReorderScreen> {
  late final List<PlaylistEntry> _entries = List.of(widget.detail.entries);
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.playlistEditOrder),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await ref.read(playlistActionsProvider).reorder(widget.detail.playlist.id, _entries.map((e) => e.entryId).toList());
                      ref.invalidate(playlistDetailProvider(widget.detail.playlist.id));
                      if (context.mounted) Navigator.of(context).pop();
                    } catch (e) {
                      if (context.mounted) showSnack(context, errorText(e));
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: Text(s.done),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        itemCount: _entries.length,
        onReorderItem: (from, to) => setState(() {
          final e = _entries.removeAt(from);
          _entries.insert(to, e);
        }),
        itemBuilder: (c, i) {
          final t = _entries[i].track;
          return ListTile(
            key: ValueKey(_entries[i].entryId),
            leading: CoverImage(imageId: t.coverImageId, size: 44),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(t.artistLine, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
          );
        },
      ),
    );
  }
}

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final v = ref.watch(favoriteTracksProvider);
    final player = ref.read(playerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.favorites)),
      body: AsyncView(
        value: v,
        onRetry: () => ref.invalidate(favoriteTracksProvider),
        builder: (tracks) {
          if (tracks.isEmpty) return EmptyView(icon: Icons.favorite_border_rounded, title: s.favoritesEmpty, message: s.favoritesEmptyHint);
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(DSpacing.l),
                child: Row(
                  children: [
                    Text(s.trackCount(tracks.length), style: const TextStyle(color: DColors.textMuted)),
                    const Spacer(),
                    IconButton(
                      tooltip: s.download,
                      icon: const Icon(Icons.download_for_offline_outlined),
                      onPressed: () => ref.read(downloadsProvider.notifier).downloadTracks(tracks),
                    ),
                    IconButton(
                      tooltip: s.shuffle,
                      icon: const Icon(Icons.shuffle_rounded),
                      onPressed: () => player.playTracks(tracks, index: Random().nextInt(tracks.length), shuffle: true, contextType: 'favorites'),
                    ),
                    FilledButton.icon(
                      onPressed: () => player.playTracks(tracks, contextType: 'favorites'),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(s.play),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < tracks.length; i++)
                TrackTile(track: tracks[i], showRelease: true, onTap: () => player.playTracks(tracks, index: i, contextType: 'favorites')),
              const SizedBox(height: DSpacing.xxl),
            ],
          );
        },
      ),
    );
  }
}
