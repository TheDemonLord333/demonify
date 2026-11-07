import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/cover_cache.dart';
import '../../core/storage/providers.dart';
import '../catalog/models.dart';
import 'player_controller.dart';
import 'player_providers.dart';
import 'queue_model.dart';

/// Brücke zwischen dem zentralen Player und der System-Mediensteuerung
/// (Android MediaSession/Benachrichtigung, iOS Sperrbildschirm/Control Center,
/// Bluetooth- und Headset-Tasten). Cover: individuelles Songcover, sonst Veröffentlichungscover.
class DemonifyAudioHandler extends BaseAudioHandler with SeekHandler {
  DemonifyAudioHandler(this._container) {
    _player.stateStream.listen(_onState);
    _player.positionStream.listen((p) {
      // Systemposition nur bei größeren Sprüngen aktualisieren (System extrapoliert selbst)
      final last = playbackState.value.updatePosition;
      if ((p.position - last).abs() > const Duration(seconds: 2) && !_player.state.playing) {
        _broadcast(_player.state, position: p.position);
      }
    });
  }

  final ProviderContainer _container;
  PlayerController get _player => _container.read(playerProvider);
  String? _currentArtFor;

  void _onState(PlayerSnapshot s) {
    _broadcast(s);
    final t = s.current;
    if (t == null) {
      mediaItem.add(null);
      return;
    }
    final item = _mediaItem(t, null);
    if (mediaItem.value?.id != t.id || mediaItem.value?.duration != item.duration) {
      mediaItem.add(item);
      unawaited(_loadArt(t));
    }
    queue.add(s.queue.map((e) => _mediaItem(e.track, null)).toList());
  }

  MediaItem _mediaItem(Track t, Uri? art) => MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artistLine,
        album: t.release.title,
        duration: t.duration,
        artUri: art,
      );

  Future<void> _loadArt(Track t) async {
    final id = t.coverImageId;
    if (id == null || _currentArtFor == '${t.id}:$id') return;
    _currentArtFor = '${t.id}:$id';
    final cache = _container.read(coverCacheProvider);
    final file = await cache?.get(id, CoverSize.large);
    if (file == null || mediaItem.value?.id != t.id) return;
    mediaItem.add(_mediaItem(t, Uri.file(file.path)));
  }

  void _broadcast(PlayerSnapshot s, {Duration? position}) {
    final processing = s.loading
        ? AudioProcessingState.loading
        : s.buffering
            ? AudioProcessingState.buffering
            : s.error != null && !s.playing
                ? AudioProcessingState.error
                : s.current == null
                    ? AudioProcessingState.idle
                    : AudioProcessingState.ready;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        s.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward, MediaAction.setShuffleMode, MediaAction.setRepeatMode},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processing,
      playing: s.playing,
      updatePosition: position ?? _player.positionInfo.position,
      bufferedPosition: _player.positionInfo.buffered,
      speed: 1,
      queueIndex: s.index < 0 ? null : s.index,
      shuffleMode: s.shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      repeatMode: switch (s.repeat) {
        RepeatMode.off => AudioServiceRepeatMode.none,
        RepeatMode.all => AudioServiceRepeatMode.all,
        RepeatMode.one => AudioServiceRepeatMode.one,
      },
      errorMessage: s.error,
    ));
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcast(_player.state, position: position);
  }

  @override
  Future<void> skipToNext() => _player.next();
  @override
  Future<void> skipToPrevious() => _player.previous();
  @override
  Future<void> skipToQueueItem(int index) => _player.jumpTo(index);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async => _player.setShuffle(shuffleMode != AudioServiceShuffleMode.none);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async => _player.setRepeat(switch (repeatMode) {
        AudioServiceRepeatMode.none => RepeatMode.off,
        AudioServiceRepeatMode.one => RepeatMode.one,
        _ => RepeatMode.all,
      });

  /// Android: App aus den „Zuletzt verwendet“ entfernt → bei Pause Dienst beenden
  @override
  Future<void> onTaskRemoved() async {
    if (!_player.state.playing) await stop();
  }
}

/// Initialisiert die Systemintegration. Auf Plattformen ohne audio_service-Unterstützung
/// (z. B. künftiges Windows) läuft der Player ohne Systemsteuerung weiter.
Future<void> initAudioService(ProviderContainer container) async {
  try {
    await AudioService.init(
      builder: () => DemonifyAudioHandler(container),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'me.thedemonlord333.demonify.playback',
        androidNotificationChannelName: 'Wiedergabe',
        androidNotificationChannelDescription: 'Steuerung der Musikwiedergabe',
        androidNotificationIcon: 'drawable/ic_stat_demonify',
        androidStopForegroundOnPause: true,
        androidNotificationOngoing: false,
        notificationColor: null,
      ),
    );
  } catch (_) {
    // keine Systemmediensteuerung verfügbar
  }
}
