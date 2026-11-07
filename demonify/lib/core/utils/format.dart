String formatDuration(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final str = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${str.replaceAll('.', ',')} ${units[i]}';
}

/// Lange Gesamtdauer, z. B. "1 Std. 12 Min."
String formatLongDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '$h Std. $m Min.';
  return '${d.inMinutes} Min.';
}
