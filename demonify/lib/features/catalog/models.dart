// Servermodelle (entsprechen den API-DTOs). Lokale Download-Daten liegen getrennt
// in features/downloads/download_models.dart.

enum ReleaseType {
  album,
  ep,
  single;

  static ReleaseType parse(String? s) => switch (s) {
        'EP' => ReleaseType.ep,
        'SINGLE' => ReleaseType.single,
        _ => ReleaseType.album,
      };

  String get apiName => switch (this) {
        ReleaseType.album => 'ALBUM',
        ReleaseType.ep => 'EP',
        ReleaseType.single => 'SINGLE',
      };
}

class ArtistRef {
  const ArtistRef({required this.id, required this.name, this.imageId});
  final String id;
  final String name;
  final String? imageId;

  factory ArtistRef.fromJson(Map<String, dynamic> j) =>
      ArtistRef(id: j['id'] as String, name: j['name'] as String, imageId: j['imageId'] as String?);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'imageId': imageId};
}

class TrackArtist {
  const TrackArtist({required this.id, required this.name, required this.featured});
  final String id;
  final String name;
  final bool featured;
  factory TrackArtist.fromJson(Map<String, dynamic> j) =>
      TrackArtist(id: j['id'] as String, name: j['name'] as String, featured: j['role'] == 'FEATURED');
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': featured ? 'FEATURED' : 'PRIMARY'};
}

class ReleaseRef {
  const ReleaseRef({
    required this.id,
    required this.title,
    required this.type,
    this.year,
    this.coverImageId,
    required this.albumArtist,
  });
  final String id;
  final String title;
  final ReleaseType type;
  final int? year;
  final String? coverImageId;
  final ArtistRef albumArtist;

  factory ReleaseRef.fromJson(Map<String, dynamic> j) => ReleaseRef(
        id: j['id'] as String,
        title: j['title'] as String,
        type: ReleaseType.parse(j['type'] as String?),
        year: j['year'] as int?,
        coverImageId: j['coverImageId'] as String?,
        albumArtist: ArtistRef.fromJson(j['albumArtist'] as Map<String, dynamic>),
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.apiName,
        'year': year,
        'coverImageId': coverImageId,
        'albumArtist': albumArtist.toJson(),
      };
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.discNumber,
    required this.trackNumber,
    required this.durationMs,
    required this.available,
    this.genre,
    this.year,
    this.codec,
    this.coverImageId,
    required this.hasOwnCover,
    required this.artists,
    required this.release,
  });

  final String id;
  final String title;
  final int discNumber;
  final int trackNumber;
  final int durationMs;
  final bool available;
  final String? genre;
  final int? year;
  final String? codec;

  /// Effektives Cover (individuelles Songcover → Veröffentlichungscover → null = Platzhalter)
  final String? coverImageId;
  final bool hasOwnCover;
  final List<TrackArtist> artists;
  final ReleaseRef release;

  Duration get duration => Duration(milliseconds: durationMs);
  String get artistLine {
    final primary = artists.where((a) => !a.featured).map((a) => a.name).join(', ');
    final feat = artists.where((a) => a.featured).map((a) => a.name).toList();
    final p = primary.isEmpty ? release.albumArtist.name : primary;
    return feat.isEmpty ? p : '$p feat. ${feat.join(', ')}';
  }

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String,
        discNumber: (j['discNumber'] as num?)?.toInt() ?? 1,
        trackNumber: (j['trackNumber'] as num?)?.toInt() ?? 1,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        available: j['available'] as bool? ?? true,
        genre: j['genre'] as String?,
        year: (j['year'] as num?)?.toInt(),
        codec: j['codec'] as String?,
        coverImageId: j['coverImageId'] as String?,
        hasOwnCover: j['hasOwnCover'] as bool? ?? false,
        artists: ((j['artists'] as List?) ?? const []).map((e) => TrackArtist.fromJson(e as Map<String, dynamic>)).toList(),
        release: ReleaseRef.fromJson(j['release'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'discNumber': discNumber,
        'trackNumber': trackNumber,
        'durationMs': durationMs,
        'available': available,
        'genre': genre,
        'year': year,
        'codec': codec,
        'coverImageId': coverImageId,
        'hasOwnCover': hasOwnCover,
        'artists': artists.map((a) => a.toJson()).toList(),
        'release': release.toJson(),
      };
}

