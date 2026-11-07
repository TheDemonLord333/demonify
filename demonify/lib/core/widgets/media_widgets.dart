import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/catalog/catalog_providers.dart';
import '../../features/catalog/models.dart';
import '../../features/downloads/download_manager.dart';
import '../../features/downloads/download_models.dart';
import '../../features/player/player_providers.dart';
import '../../features/playlists/add_to_playlist_sheet.dart';
import '../../l10n/l10n.dart';
import '../network/api_exception.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import 'async_view.dart';
import 'cover_image.dart';

String releaseTypeLabel(BuildContext context, ReleaseType t) => switch (t) {
      ReleaseType.album => context.s.typeAlbum,
      ReleaseType.ep => context.s.typeEp,
      ReleaseType.single => context.s.typeSingle,
    };

/// Songzeile: individuelles Songcover (Fallback Veröffentlichungscover), Titel, Künstler,
/// optional Veröffentlichungsname (unterscheidet gleichnamige Songs), Download-Status.
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.showCover = true,
    this.showRelease = false,
    this.leadingNumber,
    this.trailing,
    this.onRemoveFromPlaylist,
  });

  final Track track;
  final VoidCallback onTap;
  final bool showCover;
  final bool showRelease;
  final int? leadingNumber;
  final Widget? trailing;
  final VoidCallback? onRemoveFromPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(playerSnapshotProvider.select((s) => s.current?.id));
    final dl = ref.watch(downloadsProvider.select((d) => d.items[track.id]));
    final isCurrent = current == track.id;
    final subtitle = [
      track.artistLine,
      if (showRelease) track.release.title,
    ].join(' • ');
    final titleColor = !track.available ? DColors.textDim : (isCurrent ? DColors.primaryHover : DColors.text);
    return InkWell(
      onTap: track.available ? onTap : null,
      onLongPress: () => showTrackActions(context, ref, track, onRemoveFromPlaylist: onRemoveFromPlaylist),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DSpacing.l, vertical: DSpacing.s),
          child: Row(
            children: [
              if (leadingNumber != null)
                SizedBox(
                  width: 32,
                  child: isCurrent
                      ? const Icon(Icons.graphic_eq_rounded, color: DColors.primary, size: 20)
                      : Text('$leadingNumber', style: const TextStyle(color: DColors.textMuted), textAlign: TextAlign.center),
                ),
              if (showCover) ...[
                CoverImage(imageId: track.coverImageId, size: 48, semanticLabel: track.title),
                const SizedBox(width: DSpacing.m),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: titleColor, fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (dl?.status == DownloadStatus.done)
                          const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.download_done_rounded, size: 14, color: DColors.secondary)),
                        if (dl?.status == DownloadStatus.downloading || dl?.status == DownloadStatus.queued)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: DColors.secondary)),
                          ),
                        Expanded(
                          child: Text(
                            track.available ? subtitle : '${context.s.unavailable} • $subtitle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: DColors.textMuted, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(formatDuration(track.duration), style: const TextStyle(color: DColors.textDim, fontSize: 13)),
              trailing ??
                  IconButton(
                    tooltip: context.s.moreActions,
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => showTrackActions(context, ref, track, onRemoveFromPlaylist: onRemoveFromPlaylist),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showTrackActions(BuildContext context, WidgetRef ref, Track track, {VoidCallback? onRemoveFromPlaylist}) {
  final s = context.s;
  final router = GoRouter.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final isFav = ref.watch(favoritesProvider).contains(track.id);
      final dl = ref.watch(downloadsProvider).items[track.id];
      final player = ref.read(playerProvider);
      void close() => Navigator.of(ctx).pop();
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CoverImage(imageId: track.coverImageId, size: 48),
              title: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${track.artistLine} • ${track.release.title}', maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const Divider(),
            ListTile(
              leading: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: isFav ? DColors.primary : null),
              title: Text(isFav ? s.favoriteRemove : s.favoriteAdd),
              onTap: () async {
                close();
                try {
                  await ref.read(favoritesProvider.notifier).toggle(track.id);
                } catch (e) {
                  if (context.mounted) showSnack(context, errorText(e));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(s.addToPlaylist),
              onTap: () {
                close();
                showAddToPlaylistSheet(context, [track.id]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_play_next_rounded),
              title: Text(s.playNext),
              onTap: () {
                close();
                player.playNext([track]);
                showSnack(context, s.addedToQueue);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(s.addToQueue),
              onTap: () {
                close();
                player.addToQueue([track]);
                showSnack(context, s.addedToQueue);
              },
            ),
            if (dl?.status == DownloadStatus.done)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(s.removeDownload),
                onTap: () {
                  close();
                  ref.read(downloadsProvider.notifier).remove(track.id);
                },
              )
            else if (track.available)
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: Text(s.download),
                onTap: () {
                  close();
                  ref.read(downloadsProvider.notifier).downloadTracks([track]);
                },
              ),
            if (onRemoveFromPlaylist != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: Text(s.playlistRemoveEntry),
                onTap: () {
                  close();
                  onRemoveFromPlaylist();
                },
              ),
            ListTile(
              leading: const Icon(Icons.album_rounded),
              title: Text(s.goToRelease),
              onTap: () {
                close();
                router.push('/release/${track.release.id}');
              },
            ),
            for (final a in track.artists)
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: Text(s.goToArtistNamed(a.name)),
                onTap: () {
                  close();
                  router.push('/artist/${a.id}');
                },
              ),
            const SizedBox(height: DSpacing.l),
          ],
        ),
      );
    }),
  );
}

