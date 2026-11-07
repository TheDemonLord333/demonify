import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/cover_image.dart';
import '../../core/widgets/media_widgets.dart';
import '../../l10n/l10n.dart';
import '../catalog/catalog_providers.dart';
import '../catalog/models.dart';
import '../downloads/download_manager.dart';
import '../playlists/add_to_playlist_sheet.dart';

enum LibraryTab { playlists, artists, albums, eps, singles }

enum LibraryScope { mine, all }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  LibraryTab _tab = LibraryTab.playlists;
  LibraryScope _scope = LibraryScope.all;
  LibrarySort _sort = LibrarySort.recent;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final favCount = ref.watch(favoritesProvider).length;
    final dl = ref.watch(downloadsProvider);
    final labels = {
      LibraryTab.playlists: s.playlists,
      LibraryTab.artists: s.artists,
      LibraryTab.albums: s.typeAlbums,
      LibraryTab.eps: s.typeEps,
      LibraryTab.singles: s.typeSingles,
    };
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Text(s.navLibrary),
          actions: [
            if (_tab == LibraryTab.playlists)
              IconButton(tooltip: s.playlistNew, icon: const Icon(Icons.add_rounded), onPressed: _createPlaylist)
            else
              PopupMenuButton<LibrarySort>(
                tooltip: s.sort,
                icon: const Icon(Icons.sort_rounded),
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (c) => [
                  PopupMenuItem(value: LibrarySort.recent, child: Text(s.sortRecent)),
                  PopupMenuItem(value: LibrarySort.title, child: Text(s.sortTitle)),
                  if (_tab != LibraryTab.artists) PopupMenuItem(value: LibrarySort.artist, child: Text(s.sortArtist)),
                ],
              ),
          ],
        ),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
            child: Row(
              children: [
                for (final t in LibraryTab.values)
                  Padding(
                    padding: const EdgeInsets.only(right: DSpacing.s),
                    child: ChoiceChip(
                      label: Text(labels[t]!),
                      selected: _tab == t,
                      showCheckmark: false,
                      labelStyle: TextStyle(color: _tab == t ? Colors.white : DColors.text, fontWeight: FontWeight.w600),
                      onSelected: (_) => setState(() => _tab = t),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_tab != LibraryTab.playlists)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(DSpacing.l, DSpacing.m, DSpacing.l, 0),
              child: SegmentedButton<LibraryScope>(
                segments: [
                  ButtonSegment(value: LibraryScope.all, label: Text(s.libraryAll)),
                  ButtonSegment(value: LibraryScope.mine, label: Text(_tab == LibraryTab.artists ? s.libraryFollowed : s.librarySaved)),
                ],
                selected: {_scope},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _scope = v.first),
              ),
            ),
          ),
        if (_tab == LibraryTab.playlists) ...[
          SliverToBoxAdapter(
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(DRadius.s), gradient: DColors.favoriteGradient),
                    child: const Icon(Icons.favorite_rounded, color: Colors.white),
                  ),
                  title: Text(s.favorites, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(s.trackCount(favCount)),
                  onTap: () => context.push('/favorites'),
                ),
                ListTile(
                  leading: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(DRadius.s), color: DColors.secondary.withValues(alpha: 0.18)),
                    child: const Icon(Icons.download_done_rounded, color: DColors.secondary),
                  ),
                  title: Text(s.downloads, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(s.trackCount(dl.items.values.where((i) => dl.isDownloaded(i.track.id)).length)),
                  onTap: () => context.push('/downloads'),
                ),
              ],
            ),
          ),
          _playlists(),
        ] else if (_tab == LibraryTab.artists)
          _artists()
        else
          _releases(switch (_tab) {
            LibraryTab.eps => ReleaseType.ep,
            LibraryTab.singles => ReleaseType.single,
            _ => ReleaseType.album,
          }),
        const SliverToBoxAdapter(child: SizedBox(height: DSpacing.xxl)),
      ],
    );
  }

  Widget _playlists() {
    final lists = ref.watch(playlistsProvider);
    return lists.when(
      loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))),
      error: (e, _) => SliverToBoxAdapter(child: ErrorView(error: e, onRetry: () => ref.invalidate(playlistsProvider))),
      data: (items) => SliverList.builder(
        itemCount: items.length,
        itemBuilder: (c, i) {
          final p = items[i];
          return ListTile(
            leading: CoverImage(imageId: p.coverImageIds.isEmpty ? null : p.coverImageIds.first, size: 56, icon: Icons.queue_music_rounded),
            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(c.s.trackCount(p.trackCount)),
            onTap: () => context.push('/playlist/${p.id}'),
          );
        },
      ),
    );
  }

  Widget _artists() {
    final v = ref.watch(artistsProvider(_scope == LibraryScope.mine));
    return v.when(
      loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))),
      error: (e, _) => SliverToBoxAdapter(child: ErrorView(error: e, onRetry: () => ref.invalidate(artistsProvider))),
      data: (items) {
        final list = List.of(items);
        if (_sort == LibrarySort.title) list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (list.isEmpty) return SliverToBoxAdapter(child: EmptyView(icon: Icons.person_search_rounded, title: context.s.libraryEmpty));
        return CardGrid(maxExtent: 180, children: list.map((a) => ArtistCard(artist: a)).toList());
      },
    );
  }

  Widget _releases(ReleaseType type) {
    final v = ref.watch(releasesProvider(ReleaseListQuery(type: type, savedOnly: _scope == LibraryScope.mine)));
    return v.when(
      loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))),
      error: (e, _) => SliverToBoxAdapter(child: ErrorView(error: e, onRetry: () => ref.invalidate(releasesProvider))),
      data: (items) {
        final list = List.of(items);
        switch (_sort) {
          case LibrarySort.title:
            list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
          case LibrarySort.artist:
            list.sort((a, b) => a.albumArtist.name.toLowerCase().compareTo(b.albumArtist.name.toLowerCase()));
          case LibrarySort.recent:
            break;
        }
        if (list.isEmpty) return SliverToBoxAdapter(child: EmptyView(icon: Icons.album_rounded, title: context.s.libraryEmpty));
        return CardGrid(children: list.map((r) => ReleaseCard(release: r)).toList());
      },
    );
  }

  Future<void> _createPlaylist() async {
    final s = context.s;
    final name = await askPlaylistName(context, title: s.playlistNew, action: s.playlistCreate);
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final id = await ref.read(playlistActionsProvider).create(name);
      if (mounted) context.push('/playlist/$id');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }
}

