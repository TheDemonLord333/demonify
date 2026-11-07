import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'features/player/audio_handler.dart';
import 'features/player/player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Keine automatische Wiederholung fehlgeschlagener Provider: Fehler werden sichtbar
  // angezeigt und können gezielt erneut versucht werden.
  final container = ProviderContainer(retry: (_, _) => null);

  // Zentraler Player + Systemintegration (Hintergrundwiedergabe, Sperrbildschirm, Bluetooth)
  final player = container.read(playerProvider);
  await player.initSession();
  await initAudioService(container);

  runApp(UncontrolledProviderScope(container: container, child: const DemonifyApp()));
}
