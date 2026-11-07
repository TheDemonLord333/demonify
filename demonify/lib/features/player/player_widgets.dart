import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/cover_image.dart';
import '../../l10n/l10n.dart';
import '../catalog/catalog_providers.dart';
import '../catalog/models.dart';
import 'player_controller.dart';
import 'player_providers.dart';
import 'queue_model.dart';

/// Dauerhafter Mini-Player über der unteren Navigation
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(playerSnapshotProvider);
    final t = snap.current;
    if (t == null) return const SizedBox.shrink();
    final s = context.s;
    final player = ref.read(playerProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(DSpacing.s, 0, DSpacing.s, DSpacing.xs),
      child: Material(
        color: const Color(0xFF2A1A45),
        borderRadius: BorderRadius.circular(DRadius.m),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/player'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(DSpacing.s),
                child: Row(
                  children: [
                    Hero(tag: 'player-cover', child: CoverImage(imageId: t.coverImageId, size: 44, semanticLabel: t.title)),
                    const SizedBox(width: DSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            snap.error ?? t.artistLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: snap.error != null ? DColors.danger : DColors.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    FavoriteButton(trackId: t.id),
                    _PlayPauseButton(snap: snap, onPressed: player.togglePlay, size: 28, tooltipPlay: s.play, tooltipPause: s.pause),
                  ],
                ),
              ),
              const _MiniProgress(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniProgress extends ConsumerWidget {
  const _MiniProgress();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(positionProvider).value ?? ref.read(playerProvider).positionInfo;
    final dur = p.duration.inMilliseconds;
    final v = dur <= 0 ? 0.0 : (p.position.inMilliseconds / dur).clamp(0.0, 1.0);
    return LinearProgressIndicator(value: v, minHeight: 2, color: Colors.white, backgroundColor: Colors.white24);
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.snap, required this.onPressed, this.size = 32, required this.tooltipPlay, required this.tooltipPause, this.filled = false});
  final PlayerSnapshot snap;
  final VoidCallback onPressed;
  final double size;
  final String tooltipPlay;
  final String tooltipPause;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final busy = snap.loading || (snap.buffering && snap.playing);
    final icon = Icon(snap.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: size, color: filled ? Colors.black : Colors.white);
    final child = busy
        ? SizedBox(width: size * 0.8, height: size * 0.8, child: CircularProgressIndicator(strokeWidth: 2.5, color: filled ? Colors.black : Colors.white))
        : icon;
    if (filled) {
      return Semantics(
        button: true,
        label: snap.playing ? tooltipPause : tooltipPlay,
        child: SizedBox(
          width: size * 2.1,
          height: size * 2.1,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onPressed, child: Center(child: child)),
          ),
        ),
      );
    }
    return IconButton(tooltip: snap.playing ? tooltipPause : tooltipPlay, onPressed: onPressed, icon: child);
  }
}

class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.trackId, this.size = 24});
  final String trackId;
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(favoritesProvider.select((s) => s.contains(trackId)));
    final s = context.s;
    return IconButton(
      tooltip: fav ? s.favoriteRemove : s.favoriteAdd,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: Icon(
          fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(fav),
          size: size,
          color: fav ? DColors.favoriteStart : DColors.text,
        ),
      ),
      onPressed: () async {
        try {
          await ref.read(favoritesProvider.notifier).toggle(trackId);
        } catch (e) {
          if (context.mounted) showSnack(context, errorText(e));
        }
      },
    );
  }
}

class SeekBar extends ConsumerStatefulWidget {
  const SeekBar({super.key, this.compact = false});
  final bool compact;
  @override
  ConsumerState<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(positionProvider).value ?? ref.read(playerProvider).positionInfo;
    final snapDur = ref.watch(playerSnapshotProvider.select((s) => s.duration));
    final dur = (p.duration > Duration.zero ? p.duration : snapDur).inMilliseconds.toDouble();
    final pos = _drag ?? p.position.inMilliseconds.toDouble().clamp(0, dur <= 0 ? 0 : dur).toDouble();
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        activeTrackColor: Colors.white,
        secondaryActiveTrackColor: Colors.white30,
      ),
      child: Slider(
        value: dur <= 0 ? 0 : pos,
        max: dur <= 0 ? 1 : dur,
        secondaryTrackValue: dur <= 0 ? null : p.buffered.inMilliseconds.toDouble().clamp(0, dur).toDouble(),
        semanticFormatterCallback: (v) => formatDuration(Duration(milliseconds: v.round())),
        onChanged: dur <= 0 ? null : (v) => setState(() => _drag = v),
        onChangeEnd: (v) async {
          await ref.read(playerProvider).seek(Duration(milliseconds: v.round()));
          if (mounted) setState(() => _drag = null);
        },
      ),
    );
    final times = Padding(
      padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
      child: Row(
        children: [
          Text(formatDuration(Duration(milliseconds: pos.round())), style: const TextStyle(fontSize: 12, color: DColors.textMuted)),
          const Spacer(),
          Text(formatDuration(Duration(milliseconds: dur.round())), style: const TextStyle(fontSize: 12, color: DColors.textMuted)),
        ],
      ),
    );
    if (widget.compact) {
      return Row(children: [
        Text(formatDuration(Duration(milliseconds: pos.round())), style: const TextStyle(fontSize: 12, color: DColors.textMuted)),
        Expanded(child: slider),
        Text(formatDuration(Duration(milliseconds: dur.round())), style: const TextStyle(fontSize: 12, color: DColors.textMuted)),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [slider, times]);
  }
}

