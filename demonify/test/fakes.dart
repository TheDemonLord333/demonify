import 'dart:async';
import 'dart:io';

import 'package:demonify/features/catalog/models.dart';
import 'package:demonify/features/downloads/download_manager.dart';
import 'package:demonify/features/downloads/download_models.dart';
import 'package:demonify/features/player/audio_engine.dart';

Track fakeTrack(String id, {String title = 'Song', bool available = true, String? cover}) => Track(
      id: id,
      title: '$title $id',
      discNumber: 1,
      trackNumber: 1,
      durationMs: 180000,
      available: available,
      coverImageId: cover,
      hasOwnCover: cover != null,
      artists: const [TrackArtist(id: 'a1', name: 'Künstler', featured: false)],
      release: const ReleaseRef(id: 'r1', title: 'Album', type: ReleaseType.album, coverImageId: 'relcover', albumArtist: ArtistRef(id: 'a1', name: 'Künstler')),
    );

class FakeEngine implements AudioEngine {
  final opened = <String>[];
  String filter = '';
  double gainDb = 0;
  bool isPlaying = false;
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();

  void complete() => _completed.add(true);

  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get completed => _completed.stream;
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<Duration> get buffer => const Stream.empty();
  @override
  Stream<String> get errors => const Stream.empty();

  @override
  Future<void> open(String uri, {required bool play, Duration start = Duration.zero}) async {
    opened.add(uri);
    isPlaying = play;
    _playing.add(play);
  }

  @override
  Future<void> play() async => _playing.add(isPlaying = true);
  @override
  Future<void> pause() async => _playing.add(isPlaying = false);
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async => _playing.add(isPlaying = false);
  @override
  Future<void> setGainDb(double db) async => gainDb = db;
  @override
  Future<bool> setAudioFilter(String f) async {
    filter = f;
    return true;
  }

  @override
  Future<void> dispose() async {}
}

/// Download-Verwaltung mit festen lokalen Dateien (ohne Dateisystem-Index)
class FakeDownloads extends DownloadManager {
  FakeDownloads(this.files);
  final Map<String, File> files;
  @override
  DownloadsState build() => const DownloadsState(loaded: true);
  @override
  File? localFile(String trackId) => files[trackId];
}
