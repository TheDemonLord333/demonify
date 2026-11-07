import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/collection_header.dart';
import '../../core/widgets/media_widgets.dart';
import '../../core/widgets/section.dart';
import '../../l10n/l10n.dart';
import '../player/player_providers.dart';
import 'catalog_providers.dart';
import 'models.dart';

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(artistDetailProvider(id));
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: AsyncView(value: v, onRetry: () => ref.invalidate(artistDetailProvider(id)), builder: (d) => _ArtistBody(detail: d)),
    );
  }
}

class _ArtistBody extends ConsumerStatefulWidget {
  const _ArtistBody({required this.detail});
  final ArtistDetail detail;
  @override
  ConsumerState<_ArtistBody> createState() => _ArtistBodyState();
}

class _ArtistBodyState extends ConsumerState<_ArtistBody> {
  late bool _following = widget.detail.following;
  bool _showAll = false;

  Future<List<Track>> _allTracks() => ref.read(artistTracksProvider(widget.detail.artist.id).future);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = widget.detail;
    final player = ref.read(playerProvider);
    final all = _showAll ? ref.watch(artistTracksProvider(d.artist.id)) : null;
    final tracks = all?.value ?? d.topTracks;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: CollectionHeader(
            imageId: d.artist.imageId,
            circle: true,
            icon: Icons.person_rounded,
            title: d.artist.name,
            overline: s.artistLabel,
            meta: s.trackCount(d.trackCount),
            onPlay: d.topTracks.isEmpty
                ? null
                : () async {
                    final list = await _allTracks();
                    await player.playTracks(list, contextType: 'artist', contextId: d.artist.id);
                  },
            actions: [
              OutlinedButton(
                onPressed: () async {
                  final next = !_following;
                  setState(() => _following = next);
                  try {
                    await ref.read(libraryActionsProvider).setFollowing(d.artist.id, next);
                  } catch (e) {
                    setState(() => _following = !next);
                    if (context.mounted) showSnack(context, errorText(e));
                  }
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _following ? DColors.primary : DColors.border),
                  foregroundColor: _following ? DColors.primaryHover : DColors.text,
                ),
                child: Text(_following ? s.following : s.follow),
              ),
              const SizedBox(width: DSpacing.s),
              IconButton(
                tooltip: s.shuffle,
                icon: const Icon(Icons.shuffle_rounded),
                onPressed: () async {
                  final list = await _allTracks();
                  if (list.isEmpty) return;
                  await player.playTracks(list, index: Random().nextInt(list.length), shuffle: true, contextType: 'artist', contextId: d.artist.id);
                },
              ),
            ],
          ),
        ),
        if (tracks.isNotEmpty) SliverToBoxAdapter(child: SectionHeader(title: _showAll ? s.allSongs : s.popularSongs)),
        SliverList.builder(
          itemCount: tracks.length,
          itemBuilder: (c, i) => TrackTile(
            track: tracks[i],
            showRelease: true,
            onTap: () => player.playTracks(tracks, index: i, contextType: 'artist', contextId: d.artist.id),
          ),
        ),
        if (all?.isLoading ?? false) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))),
        if (!_showAll && d.trackCount > d.topTracks.length)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: () => setState(() => _showAll = true), child: Text(s.showAllSongs(d.trackCount))),
              ),
            ),
          ),
        if (d.releases.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader(title: s.releases)),
          CardGrid(children: d.releases.map((r) => ReleaseCard(release: r, showArtist: false)).toList()),
        ],
        if (d.appearsOn.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader(title: s.appearsOn)),
          CardGrid(children: d.appearsOn.map((r) => ReleaseCard(release: r)).toList()),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: DSpacing.xxl)),
      ],
    );
  }
}
