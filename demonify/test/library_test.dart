import 'package:demonify/core/theme/theme.dart';
import 'package:demonify/features/catalog/catalog_providers.dart';
import 'package:demonify/features/catalog/models.dart';
import 'package:demonify/features/downloads/download_manager.dart';
import 'package:demonify/features/library/library_model.dart';
import 'package:demonify/features/library/library_screen.dart';
import 'package:demonify/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

final _entries = <LibraryEntry>[
  PlaylistLibraryEntry(PlaylistSummary(id: 'p1', name: 'Meine Playlist', trackCount: 3, updatedAt: DateTime.utc(2026, 1, 3))),
  ReleaseLibraryEntry(
    const Release(
      id: 'r1',
      title: 'Gespeichertes Album',
      type: ReleaseType.album,
      albumArtist: ArtistRef(id: 'a9', name: 'Band'),
      trackCount: 9,
    ),
    DateTime.utc(2026, 1, 5),
  ),
  ArtistLibraryEntry(const ArtistRef(id: 'a1', name: 'Gefolgter Künstler'), DateTime.utc(2026, 1, 4)),
];

Widget _app(List<LibraryEntry> entries) => ProviderScope(
  overrides: [libraryEntriesProvider.overrideWith((ref) async => entries), downloadsProvider.overrideWith(() => FakeDownloads({}))],
  child: MaterialApp(
    theme: buildDemonifyTheme(),
    locale: const Locale('de'),
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: const Scaffold(body: LibraryScreen()),
  ),
);

Finder _chip(String name) => find.byKey(ValueKey('library-filter-$name'));
bool _selected(WidgetTester t, String name) => t.widget<FilterChip>(_chip(name)).selected;

void main() {
  group('libraryView', () {
    test('ohne Filter alle Kategorien, nach „Zuletzt“ gemischt sortiert', () {
      final v = libraryView(_entries);
      expect(v.map((e) => e.id), ['r1', 'a1', 'p1']);
    });
    test('Filter verwenden dieselben Einträge wie die Gesamtansicht', () {
      for (final f in LibraryFilter.values) {
        final filtered = libraryView(_entries, filter: f);
        expect(filtered, everyElement(predicate<LibraryEntry>((e) => e.category == f)));
        expect(filtered.every((e) => libraryView(_entries).contains(e)), isTrue);
      }
      final union = LibraryFilter.values.expand((f) => libraryView(_entries, filter: f)).toSet();
      expect(union, libraryView(_entries).toSet());
    });
    test('leere Kategorien liefern leere Listen', () {
      final onlyPlaylists = _entries.whereType<PlaylistLibraryEntry>().toList();
      expect(libraryView(onlyPlaylists, filter: LibraryFilter.albums), isEmpty);
      expect(libraryView(onlyPlaylists, filter: LibraryFilter.artists), isEmpty);
      expect(libraryCounts(onlyPlaylists), {LibraryFilter.playlists: 1, LibraryFilter.albums: 0, LibraryFilter.artists: 0});
      expect(libraryView(const []), isEmpty);
    });
    test('Sortierung nach Name', () {
      expect(libraryView(_entries, order: LibraryOrder.name).map((e) => e.name), ['Gefolgter Künstler', 'Gespeichertes Album', 'Meine Playlist']);
    });
  });

  testWidgets('Bibliothek öffnet ohne Filter; Filter zeigen nur ihre Kategorie und lassen sich abwählen', (t) async {
    await t.pumpWidget(_app(_entries));
    await t.pumpAndSettle();
    // Gesamtansicht: alles gemeinsam, kein Filter aktiv
    expect(find.text('Meine Playlist'), findsOneWidget);
    expect(find.text('Gespeichertes Album'), findsOneWidget);
    expect(find.text('Gefolgter Künstler'), findsOneWidget);
    expect(find.text('Lieblingssongs'), findsOneWidget);
    for (final f in LibraryFilter.values) {
      expect(_selected(t, f.name), isFalse);
    }

    // Alben
    await t.tap(_chip('albums'));
    await t.pumpAndSettle();
    expect(_selected(t, 'albums'), isTrue);
    expect(find.text('Gespeichertes Album'), findsOneWidget);
    expect(find.text('Meine Playlist'), findsNothing);
    expect(find.text('Gefolgter Künstler'), findsNothing);
    expect(find.text('Lieblingssongs'), findsNothing);

    // Künstler (direkt umschalten)
    await t.tap(_chip('artists'));
    await t.pumpAndSettle();
    expect(_selected(t, 'artists'), isTrue);
    expect(_selected(t, 'albums'), isFalse);
    expect(find.text('Gefolgter Künstler'), findsOneWidget);
    expect(find.text('Gespeichertes Album'), findsNothing);

    // Playlists inkl. fester Einträge
    await t.tap(_chip('playlists'));
    await t.pumpAndSettle();
    expect(find.text('Meine Playlist'), findsOneWidget);
    expect(find.text('Lieblingssongs'), findsOneWidget);
    expect(find.text('Gefolgter Künstler'), findsNothing);

    // Aktiven Filter erneut antippen → Gesamtansicht
    await t.tap(_chip('playlists'));
    await t.pumpAndSettle();
    expect(_selected(t, 'playlists'), isFalse);
    expect(find.text('Gespeichertes Album'), findsOneWidget);
    expect(find.text('Gefolgter Künstler'), findsOneWidget);

    // Über das ×-Symbol abwählen
    await t.tap(_chip('artists'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Filter aufheben').first);
    await t.pumpAndSettle();
    expect(find.text('Meine Playlist'), findsOneWidget);
    expect(_selected(t, 'artists'), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('leere Kategorien zeigen einen passenden Hinweis', (t) async {
    await t.pumpWidget(_app(_entries.whereType<PlaylistLibraryEntry>().toList()));
    await t.pumpAndSettle();
    await t.tap(_chip('albums'));
    await t.pumpAndSettle();
    expect(find.text('Noch keine Alben gespeichert'), findsOneWidget);
    await t.tap(_chip('artists'));
    await t.pumpAndSettle();
    expect(find.text('Du folgst noch keinen Künstlern'), findsOneWidget);

    await t.pumpWidget(const SizedBox()); // neuer Bildschirm → wieder ohne Filter
    await t.pumpWidget(_app(const []));
    await t.pumpAndSettle();
    expect(find.text('Deine Bibliothek ist noch leer'), findsOneWidget);
    await t.tap(_chip('playlists'));
    await t.pumpAndSettle();
    expect(find.text('Noch keine eigenen Playlists'), findsOneWidget);
  });
}