class Release {
  const Release({
    required this.id,
    required this.title,
    required this.type,
    this.year,
    this.genre,
    this.coverImageId,
    required this.albumArtist,
    required this.trackCount,
    this.durationMs,
  });
  final String id;
  final String title;
  final ReleaseType type;
  final int? year;
  final String? genre;
  final String? coverImageId;
  final ArtistRef albumArtist;
  final int trackCount;
  final int? durationMs;

  factory Release.fromJson(Map<String, dynamic> j) => Release(
        id: j['id'] as String,
        title: j['title'] as String,
        type: ReleaseType.parse(j['type'] as String?),
        year: (j['year'] as num?)?.toInt(),
        genre: j['genre'] as String?,
        coverImageId: j['coverImageId'] as String?,
        albumArtist: ArtistRef.fromJson(j['albumArtist'] as Map<String, dynamic>),
        trackCount: (j['trackCount'] as num?)?.toInt() ?? 0,
        durationMs: (j['durationMs'] as num?)?.toInt(),
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.apiName,
        'year': year,
        'genre': genre,
        'coverImageId': coverImageId,
        'albumArtist': albumArtist.toJson(),
        'trackCount': trackCount,
        'durationMs': durationMs,
      };
}

class ReleaseDetail {
  const ReleaseDetail({required this.release, required this.saved, required this.tracks});
  final Release release;
  final bool saved;
  final List<Track> tracks;
  factory ReleaseDetail.fromJson(Map<String, dynamic> j) => ReleaseDetail(
        release: Release.fromJson(j['release'] as Map<String, dynamic>),
        saved: j['saved'] as bool? ?? false,
        tracks: (j['tracks'] as List).map((e) => Track.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class ArtistDetail {
  const ArtistDetail({
    required this.artist,
    required this.following,
    required this.trackCount,
    required this.releases,
    required this.appearsOn,
    required this.topTracks,
  });
  final ArtistRef artist;
  final bool following;
  final int trackCount;
  final List<Release> releases;
  final List<Release> appearsOn;
  final List<Track> topTracks;
  factory ArtistDetail.fromJson(Map<String, dynamic> j) => ArtistDetail(
        artist: ArtistRef.fromJson(j['artist'] as Map<String, dynamic>),
        following: j['following'] as bool? ?? false,
        trackCount: (j['trackCount'] as num?)?.toInt() ?? 0,
        releases: (j['releases'] as List).map((e) => Release.fromJson(e as Map<String, dynamic>)).toList(),
        appearsOn: (j['appearsOn'] as List).map((e) => Release.fromJson(e as Map<String, dynamic>)).toList(),
        topTracks: (j['topTracks'] as List).map((e) => Track.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    this.description,
    required this.trackCount,
    this.coverImageIds = const [],
    this.updatedAt,
  });
  final String id;
  final String name;
  final String? description;
  final int trackCount;
  final List<String> coverImageIds;
  final DateTime? updatedAt;
  factory PlaylistSummary.fromJson(Map<String, dynamic> j) => PlaylistSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        trackCount: (j['trackCount'] as num?)?.toInt() ?? 0,
        coverImageIds: ((j['coverImageIds'] as List?) ?? const []).cast<String>(),
        updatedAt: j['updatedAt'] == null ? null : DateTime.tryParse(j['updatedAt'] as String),
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'trackCount': trackCount,
        'coverImageIds': coverImageIds,
        'updatedAt': updatedAt?.toIso8601String(),
      };
}

class PlaylistEntry {
  const PlaylistEntry({required this.entryId, required this.position, required this.track});
  final String entryId;
  final int position;
  final Track track;
  factory PlaylistEntry.fromJson(Map<String, dynamic> j) => PlaylistEntry(
        entryId: j['entryId'] as String,
        position: (j['position'] as num).toInt(),
        track: Track.fromJson(j['track'] as Map<String, dynamic>),
      );
}

class PlaylistDetail {
  const PlaylistDetail({required this.playlist, required this.entries, required this.durationMs});
  final PlaylistSummary playlist;
  final List<PlaylistEntry> entries;
  final int durationMs;
  factory PlaylistDetail.fromJson(Map<String, dynamic> j) => PlaylistDetail(
        playlist: PlaylistSummary.fromJson(j['playlist'] as Map<String, dynamic>),
        entries: (j['entries'] as List).map((e) => PlaylistEntry.fromJson(e as Map<String, dynamic>)).toList(),
        durationMs: ((j['playlist'] as Map<String, dynamic>)['durationMs'] as num?)?.toInt() ?? 0,
      );
}

class PageResult<T> {
  const PageResult({required this.items, required this.total, this.nextOffset});
  final List<T> items;
  final int total;
  final int? nextOffset;
  factory PageResult.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) parse) => PageResult(
        items: (j['items'] as List).map((e) => parse(e as Map<String, dynamic>)).toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        nextOffset: (j['nextOffset'] as num?)?.toInt(),
      );
}

