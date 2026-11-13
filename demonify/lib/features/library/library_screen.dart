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
import 'library_model.dart';

/// Bibliothek: öffnet ohne aktiven Filter und zeigt Playlists, gespeicherte Alben und gefolgte Künstler
/// gemeinsam. Ein Filter-Chip zeigt nur seine Kategorie; erneutes Antippen hebt den Filter wieder auf.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  LibraryFilter? _filter;
  LibraryOrder _order = LibraryOrder.recent;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final entries = ref.watch(libraryEntriesProvider);
    final labels = {LibraryFilter.playlists: s.playlists, LibraryFilter.albums: s.libraryAlbums, LibraryFilter.artists: s.artists};
    final showPinned = _filter == null || _filter == LibraryFilter.playlists;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(libraryEntriesProvider.future),
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Text(s.navLibrary),
            actions: [
              IconButton(tooltip: s.libraryCatalog, icon: const Icon(Icons.travel_explore_rounded), onPressed: () => context.push('/catalog')),
              PopupMenuButton<LibraryOrder>(
                tooltip: s.sort,
                icon: const Icon(Icons.sort_rounded),
                initialValue: _order,
                onSelected: (v) => setState(() => _order = v),
                itemBuilder: (c) => [
                  PopupMenuItem(value: LibraryOrder.recent, child: Text(s.sortRecent)),
                  PopupMenuItem(value: LibraryOrder.name, child: Text(s.sortTitle)),
                ],
              ),
              IconButton(tooltip: s.playlistNew, icon: const Icon(Icons.add_rounded), onPressed: _createPlaylist),
            ],
          ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
              child: Row(
                children: [
                  if (_filter != null)
                    Padding(
                      padding: const EdgeInsets.only(right: DSpacing.s),
                      child: IconButton.filledTonal(
                        tooltip: s.libraryClearFilter,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _filter = null),
                      ),
                    ),
                  for (final f in LibraryFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: DSpacing.s),
                      child: FilterChip(
                        key: ValueKey('library-filter-${f.name}'),
                        label: Text(labels[f]!),
                        selected: _filter == f,
                        showCheckmark: false,
                        selectedColor: DColors.secondary,
                        labelStyle: TextStyle(color: _filter == f ? Colors.black : DColors.text, fontWeight: FontWeight.w600),
                        tooltip: _filter == f ? s.libraryClearFilter : null,
                        // Antippen des aktiven Filters → zurück zur Gesamtansicht
                        onSelected: (_) => setState(() => _filter = _filter == f ? null : f),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: DSpacing.s)),
          if (showPinned) _pinned(),
          ...entries.when(
            loading: () => [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ],
            error: (e, _) => [
              SliverToBoxAdapter(
                child: ErrorView(error: e, onRetry: () => ref.invalidate(libraryEntriesProvider)),
              ),
            ],
            data: (all) {
              final view = libraryView(all, filter: _filter, order: _order);
              if (view.isEmpty) return [SliverToBoxAdapter(child: _empty(context))];
              return [
                SliverList.builder(
                  itemCount: view.length,
                  itemBuilder: (c, i) => _EntryTile(entry: view[i]),
                ),
              ];
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: DSpacing.xxl)),
        ],
      ),
    );
  }

  /// Lieblingssongs und Downloads sind feste Einträge (Gesamtansicht und Filter „Playlists“)
  Widget _pinned() {
    final s = context.s;
    final favCount = ref.watch(favoritesProvider).length;
    final dl = ref.watch(downloadsProvider);
    return SliverToBoxAdapter(
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
            subtitle: Text('${s.playlist} • ${s.trackCount(favCount)}'),
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
    );
  }

  Widget _empty(BuildContext context) {
    final s = context.s;
    return switch (_filter) {
      null => EmptyView(icon: Icons.library_music_rounded, title: s.libraryEmptyAll, message: s.libraryEmptyAllHint),
      LibraryFilter.playlists => EmptyView(
        icon: Icons.queue_music_rounded,
        title: s.libraryEmptyPlaylists,
        action: FilledButton.tonal(onPressed: _createPlaylist, child: Text(s.playlistNew)),
      ),
      LibraryFilter.albums => EmptyView(icon: Icons.album_rounded, title: s.libraryEmptyAlbums, message: s.libraryEmptyAlbumsHint),
      LibraryFilter.artists => EmptyView(icon: Icons.person_search_rounded, title: s.libraryEmptyArtists, message: s.libraryEmptyArtistsHint),
    };
  }

  Future<void> _createPlaylist() async {
    final s = context.s;
    final name = await askPlaylistName(context, title: s.playlistNew, action: s.playlistCreate);
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final id = await ref.read(playlistActionsProvider).create(name);
      ref.invalidate(libraryEntriesProvider);
      if (mounted) context.push('/playlist/$id');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final (Widget leading, String subtitle, String route) = switch (entry) {
      PlaylistLibraryEntry(:final playlist) => (
        CoverImage(imageId: playlist.coverImageIds.isEmpty ? null : playlist.coverImageIds.first, size: 56, icon: Icons.queue_music_rounded),
        '${s.playlist} • ${s.trackCount(playlist.trackCount)}',
        '/playlist/${playlist.id}',
      ),
      ReleaseLibraryEntry(:final release) => (
        CoverImage(imageId: release.coverImageId, size: 56, icon: Icons.album_rounded),
        '${releaseTypeLabel(context, release.type)} • ${release.albumArtist.name}',
        '/release/${release.id}',
      ),
      ArtistLibraryEntry(:final artist) => (
        CoverImage(imageId: artist.imageId, size: 56, circle: true, icon: Icons.person_rounded),
        s.artist,
        '/artist/${artist.id}',
      ),
    };
    return ListTile(
      leading: leading,
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => context.push(route),
    );
  }
}

