import 'dart:async';
import 'dart:math' as math;

import 'package:media_kit/media_kit.dart';

/// Abstraktion der Audioengine (für Tests austauschbar).
abstract class AudioEngine {
  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<bool> get completed;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<Duration> get buffer;
  Stream<String> get errors;

  Future<void> open(String uri, {required bool play, Duration start = Duration.zero});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();

  /// Lautstärke in dB (≤ 0) – für Vorverstärkung/Headroom und Ducking
  Future<void> setGainDb(double db);

  /// Audiofilterkette (FFmpeg/libavfilter); leer = aus. Liefert false, wenn nicht unterstützt.
  Future<bool> setAudioFilter(String filter);

  Future<void> dispose();
}

/// libmpv/FFmpeg-basierte Engine über media_kit (Android, iOS, Windows, macOS, Linux).
///
/// Warum media_kit: eine Engine für alle Zielplattformen inkl. späterem Windows, Wiedergabe
/// aller Bibliotheksformate (FLAC/Ogg auch auf iOS), HTTP-Range-Seeking und – entscheidend –
/// ein echter, plattformübergreifender Equalizer über den FFmpeg-Filter "equalizer", der in den
/// media_kit-Audiobuilds für Android und iOS ausdrücklich enthalten ist.
class MediaKitEngine implements AudioEngine {
  MediaKitEngine()
      : _player = Player(
          configuration: const PlayerConfiguration(
            title: 'Demonify',
            // Großzügiger Puffer für mobile Netze
            bufferSize: 32 * 1024 * 1024,
          ),
        );

  final Player _player;

  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<bool> get buffering => _player.stream.buffering;
  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<Duration> get buffer => _player.stream.buffer;
  @override
  Stream<String> get errors => _player.stream.error;

  NativePlayer? get _native => _player.platform is NativePlayer ? _player.platform as NativePlayer : null;

  @override
  Future<void> open(String uri, {required bool play, Duration start = Duration.zero}) async {
    await _player.open(Media(uri, start: start > Duration.zero ? start : null), play: play);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> setGainDb(double db) {
    // mpv-Lautstärke ist kubisch: Verstärkung = (vol/100)^3 → vol = 100 · 10^(dB/60)
    final vol = (100 * math.pow(10, db / 60)).clamp(0.0, 100.0).toDouble();
    return _player.setVolume(vol);
  }

  @override
  Future<bool> setAudioFilter(String filter) async {
    final native = _native;
    if (native == null) return false;
    try {
      await native.setProperty('af', filter);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dispose() => _player.dispose();
}