class HomeData {
  const HomeData({
    required this.recentlyPlayed,
    required this.newReleases,
    required this.playlists,
    required this.favoritesCount,
    required this.followedArtists,
  });
  final List<Track> recentlyPlayed;
  final List<Release> newReleases;
  final List<PlaylistSummary> playlists;
  final int favoritesCount;
  final List<ArtistRef> followedArtists;
  factory HomeData.fromJson(Map<String, dynamic> j) => HomeData(
        recentlyPlayed: (j['recentlyPlayed'] as List).map((e) => Track.fromJson(e as Map<String, dynamic>)).toList(),
        newReleases: (j['newReleases'] as List).map((e) => Release.fromJson(e as Map<String, dynamic>)).toList(),
        playlists: (j['playlists'] as List).map((e) => PlaylistSummary.fromJson(e as Map<String, dynamic>)).toList(),
        favoritesCount: (j['favoritesCount'] as num?)?.toInt() ?? 0,
        followedArtists: (j['followedArtists'] as List).map((e) => ArtistRef.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class SearchResults {
  const SearchResults({
    required this.query,
    required this.tracks,
    required this.artists,
    required this.releases,
    required this.playlists,
  });
  final String query;
  final List<Track> tracks;
  final List<ArtistRef> artists;
  final List<Release> releases;
  final List<PlaylistSummary> playlists;
  bool get isEmpty => tracks.isEmpty && artists.isEmpty && releases.isEmpty && playlists.isEmpty;

  factory SearchResults.fromJson(Map<String, dynamic> j) {
    List<T> items<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((j[key] as Map<String, dynamic>)['items'] as List).map((e) => f(e as Map<String, dynamic>)).toList();
    return SearchResults(
      query: j['query'] as String? ?? '',
      tracks: items('tracks', Track.fromJson),
      artists: items('artists', ArtistRef.fromJson),
      releases: items('releases', Release.fromJson),
      playlists: items('playlists', PlaylistSummary.fromJson),
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    this.displayName,
    required this.isAdmin,
    this.email,
    this.emailVerified = false,
    this.mustChangePassword = false,
  });
  final String id;
  final String username;
  final String? displayName;
  final bool isAdmin;

  /// Bestätigte E-Mail-Adresse (null, solange keine bestätigt ist)
  final String? email;
  final bool emailVerified;

  /// Startpasswort → Ersteinrichtung erforderlich (vom Server erzwungen)
  final bool mustChangePassword;
  String get label => (displayName?.isNotEmpty ?? false) ? displayName! : username;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['displayName'] as String?,
        isAdmin: j['role'] == 'ADMIN',
        email: j['email'] as String?,
        emailVerified: j['emailVerified'] as bool? ?? false,
        mustChangePassword: j['mustChangePassword'] as bool? ?? false,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'role': isAdmin ? 'ADMIN' : 'USER',
        'email': email,
        'emailVerified': emailVerified,
        'mustChangePassword': mustChangePassword,
      };
}

/// Hinweise des Servers zur Ersteinrichtung
class SetupInfo {
  const SetupInfo({this.emailRequired = false, this.passwordResetAvailable = false, this.pendingEmail});
  final bool emailRequired;
  final bool passwordResetAvailable;

  /// Adresse, deren Bestätigungslink gerade aussteht
  final String? pendingEmail;

  factory SetupInfo.fromJson(Map<String, dynamic>? j) => SetupInfo(
        emailRequired: j?['emailRequired'] as bool? ?? false,
        passwordResetAvailable: j?['passwordResetAvailable'] as bool? ?? false,
        pendingEmail: j?['pendingEmail'] as String?,
      );
  SetupInfo withPending(String? email) => SetupInfo(emailRequired: emailRequired, passwordResetAvailable: passwordResetAvailable, pendingEmail: email);
}
