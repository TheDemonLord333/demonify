import '../catalog/models.dart';

/// Lokales Download-Modell – bewusst getrennt vom Servermodell, damit der Offline-Bestand
/// unabhängig von späteren API-Änderungen lesbar bleibt.
enum DownloadStatus { queued, downloading, done, failed }

class DownloadItem {
  DownloadItem({
    required this.track,
    required this.status,
    this.progress = 0,
    this.bytes = 0,
    this.fileName,
    this.quality,
    this.error,
    this.explicit = false,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  final Track track;
  final DownloadStatus status;
  final double progress;
  final int bytes;

  /// Dateiname relativ zum Download-Ordner des Benutzers
  final String? fileName;
  final String? quality;
  final String? error;

  /// Einzeln heruntergeladen (nicht nur als Teil einer Veröffentlichung/Playlist)
  final bool explicit;
  final DateTime addedAt;

  DownloadItem copyWith({DownloadStatus? status, double? progress, int? bytes, String? fileName, String? quality, String? error, bool? explicit, Track? track}) =>
      DownloadItem(
        track: track ?? this.track,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        bytes: bytes ?? this.bytes,
        fileName: fileName ?? this.fileName,
        quality: quality ?? this.quality,
        error: error,
        explicit: explicit ?? this.explicit,
        addedAt: addedAt,
      );

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'status': status == DownloadStatus.done ? 'done' : 'pending',
        'bytes': bytes,
        'fileName': fileName,
        'quality': quality,
        'explicit': explicit,
        'addedAt': addedAt.toIso8601String(),
      };

  factory DownloadItem.fromJson(Map<String, dynamic> j) => DownloadItem(
        track: Track.fromJson((j['track'] as Map).cast<String, dynamic>()),
        // Unterbrochene Downloads werden nach Neustart erneut eingereiht
        status: j['status'] == 'done' ? DownloadStatus.done : DownloadStatus.queued,
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        fileName: j['fileName'] as String?,
        quality: j['quality'] as String?,
        explicit: j['explicit'] as bool? ?? false,
        progress: j['status'] == 'done' ? 1 : 0,
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? ''),
      );
}

class DownloadCollection {
  DownloadCollection({required this.kind, required this.id, required this.title, this.subtitle, this.coverImageId, required this.trackIds});
  /// 'release' oder 'playlist'
  final String kind;
  final String id;
  final String title;
  final String? subtitle;
  final String? coverImageId;
  final List<String> trackIds;

  String get key => '$kind:$id';

  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'title': title, 'subtitle': subtitle, 'coverImageId': coverImageId, 'trackIds': trackIds};
  factory DownloadCollection.fromJson(Map<String, dynamic> j) => DownloadCollection(
        kind: j['kind'] as String,
        id: j['id'] as String,
        title: j['title'] as String,
        subtitle: j['subtitle'] as String?,
        coverImageId: j['coverImageId'] as String?,
        trackIds: ((j['trackIds'] as List?) ?? const []).cast<String>(),
      );
}

class DownloadsState {
  const DownloadsState({this.items = const {}, this.collections = const {}, this.loaded = false});
  final Map<String, DownloadItem> items;
  final Map<String, DownloadCollection> collections;
  final bool loaded;

  int get totalBytes => items.values.fold(0, (s, i) => s + (i.status == DownloadStatus.done ? i.bytes : 0));
  bool isDownloaded(String trackId) => items[trackId]?.status == DownloadStatus.done;
  DownloadItem? item(String trackId) => items[trackId];
  bool hasCollection(String kind, String id) => collections.containsKey('$kind:$id');

  /// Fortschritt einer Sammlung (0..1) oder null, wenn nicht heruntergeladen
  double? collectionProgress(String kind, String id) {
    final c = collections['$kind:$id'];
    if (c == null || c.trackIds.isEmpty) return null;
    final p = c.trackIds.fold<double>(0, (s, t) => s + (items[t]?.status == DownloadStatus.done ? 1 : (items[t]?.progress ?? 0)));
    return p / c.trackIds.length;
  }

  DownloadsState copyWith({Map<String, DownloadItem>? items, Map<String, DownloadCollection>? collections, bool? loaded}) =>
      DownloadsState(items: items ?? this.items, collections: collections ?? this.collections, loaded: loaded ?? this.loaded);
}
