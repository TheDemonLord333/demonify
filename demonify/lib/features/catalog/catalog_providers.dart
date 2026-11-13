import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../auth/auth_controller.dart';
import '../library/library_model.dart';
import 'models.dart';

ApiClient requireApi(Ref ref) {
  final api = ref.watch(apiProvider);
  if (api == null) throw ApiException(code: 'UNAUTHORIZED', message: 'Nicht angemeldet.');
  return api;
}

final homeProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  return HomeData.fromJson(await requireApi(ref).get('home'));
});

final releaseDetailProvider = FutureProvider.autoDispose.family<ReleaseDetail, String>((ref, id) async {
  return ReleaseDetail.fromJson(await requireApi(ref).get('releases/$id'));
});

final artistDetailProvider = FutureProvider.autoDispose.family<ArtistDetail, String>((ref, id) async {
  return ArtistDetail.fromJson(await requireApi(ref).get('artists/$id'));
});

final artistTracksProvider = FutureProvider.autoDispose.family<List<Track>, String>((ref, id) async {
  final api = requireApi(ref);
  final all = <Track>[];
  int? offset = 0;
  while (offset != null && all.length < 1000) {
    final res = PageResult.fromJson(await api.get('artists/$id/tracks', query: {'offset': offset, 'limit': 100}), Track.fromJson);
    all.addAll(res.items);
    offset = res.nextOffset;
  }
  return all;
});

enum LibrarySort { recent, title, artist }

class ReleaseListQuery {
  const ReleaseListQuery({this.type, this.savedOnly = false});
  final ReleaseType? type;
  final bool savedOnly;
  @override
  bool operator ==(Object other) => other is ReleaseListQuery && other.type == type && other.savedOnly == savedOnly;
  @override
  int get hashCode => Object.hash(type, savedOnly);
}

/// Alle Veröffentlichungen (Katalog) oder gespeicherte (Bibliothek)
final releasesProvider = FutureProvider.autoDispose.family<List<Release>, ReleaseListQuery>((ref, q) async {
  final api = requireApi(ref);
  final out = <Release>[];
  int? offset = 0;
  while (offset != null && out.length < 2000) {
    final res = PageResult.fromJson(
      await api.get(q.savedOnly ? 'library/releases' : 'releases', query: {
        'offset': offset,
        'limit': 100,
        if (q.type != null) 'type': q.type!.apiName,
      }),
      Release.fromJson,
    );
    out.addAll(res.items);
    offset = res.nextOffset;
  }
  return out;
});

final artistsProvider = FutureProvider.autoDispose.family<List<ArtistRef>, bool>((ref, followedOnly) async {
  final api = requireApi(ref);
  final out = <ArtistRef>[];
  int? offset = 0;
  while (offset != null && out.length < 2000) {
    final res = PageResult.fromJson(
      await api.get(followedOnly ? 'library/artists' : 'artists', query: {'offset': offset, 'limit': 100}),
      ArtistRef.fromJson,
    );
    out.addAll(res.items);
    offset = res.nextOffset;
  }
  return out;
});

/// Persönliche Bibliothek als eine Liste: Playlists, gespeicherte Veröffentlichungen, gefolgte Künstler.
/// Gesamtansicht und alle Filter der Bibliothek lesen dieselben Einträge.
final libraryEntriesProvider = FutureProvider.autoDispose<List<LibraryEntry>>((ref) async {
  final api = requireApi(ref);
  Future<List<Map<String, dynamic>>> all(String path) async {
    final out = <Map<String, dynamic>>[];
    int? offset = 0;
    while (offset != null && out.length < 5000) {
      final r = await api.get(path, query: {'offset': offset, 'limit': 100});
      out.addAll((r['items'] as List).cast<Map<String, dynamic>>());
      offset = (r['nextOffset'] as num?)?.toInt();
    }
    return out;
  }

  final (playlists, releases, artists) = await (ref.watch(playlistsProvider.future), all('library/releases'), all('library/artists')).wait;
  DateTime? ts(Object? v) => v is String ? DateTime.tryParse(v) : null;
  return [
    ...playlists.map(PlaylistLibraryEntry.new),
    ...releases.map((j) => ReleaseLibraryEntry(Release.fromJson(j), ts(j['savedAt']))),
    ...artists.map((j) => ArtistLibraryEntry(ArtistRef.fromJson(j), ts(j['followedAt']))),
  ];
});

final favoriteTracksProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  final api = requireApi(ref);
  // bei Änderungen der Favoriten neu laden
  ref.watch(favoritesProvider);
  final out = <Track>[];
  int? offset = 0;
  while (offset != null && out.length < 5000) {
    final res = PageResult.fromJson(await api.get('library/favorites', query: {'offset': offset, 'limit': 100}), Track.fromJson);
    out.addAll(res.items);
    offset = res.nextOffset;
  }
  return out;
});

final favoritesProvider = NotifierProvider<FavoritesController, Set<String>>(FavoritesController.new);

/// Lieblingssongs (IDs) mit optimistischer Aktualisierung
class FavoritesController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(currentUserProvider.select((u) => u?.id));
    Future.microtask(refresh);
    return {};
  }

  Future<void> refresh() async {
    final api = ref.read(apiProvider);
    if (api == null) return;
    try {
      final res = await api.get('library/favorites/ids');
      state = ((res['ids'] as List?) ?? const []).cast<String>().toSet();
    } catch (_) {}
  }

  Future<void> toggle(String trackId) async {
    final api = ref.read(apiProvider);
    if (api == null) return;
    final was = state.contains(trackId);
    state = was ? ({...state}..remove(trackId)) : {...state, trackId};
    try {
      if (was) {
        await api.delete('library/favorites/$trackId');
      } else {
        await api.put('library/favorites/$trackId');
      }
    } catch (e) {
      state = was ? {...state, trackId} : ({...state}..remove(trackId));
      rethrow;
    }
  }
}

final playlistsProvider = FutureProvider.autoDispose<List<PlaylistSummary>>((ref) async {
  final res = await requireApi(ref).get('playlists');
  return (res['items'] as List).map((e) => PlaylistSummary.fromJson(e as Map<String, dynamic>)).toList();
});

final playlistDetailProvider = FutureProvider.autoDispose.family<PlaylistDetail, String>((ref, id) async {
  return PlaylistDetail.fromJson(await requireApi(ref).get('playlists/$id'));
});

/// Playlist-Aktionen
class PlaylistActions {
  PlaylistActions(this._ref);
  final Ref _ref;
  ApiClient get _api => _ref.read(apiProvider)!;

  Future<String> create(String name, {List<String> trackIds = const []}) async {
    final res = await _api.post('playlists', {'name': name, if (trackIds.isNotEmpty) 'trackIds': trackIds});
    _ref.invalidate(playlistsProvider);
    return (res['playlist'] as Map<String, dynamic>)['id'] as String;
  }

  Future<void> rename(String id, String name) async {
    await _api.patch('playlists/$id', {'name': name});
    _ref.invalidate(playlistsProvider);
    _ref.invalidate(playlistDetailProvider(id));
  }

  Future<void> delete(String id) async {
    await _api.delete('playlists/$id');
    _ref.invalidate(playlistsProvider);
  }

  Future<void> addTracks(String id, List<String> trackIds) async {
    await _api.post('playlists/$id/tracks', {'trackIds': trackIds});
    _ref.invalidate(playlistsProvider);
    _ref.invalidate(playlistDetailProvider(id));
  }

  Future<void> removeEntry(String id, String entryId) async {
    await _api.delete('playlists/$id/entries/$entryId');
    _ref.invalidate(playlistDetailProvider(id));
    _ref.invalidate(playlistsProvider);
  }

  Future<void> reorder(String id, List<String> entryIds) async {
    await _api.put('playlists/$id/order', {'entryIds': entryIds});
  }
}

final playlistActionsProvider = Provider<PlaylistActions>(PlaylistActions.new);

class LibraryActions {
  LibraryActions(this._ref);
  final Ref _ref;
  ApiClient get _api => _ref.read(apiProvider)!;

  Future<void> setSaved(String releaseId, bool saved) async {
    if (saved) {
      await _api.put('library/releases/$releaseId');
    } else {
      await _api.delete('library/releases/$releaseId');
    }
    _ref.invalidate(releaseDetailProvider(releaseId));
    _ref.invalidate(releasesProvider);
    _ref.invalidate(libraryEntriesProvider);
  }

  Future<void> setFollowing(String artistId, bool follow) async {
    if (follow) {
      await _api.put('library/artists/$artistId');
    } else {
      await _api.delete('library/artists/$artistId');
    }
    _ref.invalidate(artistDetailProvider(artistId));
    _ref.invalidate(artistsProvider);
    _ref.invalidate(libraryEntriesProvider);
  }
}

final libraryActionsProvider = Provider<LibraryActions>(LibraryActions.new);