enum CatalogTab { artists, albums, eps, singles }

/// Gesamter Katalog (alle Künstler und Veröffentlichungen) – aus der Bibliothek erreichbar
class CatalogBrowseScreen extends ConsumerStatefulWidget {
  const CatalogBrowseScreen({super.key});
  @override
  ConsumerState<CatalogBrowseScreen> createState() => _CatalogBrowseScreenState();
}

class _CatalogBrowseScreenState extends ConsumerState<CatalogBrowseScreen> {
  CatalogTab _tab = CatalogTab.artists;
  LibrarySort _sort = LibrarySort.recent;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final labels = {CatalogTab.artists: s.artists, CatalogTab.albums: s.typeAlbums, CatalogTab.eps: s.typeEps, CatalogTab.singles: s.typeSingles};
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Text(s.libraryCatalog),
            actions: [
              PopupMenuButton<LibrarySort>(
                tooltip: s.sort,
                icon: const Icon(Icons.sort_rounded),
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (c) => [
                  PopupMenuItem(value: LibrarySort.recent, child: Text(s.sortRecent)),
                  PopupMenuItem(value: LibrarySort.title, child: Text(s.sortTitle)),
                  if (_tab != CatalogTab.artists) PopupMenuItem(value: LibrarySort.artist, child: Text(s.sortArtist)),
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
                  for (final t in CatalogTab.values)
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
          if (_tab == CatalogTab.artists)
            _artists()
          else
            _releases(switch (_tab) {
              CatalogTab.eps => ReleaseType.ep,
              CatalogTab.singles => ReleaseType.single,
              _ => ReleaseType.album,
            }),
          const SliverToBoxAdapter(child: SizedBox(height: DSpacing.xxl)),
        ],
      ),
    );
  }

  Widget _artists() {
    final v = ref.watch(artistsProvider(false));
    return v.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: ErrorView(error: e, onRetry: () => ref.invalidate(artistsProvider)),
      ),
      data: (items) {
        final list = List.of(items);
        if (_sort == LibrarySort.title) list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (list.isEmpty) {
          return SliverToBoxAdapter(
            child: EmptyView(icon: Icons.person_search_rounded, title: context.s.libraryEmpty),
          );
        }
        return CardGrid(maxExtent: 180, children: list.map((a) => ArtistCard(artist: a)).toList());
      },
    );
  }

  Widget _releases(ReleaseType type) {
    final v = ref.watch(releasesProvider(ReleaseListQuery(type: type)));
    return v.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: ErrorView(error: e, onRetry: () => ref.invalidate(releasesProvider)),
      ),
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
        if (list.isEmpty) {
          return SliverToBoxAdapter(
            child: EmptyView(icon: Icons.album_rounded, title: context.s.libraryEmpty),
          );
        }
        return CardGrid(children: list.map((r) => ReleaseCard(release: r)).toList());
      },
    );
  }
}
