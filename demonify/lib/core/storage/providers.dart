import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import 'cover_cache.dart';
import 'user_paths.dart';

/// Verzeichnisse des aktuell angemeldeten Benutzers
final userPathsProvider = FutureProvider<UserPaths?>((ref) async {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  if (userId == null) return null;
  return UserPaths.forUser(userId);
});

final coverCacheProvider = Provider<CoverCache?>((ref) {
  final paths = ref.watch(userPathsProvider).value;
  if (paths == null) return null;
  return CoverCache(paths, ref.watch(apiProvider));
});
