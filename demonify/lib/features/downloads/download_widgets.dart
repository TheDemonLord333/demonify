import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';

/// Download-Symbol mit Fortschrittsring (grün = vollständig offline verfügbar)
class CollectionDownloadButton extends StatelessWidget {
  const CollectionDownloadButton({super.key, required this.progress, required this.onDownload, required this.onRemove});
  final double? progress;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = progress;
    if (p == null) {
      return IconButton(tooltip: s.download, icon: const Icon(Icons.download_for_offline_outlined), onPressed: onDownload);
    }
    if (p >= 1) {
      return IconButton(
        tooltip: s.removeDownload,
        icon: const Icon(Icons.download_for_offline_rounded, color: DColors.secondary),
        onPressed: () => _confirmRemove(context),
      );
    }
    return IconButton(
      tooltip: s.downloading,
      onPressed: () => _confirmRemove(context),
      icon: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(value: p <= 0 ? null : p, strokeWidth: 2.5, color: DColors.secondary, backgroundColor: DColors.surface3),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final s = context.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.removeDownload),
        content: Text(s.removeDownloadConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.delete)),
        ],
      ),
    );
    if (ok == true) onRemove();
  }
}
