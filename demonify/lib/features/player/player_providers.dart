import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'audio_engine.dart';
import 'player_controller.dart';

/// Austauschbar für Tests (ProviderScope overrides)
final audioEngineProvider = Provider<AudioEngine>((ref) => MediaKitEngine());

/// Der Player lebt für die gesamte App-Laufzeit (unabhängig von Navigation und Screens).
final playerProvider = Provider<PlayerController>((ref) {
  final c = PlayerController(ref, ref.watch(audioEngineProvider));
  ref.listen(currentUserProvider.select((u) => u?.id), (_, id) => c.onUserChanged(id), fireImmediately: true);
  ref.onDispose(c.dispose);
  return c;
});

final playerStateProvider = StreamProvider<PlayerSnapshot>((ref) {
  final c = ref.watch(playerProvider);
  return c.stateStream;
});

final positionProvider = StreamProvider<PositionInfo>((ref) {
  final c = ref.watch(playerProvider);
  return c.positionStream;
});

/// Aktueller Zustand ohne Ladezustand (Startwert = aktueller Snapshot)
final playerSnapshotProvider = Provider<PlayerSnapshot>((ref) {
  return ref.watch(playerStateProvider).value ?? ref.watch(playerProvider).state;
});
