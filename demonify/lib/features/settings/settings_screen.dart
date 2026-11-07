import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import '../downloads/download_manager.dart';
import '../player/equalizer/eq_controller.dart';
import '../player/player_providers.dart';
import 'settings_controller.dart';

final packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

String qualityLabel(BuildContext c, AudioQuality q) => switch (q) {
      AudioQuality.original => c.s.qualityOriginal,
      AudioQuality.high => c.s.qualityHigh,
      AudioQuality.normal => c.s.qualityNormal,
      AudioQuality.low => c.s.qualityLow,
    };

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final session = ref.watch(authProvider).value;
    final settings = ref.watch(settingsProvider);
    final dl = ref.watch(downloadsProvider);
    final eq = ref.watch(equalizerProvider);
    final info = ref.watch(packageInfoProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(s.navSettings)),
      body: ListView(
        children: [
          _Header(s.settingsAccount),
          ListTile(
            leading: const Icon(Icons.account_circle_rounded),
            title: Text(session?.user.label ?? '–'),
            subtitle: Text(session?.user.isAdmin == true ? s.roleAdmin : s.roleUser),
          ),
          ListTile(
            leading: const Icon(Icons.dns_rounded),
            title: Text(s.serverAddress),
            subtitle: Text(session?.api.origin ?? '–'),
          ),
          if (session?.offline == true)
            ListTile(
              leading: const Icon(Icons.cloud_off_rounded, color: DColors.warning),
              title: Text(s.offlineBanner),
              trailing: TextButton(onPressed: () => ref.read(authProvider.notifier).reconnect(), child: Text(s.reconnect)),
            ),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: DColors.danger),
            title: Text(s.logout, style: const TextStyle(color: DColors.danger)),
            onTap: () => confirmLogout(context, ref),
          ),
          _Header(s.settingsPlayback),
          ListTile(
            leading: const Icon(Icons.wifi_rounded),
            title: Text(s.streamingQuality),
            subtitle: Text(qualityLabel(context, settings.streamingQuality)),
            onTap: () => _pickQuality(context, ref, settings.streamingQuality, (q) => settings.copyWith(streamingQuality: q)),
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: Text(s.downloadQuality),
            subtitle: Text(qualityLabel(context, settings.downloadQuality)),
            onTap: () => _pickQuality(context, ref, settings.downloadQuality, (q) => settings.copyWith(downloadQuality: q)),
          ),
          _Header(s.settingsSound),
          ListTile(
            leading: const Icon(Icons.equalizer_rounded),
            title: Text(s.equalizer),
            subtitle: Text(eq.enabled ? s.on : s.off),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/settings/equalizer'),
          ),
          _Header(s.downloads),
          ListTile(
            leading: const Icon(Icons.download_done_rounded),
            title: Text(s.manageDownloads),
            subtitle: Text(s.storageUsed(formatBytes(dl.totalBytes))),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/downloads'),
          ),
          _Header(s.settingsAbout),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(s.appVersion),
            subtitle: Text(info == null ? '…' : '${info.version} (${info.buildNumber})'),
          ),
          const SizedBox(height: DSpacing.xxl),
        ],
      ),
    );
  }

  Future<void> _pickQuality(BuildContext context, WidgetRef ref, AudioQuality current, UserSettings Function(AudioQuality) apply) async {
    final q = await showModalBottomSheet<AudioQuality>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (c) => RadioGroup<AudioQuality>(
        groupValue: current,
        onChanged: (v) => Navigator.pop(c, v),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final q in AudioQuality.values) RadioListTile<AudioQuality>(value: q, title: Text(qualityLabel(c, q))),
            Padding(padding: const EdgeInsets.all(16), child: Text(c.s.qualityHint, style: const TextStyle(color: DColors.textMuted))),
          ],
        ),
      ),
    );
    if (q != null) await ref.read(settingsProvider.notifier).update(apply(q));
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(DSpacing.l, DSpacing.xl, DSpacing.l, DSpacing.s),
        child: Text(text, style: const TextStyle(color: DColors.primaryHover, fontWeight: FontWeight.w700)),
      );
}

/// Abmelden mit Angebot, die Downloads dieses Benutzers zu entfernen
Future<void> confirmLogout(BuildContext context, WidgetRef ref) async {
  final s = context.s;
  var deleteDownloads = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(s.logoutTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.logoutMessage),
            const SizedBox(height: DSpacing.m),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: deleteDownloads,
              onChanged: (v) => setState(() => deleteDownloads = v ?? false),
              title: Text(s.logoutDeleteDownloads),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.logout)),
        ],
      ),
    ),
  );
  if (ok != true) return;
  await ref.read(playerProvider).clear();
  if (deleteDownloads) await ref.read(downloadsProvider.notifier).removeAll();
  await ref.read(authProvider.notifier).logout();
}
