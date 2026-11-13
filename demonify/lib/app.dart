import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/theme.dart';
import 'features/admin/admin_screens.dart';
import 'features/admin/admin_upload_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/setup_screen.dart';
import 'features/catalog/artist_screen.dart';
import 'features/catalog/catalog_providers.dart';
import 'features/catalog/release_screen.dart';
import 'features/downloads/download_manager.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/home/home_screen.dart';
import 'features/library/library_screen.dart';
import 'features/player/equalizer/eq_controller.dart';
import 'features/player/equalizer/equalizer_screen.dart';
import 'features/player/player_widgets.dart';
import 'features/playlists/playlist_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'l10n/l10n.dart';

final _routerRefresh = ValueNotifier<int>(0);

final routerProvider = Provider<GoRouter>((ref) {
  ref.listen(authProvider, (_, _) => _routerRefresh.value++);
  final rootKey = GlobalKey<NavigatorState>();
  final shellKey = GlobalKey<NavigatorState>();

  Page<void> fade(Widget child, GoRouterState st) => NoTransitionPage(key: st.pageKey, child: child);

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/home',
    refreshListenable: _routerRefresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      if (auth.isLoading && !auth.hasValue) return loc == '/splash' ? null : '/splash';
      final session = auth.value;
      if (session == null) return loc == '/login' ? null : '/login';
      // Ersteinrichtung (Startpasswort, E-Mail-Bestätigung) vor allem anderen
      if (session.needsSetup) return loc == '/setup' ? null : '/setup';
      if (loc == '/login' || loc == '/splash' || loc == '/setup') return '/home';
      // Sichtbarkeit ist kein Schutz – die API prüft jede Berechtigung serverseitig
      if (loc.startsWith('/admin') && !session.user.isAdmin) return '/home';
      rememberTab(loc);
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const _Splash()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/setup', builder: (c, s) => const SetupScreen()),
      GoRoute(
        path: '/player',
        parentNavigatorKey: rootKey,
        pageBuilder: (c, s) => CustomTransitionPage(
          key: s.pageKey,
          child: const PlayerScreen(),
          transitionsBuilder: (c, a, _, child) => SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic)).animate(a),
            child: child,
          ),
        ),
      ),
      GoRoute(path: '/queue', parentNavigatorKey: rootKey, builder: (c, s) => const QueueScreen()),
      ShellRoute(
        navigatorKey: shellKey,
        builder: (c, s, child) => AppShell(location: s.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', pageBuilder: (c, s) => fade(const HomeScreen(), s)),
          GoRoute(path: '/search', pageBuilder: (c, s) => fade(const SearchScreen(), s)),
          GoRoute(path: '/library', pageBuilder: (c, s) => fade(const LibraryScreen(), s)),
          GoRoute(path: '/catalog', builder: (c, s) => const CatalogBrowseScreen()),
          GoRoute(path: '/release/:id', builder: (c, s) => ReleaseScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/artist/:id', builder: (c, s) => ArtistScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/playlist/:id', builder: (c, s) => PlaylistScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/favorites', builder: (c, s) => const FavoritesScreen()),
          GoRoute(path: '/downloads', builder: (c, s) => const DownloadsScreen()),
          GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
          GoRoute(path: '/settings/equalizer', builder: (c, s) => const EqualizerScreen()),
          GoRoute(path: '/admin', pageBuilder: (c, s) => fade(const AdminHomeScreen(), s)),
          GoRoute(path: '/admin/artists', builder: (c, s) => const AdminArtistsScreen()),
          GoRoute(path: '/admin/upload', builder: (c, s) => const AdminUploadScreen()),
          GoRoute(path: '/admin/releases', builder: (c, s) => const AdminReleasesScreen()),
          GoRoute(path: '/admin/releases/:id', builder: (c, s) => AdminReleaseDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/admin/users', builder: (c, s) => const AdminUsersScreen()),
          GoRoute(path: '/admin/jobs', builder: (c, s) => const AdminJobsScreen()),
        ],
      ),
    ],
  );
});

class DemonifyApp extends ConsumerWidget {
  const DemonifyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Dauerhafte Dienste aktiv halten (Downloads, Equalizer, Einstellungen, Favoriten)
    ref.watch(downloadsProvider);
    ref.watch(equalizerProvider);
    ref.watch(settingsProvider);
    ref.watch(favoritesProvider);
    return MaterialApp.router(
      title: 'Demonify',
      debugShowCheckedModeBanner: false,
      theme: buildDemonifyTheme(),
      darkTheme: buildDemonifyTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      locale: const Locale('de'),
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.asset('assets/icon/app_icon.png', width: 96, height: 96)),
        ),
      );
}
