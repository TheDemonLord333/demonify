import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Benutzergebundene Verzeichnisse im privaten App-Speicher.
/// Jeder angemeldete Benutzer erhält einen eigenen Ordner; die App greift nur auf den
/// Ordner des aktuell angemeldeten Benutzers zu.
class UserPaths {
  UserPaths._(this.userId, this.downloads, this.coverCache);

  final String userId;
  final Directory downloads;
  final Directory coverCache;

  Directory get audioDir => Directory(p.join(downloads.path, 'audio'));
  Directory get coverDir => Directory(p.join(downloads.path, 'covers'));
  File get indexFile => File(p.join(downloads.path, 'index.json'));

  static Future<UserPaths> forUser(String userId) async {
    // Application Support ist privat (kein Zugriff für andere Apps, nicht im Dateimanager sichtbar)
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    final safe = userId.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '');
    final dl = Directory(p.join(support.path, 'users', safe, 'downloads'));
    final cc = Directory(p.join(cache.path, 'users', safe, 'covers'));
    await dl.create(recursive: true);
    await cc.create(recursive: true);
    await Directory(p.join(dl.path, 'audio')).create(recursive: true);
    await Directory(p.join(dl.path, 'covers')).create(recursive: true);
    return UserPaths._(safe, dl, cc);
  }
}
