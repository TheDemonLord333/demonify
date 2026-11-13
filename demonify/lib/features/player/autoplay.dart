import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../auth/auth_controller.dart';
import '../catalog/models.dart';
import '../downloads/download_manager.dart';

/// Liefert Kandidaten für Autoplay (ähnliche Titel), in bevorzugter Reihenfolge.
abstract class AutoplaySource {
  Future<List<Track>> candidates(Track finished, {List<String> recentIds = const []});
}

/// Austauschbar für Tests
final autoplaySourceProvider = Provider<AutoplaySource>((ref) => CatalogAutoplaySource(ref));

/// Online: Server wählt zufällig nach Genre und Künstler (nur verfügbare Titel).
/// Offline: nur heruntergeladene Titel mit gleichem Genre oder gemeinsamem Künstler.
class CatalogAutoplaySource implements AutoplaySource {
  CatalogAutoplaySource(this._ref);
  final Ref _ref;
  final _random = Random();

  @override
  Future<List<Track>> candidates(Track finished, {List<String> recentIds = const []}) async {
    final api = _ref.read(apiProvider);
    if (api != null && _ref.read(authProvider).value?.offline != true) {
      try {
        List<Track> parse(Map<String, dynamic> r) =>
            (r['items'] as List).map((e) => Track.fromJson((e as Map).cast<String, dynamic>())).toList();
        final recent = recentIds.where((id) => id != finished.id).take(100).join(',');
        var items = parse(await api.get('tracks/${finished.id}/similar', query: {'limit': 20, if (recent.isNotEmpty) 'exclude': recent}));
        // Alles Ähnliche lief schon → Wiederholungen erlauben, nur nicht den gerade beendeten Titel
        if (items.isEmpty && recent.isNotEmpty) items = parse(await api.get('tracks/${finished.id}/similar', query: {'limit': 20}));
        return items;
      } on ApiException catch (e) {
        if (!e.isNetwork) return const [];
      }
    }
    return _offline(finished, recentIds);
  }

  List<Track> _offline(Track finished, List<String> recentIds) {
    final dl = _ref.read(downloadsProvider);
    final genre = finished.genre?.trim().toLowerCase();
    final artistIds = {...finished.artists.map((a) => a.id), finished.release.albumArtist.id};
    int? tier(Track t) {
      final g = genre != null && genre.isNotEmpty && t.genre?.trim().toLowerCase() == genre;
      final a = t.artists.any((x) => artistIds.contains(x.id)) || artistIds.contains(t.release.albumArtist.id);
      return g && a ? 1 : g ? 2 : a ? 3 : null;
    }

    final pool = dl.items.values.map((i) => i.track).where((t) => t.id != finished.id && dl.isDownloaded(t.id) && tier(t) != null).toList()
      ..shuffle(_random);
    final fresh = pool.where((t) => !recentIds.contains(t.id)).toList();
    final list = fresh.isNotEmpty ? fresh : pool;
    list.sort((a, b) => tier(a)!.compareTo(tier(b)!));
    return list;
  }
}
