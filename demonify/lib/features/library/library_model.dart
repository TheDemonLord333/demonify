import '../catalog/models.dart';

/// Kategorien der Bibliothek. `null` = Gesamtansicht ohne Filter.
enum LibraryFilter { playlists, albums, artists }

/// Ein Eintrag der persönlichen Bibliothek: eigene Playlist, gespeicherte Veröffentlichung oder gefolgter Künstler.
/// Gesamtansicht und Filter verwenden dieselbe Liste – ein Filter blendet nur Kategorien aus.
sealed class LibraryEntry {
  const LibraryEntry();
  String get id;
  String get name;

  /// Hinzugefügt/gefolgt bzw. zuletzt geändert (Playlist) – für „Zuletzt“
  DateTime? get addedAt;
  LibraryFilter get category;
}

class PlaylistLibraryEntry extends LibraryEntry {
  const PlaylistLibraryEntry(this.playlist);
  final PlaylistSummary playlist;
  @override
  String get id => playlist.id;
  @override
  String get name => playlist.name;
  @override
  DateTime? get addedAt => playlist.updatedAt;
  @override
  LibraryFilter get category => LibraryFilter.playlists;
}

class ReleaseLibraryEntry extends LibraryEntry {
  const ReleaseLibraryEntry(this.release, this.savedAt);
  final Release release;
  final DateTime? savedAt;
  @override
  String get id => release.id;
  @override
  String get name => release.title;
  @override
  DateTime? get addedAt => savedAt;
  @override
  LibraryFilter get category => LibraryFilter.albums;
}

class ArtistLibraryEntry extends LibraryEntry {
  const ArtistLibraryEntry(this.artist, this.followedAt);
  final ArtistRef artist;
  final DateTime? followedAt;
  @override
  String get id => artist.id;
  @override
  String get name => artist.name;
  @override
  DateTime? get addedAt => followedAt;
  @override
  LibraryFilter get category => LibraryFilter.artists;
}

enum LibraryOrder { recent, name }

/// Filtert die gemeinsame Eintragsliste (null = alles) und sortiert sie.
List<LibraryEntry> libraryView(List<LibraryEntry> all, {LibraryFilter? filter, LibraryOrder order = LibraryOrder.recent}) {
  final list = filter == null ? List.of(all) : all.where((e) => e.category == filter).toList();
  switch (order) {
    case LibraryOrder.recent:
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      // stabil: gleiche Zeitpunkte behalten die Reihenfolge des Servers
      final indexed = list.asMap().entries.toList()
        ..sort((a, b) {
          final c = (b.value.addedAt ?? epoch).compareTo(a.value.addedAt ?? epoch);
          return c != 0 ? c : a.key.compareTo(b.key);
        });
      return indexed.map((e) => e.value).toList();
    case LibraryOrder.name:
      return list..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}

/// Anzahl je Kategorie (für Chips und leere Kategorien)
Map<LibraryFilter, int> libraryCounts(List<LibraryEntry> all) => {for (final f in LibraryFilter.values) f: all.where((e) => e.category == f).length};
