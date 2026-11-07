import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import '../player/player_widgets.dart';

class _Dest {
  const _Dest(this.path, this.icon, this.selectedIcon, this.label);
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Responsives Grundlayout: untere Navigation + Mini-Player auf Smartphones,
/// Seitenleiste + Playerleiste auf großen Bildschirmen. „Verwaltung“ nur für Administratoren.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final session = ref.watch(authProvider).value;
    final isAdmin = session?.user.isAdmin ?? false;
    final dests = [
      _Dest('/home', Icons.home_outlined, Icons.home_rounded, s.navHome),
      _Dest('/search', Icons.search_outlined, Icons.search_rounded, s.navSearch),
      _Dest('/library', Icons.library_music_outlined, Icons.library_music_rounded, s.navLibrary),
      if (isAdmin) _Dest('/admin', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings_rounded, s.navAdmin),
    ];
    final index = _indexFor(location, dests);
    void go(int i) => context.go(dests[i].path);

    final offlineBanner = session?.offline == true
        ? Material(
            color: DColors.warning.withValues(alpha: 0.18),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DSpacing.l, vertical: DSpacing.xs),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 18, color: DColors.warning),
                    const SizedBox(width: DSpacing.s),
                    Expanded(child: Text(s.offlineBanner, style: const TextStyle(fontSize: 13))),
                    TextButton(onPressed: () => ref.read(authProvider.notifier).reconnect(), child: Text(s.reconnect)),
                  ],
                ),
              ),
            ),
          )
        : null;

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= DBreakpoints.wide) {
        final extended = c.maxWidth >= DBreakpoints.extraWide;
        return Scaffold(
          body: Column(
            children: [
              ?offlineBanner,
              Expanded(
                child: Row(
                  children: [
                    SafeArea(
                      right: false,
                      child: NavigationRail(
                        extended: extended,
                        minExtendedWidth: 232,
                        selectedIndex: index,
                        onDestinationSelected: go,
                        leading: Padding(
                          padding: const EdgeInsets.symmetric(vertical: DSpacing.l),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/icon/app_icon.png', width: 40, height: 40)),
                              if (extended) ...[const SizedBox(width: DSpacing.m), Text('Demonify', style: Theme.of(context).textTheme.titleLarge)],
                            ],
                          ),
                        ),
                        trailing: Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: DSpacing.l),
                              child: IconButton(tooltip: s.navSettings, icon: const Icon(Icons.settings_rounded), onPressed: () => context.push('/settings')),
                            ),
                          ),
                        ),
                        destinations: [
                          for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(DRadius.l)),
                        child: ColoredBox(color: DColors.background, child: child),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: const WidePlayerBar(),
        );
      }
      return Scaffold(
        body: Column(children: [?offlineBanner, Expanded(child: child)]),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            NavigationBar(
              selectedIndex: index,
              onDestinationSelected: go,
              height: 64,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final d in dests) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
              ],
            ),
          ],
        ),
      );
    });
  }

  int _indexFor(String loc, List<_Dest> dests) {
    for (var i = 0; i < dests.length; i++) {
      if (loc.startsWith(dests[i].path)) return i;
    }
    // Detailseiten: zuletzt aktiven Bereich beibehalten
    return _lastIndex.clamp(0, dests.length - 1);
  }
}

int _lastIndex = 0;

/// Merkt sich den zuletzt gewählten Hauptbereich für Detailseiten
void rememberTab(String location) {
  if (location.startsWith('/home')) _lastIndex = 0;
  if (location.startsWith('/search')) _lastIndex = 1;
  if (location.startsWith('/library')) _lastIndex = 2;
  if (location.startsWith('/admin')) _lastIndex = 3;
}