/// Wiedergabesteuerung (Shuffle, Zurück, Play/Pause, Weiter, Wiederholen)
class PlayerControls extends ConsumerWidget {
  const PlayerControls({super.key, this.large = true});
  final bool large;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final snap = ref.watch(playerSnapshotProvider);
    final player = ref.read(playerProvider);
    final repeatIcon = snap.repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded;
    final repeatLabel = switch (snap.repeat) {
      RepeatMode.off => s.repeatOff,
      RepeatMode.all => s.repeatAll,
      RepeatMode.one => s.repeatOne,
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: snap.shuffle ? s.shuffleOn : s.shuffleOff,
          isSelected: snap.shuffle,
          icon: Icon(Icons.shuffle_rounded, color: snap.shuffle ? DColors.primary : DColors.textMuted),
          onPressed: () => player.setShuffle(!snap.shuffle),
        ),
        IconButton(tooltip: s.previous, iconSize: large ? 40 : 28, icon: const Icon(Icons.skip_previous_rounded), onPressed: player.previous),
        _PlayPauseButton(snap: snap, onPressed: player.togglePlay, size: large ? 34 : 22, filled: true, tooltipPlay: s.play, tooltipPause: s.pause),
        IconButton(tooltip: s.next, iconSize: large ? 40 : 28, icon: const Icon(Icons.skip_next_rounded), onPressed: snap.hasNext ? player.next : null),
        IconButton(
          tooltip: repeatLabel,
          isSelected: snap.repeat != RepeatMode.off,
          icon: Icon(repeatIcon, color: snap.repeat != RepeatMode.off ? DColors.primary : DColors.textMuted),
          onPressed: player.cycleRepeat,
        ),
      ],
    );
  }
}