/// Karte für Veröffentlichungen (Veröffentlichungscover), Künstler (rund) und Playlists
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.imageId,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.circle = false,
    this.icon = Icons.album_rounded,
    this.size = 152,
  });

  final String? imageId;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool circle;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: [title, subtitle].whereType<String>().join(', '),
      child: InkWell(
        borderRadius: BorderRadius.circular(DRadius.m),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth.isFinite ? c.maxWidth : size;
              return CoverImage(imageId: imageId, size: w, circle: circle, radius: DRadius.m, icon: icon);
            }),
            const SizedBox(height: DSpacing.s),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: circle ? TextAlign.center : TextAlign.start, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (subtitle != null)
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: circle ? TextAlign.center : TextAlign.start, style: const TextStyle(color: DColors.textMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class ReleaseCard extends StatelessWidget {
  const ReleaseCard({super.key, required this.release, this.showArtist = true});
  final Release release;
  final bool showArtist;
  @override
  Widget build(BuildContext context) {
    final sub = [
      if (release.year != null) '${release.year}',
      releaseTypeLabel(context, release.type),
      if (showArtist) release.albumArtist.name,
    ].join(' • ');
    return MediaCard(imageId: release.coverImageId, title: release.title, subtitle: sub, onTap: () => context.push('/release/${release.id}'));
  }
}

class ArtistCard extends StatelessWidget {
  const ArtistCard({super.key, required this.artist});
  final ArtistRef artist;
  @override
  Widget build(BuildContext context) => MediaCard(
        imageId: artist.imageId,
        title: artist.name,
        subtitle: context.s.artistLabel,
        circle: true,
        icon: Icons.person_rounded,
        onTap: () => context.push('/artist/${artist.id}'),
      );
}

class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.playlist});
  final PlaylistSummary playlist;
  @override
  Widget build(BuildContext context) => MediaCard(
        imageId: playlist.coverImageIds.isEmpty ? null : playlist.coverImageIds.first,
        title: playlist.name,
        subtitle: context.s.trackCount(playlist.trackCount),
        icon: Icons.queue_music_rounded,
        onTap: () => context.push('/playlist/${playlist.id}'),
      );
}

/// Responsives Raster für Karten
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children, this.maxExtent = 200});
  final List<Widget> children;
  final double maxExtent;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return SliverPadding(
      padding: const EdgeInsets.all(DSpacing.l),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxExtent,
          mainAxisSpacing: DSpacing.l,
          crossAxisSpacing: DSpacing.l,
          childAspectRatio: 1 / (1 + 0.42 * scale),
        ),
        delegate: SliverChildListDelegate(children),
      ),
    );
  }
}
