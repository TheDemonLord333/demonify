import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/cover_image.dart';
import '../../core/widgets/media_widgets.dart';
import '../../core/widgets/section.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import '../catalog/catalog_providers.dart';
import '../catalog/models.dart';
import '../player/player_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final user = ref.watch(currentUserProvider);
    final home = ref.watch(homeProvider);
    final hour = DateTime.now().hour;
    final greeting = hour < 11 ? s.greetingMorning : (hour < 18 ? s.greetingDay : s.greetingEvening);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(homeProvider.future),
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Text(user == null ? greeting : s.greetingName(greeting, user.label)),
            actions: [
              IconButton(tooltip: s.navSettings, icon: const Icon(Icons.settings_rounded), onPressed: () => context.push('/settings')),
            ],
          ),
          ...home.when(
            skipLoadingOnRefresh: true,
            loading: () => [const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [SliverFillRemaining(hasScrollBody: false, child: ErrorView(error: e, onRetry: () => ref.invalidate(homeProvider)))],
            data: (h) => _content(context, ref, h),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: DSpacing.xxl)),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, WidgetRef ref, HomeData h) {
    final s = context.s;
    if (h.newReleases.isEmpty && h.recentlyPlayed.isEmpty && h.playlists.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(icon: Icons.library_music_rounded, title: s.homeEmptyTitle, message: s.homeEmptyMessage),
        ),
      ];
    }
    final quick = <Widget>[
      if (h.favoritesCount > 0)
        _QuickTile(
          title: s.favorites,
          leading: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [DColors.primary, Color(0xFF3B1478)])),
            child: const Icon(Icons.favorite_rounded, color: Colors.white),
          ),
          onTap: () => context.push('/favorites'),
        ),
      for (final p in h.playlists.take(5))
        _QuickTile(
          title: p.name,
          leading: CoverImage(imageId: p.coverImageIds.isEmpty ? null : p.coverImageIds.first, size: 56, radius: 0, icon: Icons.queue_music_rounded),
          onTap: () => context.push('/playlist/${p.id}'),
        ),
    ];
    return [
      if (quick.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(DSpacing.l, DSpacing.s, DSpacing.l, 0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent: 56 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
              crossAxisSpacing: DSpacing.s,
              mainAxisSpacing: DSpacing.s,
            ),
            delegate: SliverChildListDelegate(quick),
          ),
        ),
      if (h.recentlyPlayed.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(title: s.recentlyPlayed)),
        SliverToBoxAdapter(
          child: Shelf(
            itemCount: h.recentlyPlayed.length,
            itemBuilder: (c, i) {
              final t = h.recentlyPlayed[i];
              return MediaCard(
                imageId: t.coverImageId,
                title: t.title,
                subtitle: t.artistLine,
                icon: Icons.music_note_rounded,
                onTap: () => ref.read(playerProvider).playTracks(h.recentlyPlayed, index: i, contextType: 'queue'),
              );
            },
          ),
        ),
      ],
      if (h.newReleases.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(title: s.newReleases, action: s.showAll, onAction: () => context.go('/library'))),
        SliverToBoxAdapter(child: Shelf(itemCount: h.newReleases.length, itemBuilder: (c, i) => ReleaseCard(release: h.newReleases[i]))),
      ],
      if (h.playlists.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(title: s.yourPlaylists)),
        SliverToBoxAdapter(child: Shelf(itemCount: h.playlists.length, itemBuilder: (c, i) => PlaylistCard(playlist: h.playlists[i]))),
      ],
      if (h.followedArtists.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(title: s.followedArtists)),
        SliverToBoxAdapter(child: Shelf(itemCount: h.followedArtists.length, itemBuilder: (c, i) => ArtistCard(artist: h.followedArtists[i]))),
      ],
    ];
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.title, required this.leading, required this.onTap});
  final String title;
  final Widget leading;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: DColors.surface2,
      borderRadius: BorderRadius.circular(DRadius.s),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            leading,
            const SizedBox(width: DSpacing.m),
            Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(width: DSpacing.s),
          ],
        ),
      ),
    );
  }
}
