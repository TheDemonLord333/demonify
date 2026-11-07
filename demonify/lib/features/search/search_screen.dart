import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/cover_image.dart';
import '../../core/widgets/media_widgets.dart';
import '../../core/widgets/section.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import '../catalog/models.dart';
import '../player/player_providers.dart';

/// Live-Suche: ab dem ersten Buchstaben, kurze Entprellung, veraltete Anfragen werden abgebrochen.
class SearchState {
  const SearchState({this.query = '', this.results, this.loading = false, this.error});
  final String query;
  final SearchResults? results;
  final bool loading;
  final Object? error;
}

final searchProvider = NotifierProvider.autoDispose<SearchController, SearchState>(SearchController.new);

class SearchController extends Notifier<SearchState> {
  Timer? _debounce;
  CancelToken? _cancel;
  int _seq = 0;

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _cancel?.cancel();
    });
    return const SearchState();
  }

  void setQuery(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      _cancel?.cancel();
      state = const SearchState();
      return;
    }
    state = SearchState(query: q, results: state.results, loading: true);
    _debounce = Timer(const Duration(milliseconds: 180), () => _run(q));
  }

  Future<void> retry() => _run(state.query);

  Future<void> _run(String q) async {
    final api = ref.read(apiProvider);
    if (api == null) return;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    final seq = ++_seq;
    try {
      final res = await api.get('search', query: {'q': q, 'limit': 8}, cancel: cancel);
      if (seq != _seq) return; // veraltete Antwort ignorieren
      state = SearchState(query: q, results: SearchResults.fromJson(res));
    } on ApiException catch (e) {
      if (e.code == 'CANCELLED' || seq != _seq) return;
      state = SearchState(query: q, results: state.results, error: e);
    }
  }
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final st = ref.watch(searchProvider);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(DSpacing.l, DSpacing.l, DSpacing.l, DSpacing.s),
            child: Semantics(
              textField: true,
              label: s.searchHint,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: (v) => ref.read(searchProvider.notifier).setQuery(v),
                decoration: InputDecoration(
                  hintText: s.searchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: s.clear,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _ctrl.clear();
                            ref.read(searchProvider.notifier).setQuery('');
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
          ),
          if (st.loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
          Expanded(child: _body(context, st)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, SearchState st) {
    final s = context.s;
    if (st.query.trim().isEmpty) {
      return EmptyView(icon: Icons.manage_search_rounded, title: s.searchEmptyTitle, message: s.searchEmptyMessage);
    }
    if (st.error != null && st.results == null) {
      return ErrorView(error: st.error!, onRetry: () => ref.read(searchProvider.notifier).retry());
    }
    final r = st.results;
    if (r == null) return const SizedBox.shrink();
    if (r.isEmpty && !st.loading) {
      return EmptyView(icon: Icons.search_off_rounded, title: s.searchNoResults(st.query));
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: DSpacing.xxl),
      children: [
        if (st.error != null)
          Padding(
            padding: const EdgeInsets.all(DSpacing.l),
            child: Text(errorText(st.error!), style: const TextStyle(color: DColors.danger)),
          ),
        if (r.tracks.isNotEmpty) ...[
          SectionHeader(title: s.songs),
          for (var i = 0; i < r.tracks.length; i++)
            TrackTile(
              track: r.tracks[i],
              showRelease: true,
              onTap: () => ref.read(playerProvider).playTracks([r.tracks[i]], contextType: 'search'),
            ),
        ],
        if (r.artists.isNotEmpty) ...[
          SectionHeader(title: s.artists),
          for (final a in r.artists)
            ListTile(
              leading: CoverImage(imageId: a.imageId, size: 48, circle: true, icon: Icons.person_rounded),
              title: Text(a.name),
              subtitle: Text(s.artistLabel),
              onTap: () => context.push('/artist/${a.id}'),
            ),
        ],
        if (r.releases.isNotEmpty) ...[
          SectionHeader(title: s.releases),
          for (final rel in r.releases)
            ListTile(
              leading: CoverImage(imageId: rel.coverImageId, size: 48),
              title: Text(rel.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text([releaseTypeLabel(context, rel.type), rel.albumArtist.name, if (rel.year != null) '${rel.year}'].join(' • ')),
              onTap: () => context.push('/release/${rel.id}'),
            ),
        ],
        if (r.playlists.isNotEmpty) ...[
          SectionHeader(title: s.playlists),
          for (final p in r.playlists)
            ListTile(
              leading: CoverImage(imageId: p.coverImageIds.isEmpty ? null : p.coverImageIds.first, size: 48, icon: Icons.queue_music_rounded),
              title: Text(p.name),
              subtitle: Text(s.trackCount(p.trackCount)),
              onTap: () => context.push('/playlist/${p.id}'),
            ),
        ],
      ],
    );
  }
}
