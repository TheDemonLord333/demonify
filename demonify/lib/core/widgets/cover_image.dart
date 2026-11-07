import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/cover_cache.dart';
import '../storage/providers.dart';
import '../theme/tokens.dart';

/// Cover mit einheitlichem Demonify-Platzhalter. Lädt authentifiziert über den
/// benutzergebundenen Cover-Cache und nutzt offline gespeicherte Cover für Downloads.
class CoverImage extends ConsumerStatefulWidget {
  const CoverImage({
    super.key,
    required this.imageId,
    this.size = 48,
    this.radius = DRadius.s,
    this.circle = false,
    this.coverSize,
    this.semanticLabel,
    this.icon = Icons.music_note_rounded,
  });

  final String? imageId;
  final double size;
  final double radius;
  final bool circle;
  final CoverSize? coverSize;
  final String? semanticLabel;
  final IconData icon;

  @override
  ConsumerState<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends ConsumerState<CoverImage> {
  File? _file;
  String? _loadedKey;

  CoverSize get _size => widget.coverSize ?? (widget.size <= 64 ? CoverSize.thumb : widget.size <= 200 ? CoverSize.small : CoverSize.medium);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant CoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId || oldWidget.size != widget.size) _load();
  }

  void _load() {
    final id = widget.imageId;
    final cache = ref.read(coverCacheProvider);
    final key = '$id-${_size.name}';
    if (id == null || cache == null) {
      if (_file != null) setState(() => _file = null);
      _loadedKey = null;
      return;
    }
    if (_loadedKey == key && _file != null) return;
    _loadedKey = key;
    final sync = cache.localSync(id, _size);
    if (sync != null) {
      _file = sync;
      return;
    }
    _file = null;
    cache.get(id, _size).then((f) {
      if (mounted && _loadedKey == key && f != null) setState(() => _file = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Neu laden, sobald der Cache (z. B. nach Anmeldung) verfügbar ist
    ref.listen(coverCacheProvider, (_, _) => _load());
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final placeholder = CoverPlaceholder(size: widget.size, icon: widget.icon);
    final child = _file == null
        ? placeholder
        : Image.file(
            _file!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            cacheWidth: (widget.size * dpr).round(),
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder,
            frameBuilder: (context, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 220), child: child),
          );
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: ClipRRect(
        borderRadius: widget.circle ? BorderRadius.circular(widget.size) : BorderRadius.circular(widget.radius),
        child: SizedBox(width: widget.size, height: widget.size, child: child),
      ),
    );
  }
}

class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({super.key, required this.size, this.icon = Icons.music_note_rounded});
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1748), Color(0xFF10101A)],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.42, color: DColors.primary.withValues(alpha: 0.75)),
    );
  }
}