/// Vollständige Playeransicht
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final snap = ref.watch(playerSnapshotProvider);
    final t = snap.current;
    if (t == null) {
      return Scaffold(appBar: AppBar(), body: EmptyView(icon: Icons.music_off_rounded, title: s.nothingPlaying));
    }
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A1A6B), Color(0xFF120A20), DColors.background]),
        ),
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final landscape = c.maxWidth > c.maxHeight && c.maxWidth > 600;
            final coverSize = landscape ? (c.maxHeight - 120).clamp(160.0, 480.0) : (c.maxWidth - 48).clamp(160.0, 520.0).toDouble();
            final cover = Hero(
              tag: 'player-cover',
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  key: ValueKey(t.coverImageId ?? t.id),
                  decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 48, offset: Offset(0, 20))]),
                  child: CoverImage(imageId: t.coverImageId, size: coverSize.toDouble(), radius: DRadius.l, semanticLabel: t.title),
                ),
              ),
            );
            final info = _NowPlayingInfo(track: t, snap: snap);
            return Column(
              children: [
                _PlayerTopBar(track: t),
                Expanded(
                  child: landscape
                      ? Row(children: [
                          Expanded(child: Center(child: cover)),
                          Expanded(child: SingleChildScrollView(child: info)),
                        ])
                      : SingleChildScrollView(
                          child: Column(children: [
                            const SizedBox(height: DSpacing.l),
                            Center(child: cover),
                            const SizedBox(height: DSpacing.xl),
                            info,
                          ]),
                        ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _PlayerTopBar extends StatelessWidget {
  const _PlayerTopBar({required this.track});
  final Track track;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Row(
      children: [
        IconButton(tooltip: s.close, icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32), onPressed: () => context.pop()),
        Expanded(
          child: Column(
            children: [
              Text(s.nowPlaying.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.2, color: DColors.textMuted, fontWeight: FontWeight.w700)),
              Text(track.release.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        IconButton(tooltip: s.queue, icon: const Icon(Icons.queue_music_rounded), onPressed: () => context.push('/queue')),
      ],
    );
  }
}

class _NowPlayingInfo extends ConsumerWidget {
  const _NowPlayingInfo({required this.track, required this.snap});
  final Track track;
  final PlayerSnapshot snap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      children: [
                        for (var i = 0; i < track.artists.length; i++)
                          InkWell(
                            onTap: () => context.push('/artist/${track.artists[i].id}'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '${track.artists[i].featured ? 'feat. ' : ''}${track.artists[i].name}${i < track.artists.length - 1 ? ', ' : ''}',
                                style: const TextStyle(color: DColors.textMuted, fontSize: 16),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              FavoriteButton(trackId: track.id, size: 28),
            ],
          ),
          if (snap.error != null)
            Padding(
              padding: const EdgeInsets.only(top: DSpacing.s),
              child: Text(snap.error!, style: const TextStyle(color: DColors.danger)),
            ),
          const SizedBox(height: DSpacing.m),
          const SeekBar(),
          const SizedBox(height: DSpacing.s),
          const PlayerControls(),
          const SizedBox(height: DSpacing.l),
          Row(
            children: [
              Icon(
                snap.source == PlaybackSource.local ? Icons.download_done_rounded : Icons.wifi_rounded,
                size: 16,
                color: snap.source == PlaybackSource.local ? DColors.secondary : DColors.textDim,
              ),
              const SizedBox(width: 6),
              Text(
                snap.source == PlaybackSource.local ? s.sourceLocal : (snap.source == PlaybackSource.stream ? s.sourceStream : ''),
                style: const TextStyle(color: DColors.textDim, fontSize: 12),
              ),
              const Spacer(),
              TextButton.icon(onPressed: () => context.push('/settings/equalizer'), icon: const Icon(Icons.equalizer_rounded, size: 18), label: Text(s.equalizer)),
            ],
          ),
          const SizedBox(height: DSpacing.xl),
        ],
      ),
    );
  }
}

/// Warteschlange: anzeigen, umsortieren, entfernen
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final snap = ref.watch(playerSnapshotProvider);
    final player = ref.read(playerProvider);
    final cur = snap.current;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.queue),
        actions: [
          if (snap.queue.isNotEmpty)
            TextButton(onPressed: () async {
              await player.clear();
              if (context.mounted) context.pop();
            }, child: Text(s.clearQueue)),
        ],
      ),
      body: snap.queue.isEmpty
          ? EmptyView(icon: Icons.queue_music_rounded, title: s.queueEmpty)
          : CustomScrollView(
              slivers: [
                if (cur != null) ...[
                  SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Text(s.nowPlaying, style: Theme.of(context).textTheme.titleMedium))),
                  SliverToBoxAdapter(
                    child: ListTile(
                      leading: CoverImage(imageId: cur.coverImageId, size: 48),
                      title: Text(cur.title, style: const TextStyle(color: DColors.primaryHover, fontWeight: FontWeight.w700)),
                      subtitle: Text(cur.artistLine),
                    ),
                  ),
                  SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(s.upNext, style: Theme.of(context).textTheme.titleMedium))),
                ],
                SliverReorderableList(
                  itemCount: snap.queue.length,
                  onReorderItem: player.move,
                  itemBuilder: (c, i) {
                    final e = snap.queue[i];
                    final isCur = i == snap.index;
                    return Material(
                      key: ValueKey(e.uid),
                      color: Colors.transparent,
                      child: Dismissible(
                        key: ValueKey('d${e.uid}'),
                        direction: DismissDirection.endToStart,
                        background: Container(color: DColors.danger.withValues(alpha: 0.3), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), child: const Icon(Icons.delete_rounded)),
                        onDismissed: (_) => player.removeAt(i),
                        child: ListTile(
                          leading: CoverImage(imageId: e.track.coverImageId, size: 44),
                          title: Text(e.track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isCur ? DColors.primaryHover : null, fontWeight: isCur ? FontWeight.w700 : null)),
                          subtitle: Text(e.track.artistLine, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => player.jumpTo(i),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(tooltip: s.removeFromQueue, icon: const Icon(Icons.close_rounded), onPressed: () => player.removeAt(i)),
                              ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle_rounded))),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: DSpacing.xxl)),
              ],
            ),
    );
  }
}

/// Playerleiste für breite Bildschirme (Seitenleistenlayout)
class WidePlayerBar extends ConsumerWidget {
  const WidePlayerBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(playerSnapshotProvider);
    final t = snap.current;
    if (t == null) return const SizedBox.shrink();
    final s = context.s;
    return Material(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 88,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: InkWell(
                    onTap: () => context.push('/player'),
                    child: Row(
                      children: [
                        CoverImage(imageId: t.coverImageId, size: 56),
                        const SizedBox(width: DSpacing.m),
                        Flexible(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(t.artistLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: DColors.textMuted, fontSize: 13)),
                            ],
                          ),
                        ),
                        FavoriteButton(trackId: t.id),
                      ],
                    ),
                  ),
                ),
                const Expanded(
                  flex: 4,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [PlayerControls(large: false), SeekBar(compact: true)]),
                ),
                Expanded(
                  flex: 3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(tooltip: s.equalizer, icon: const Icon(Icons.equalizer_rounded), onPressed: () => context.push('/settings/equalizer')),
                      IconButton(tooltip: s.queue, icon: const Icon(Icons.queue_music_rounded), onPressed: () => context.push('/queue')),
                      IconButton(tooltip: s.openPlayer, icon: const Icon(Icons.open_in_full_rounded), onPressed: () => context.push('/player')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
