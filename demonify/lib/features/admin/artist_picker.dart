import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/cover_image.dart';
import '../../l10n/l10n.dart';
import '../catalog/models.dart';
import 'admin_api.dart';

/// Künstlerauswahl mit Live-Vorschlägen ab dem ersten Buchstaben (ohne Enter),
/// Profilbild in den Vorschlägen und „Neuen Künstler erstellen“.
class ArtistPickerField extends ConsumerStatefulWidget {
  const ArtistPickerField({super.key, required this.onSelected, this.hint, this.excludeIds = const []});
  final ValueChanged<ArtistRef> onSelected;
  final String? hint;
  final List<String> excludeIds;

  @override
  ConsumerState<ArtistPickerField> createState() => _ArtistPickerFieldState();
}

class _ArtistPickerFieldState extends ConsumerState<ArtistPickerField> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  CancelToken? _cancel;
  int _seq = 0;
  List<ArtistRef> _items = [];
  ArtistRef? _exact;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _cancel?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _items = [];
        _exact = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      final admin = ref.read(adminApiProvider);
      if (admin == null) return;
      _cancel?.cancel();
      final cancel = _cancel = CancelToken();
      final seq = ++_seq;
      try {
        final r = await admin.suggestArtists(q.trim(), cancel: cancel);
        if (!mounted || seq != _seq) return;
        setState(() {
          _items = r.items.where((a) => !widget.excludeIds.contains(a.id)).toList();
          _exact = r.exact;
          _error = null;
        });
      } on ApiException catch (e) {
        if (e.code != 'CANCELLED' && mounted && seq == _seq) setState(() => _error = e.message);
      }
    });
  }

  void _select(ArtistRef a) {
    widget.onSelected(a);
    _ctrl.clear();
    setState(() => _items = []);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final q = _ctrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          onChanged: (v) {
            setState(() {});
            _onChanged(v);
          },
          autocorrect: false,
          decoration: InputDecoration(hintText: widget.hint ?? s.adminArtistSearch, prefixIcon: const Icon(Icons.person_search_rounded)),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: const TextStyle(color: DColors.danger))),
        if (q.isNotEmpty)
          Card(
            color: DColors.surface2,
            margin: const EdgeInsets.only(top: DSpacing.xs),
            child: Column(
              children: [
                for (final a in _items)
                  ListTile(
                    leading: CoverImage(imageId: a.imageId, size: 40, circle: true, icon: Icons.person_rounded),
                    title: Text(a.name),
                    trailing: _exact?.id == a.id ? const Icon(Icons.check_circle_rounded, color: DColors.secondary) : null,
                    onTap: () => _select(a),
                  ),
                if (_items.isEmpty) ListTile(dense: true, title: Text(s.adminNoArtistFound, style: const TextStyle(color: DColors.textMuted))),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded, color: DColors.primary),
                  title: Text(s.adminCreateArtistNamed(q), style: const TextStyle(color: DColors.primaryHover, fontWeight: FontWeight.w700)),
                  onTap: () async {
                    final created = await showCreateArtistDialog(context, q);
                    if (created != null) _select(created);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Anlegeformular: übernimmt den eingetippten Namen, prüft vor dem Speichern erneut
/// auf normalisierte Duplikate und behandelt gleichzeitige Anlage (409) verständlich.
Future<ArtistRef?> showCreateArtistDialog(BuildContext context, String initial) {
  return showDialog<ArtistRef>(context: context, builder: (c) => _CreateArtistDialog(initial: initial));
}

class _CreateArtistDialog extends ConsumerStatefulWidget {
  const _CreateArtistDialog({required this.initial});
  final String initial;
  @override
  ConsumerState<_CreateArtistDialog> createState() => _CreateArtistDialogState();
}

class _CreateArtistDialogState extends ConsumerState<_CreateArtistDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  Timer? _debounce;
  ArtistRef? _existing;
  List<ArtistRef> _similar = [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _check() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final name = _ctrl.text.trim();
      final admin = ref.read(adminApiProvider);
      if (name.isEmpty || admin == null) return;
      try {
        final r = await admin.checkArtist(name);
        if (mounted && _ctrl.text.trim() == name) {
          setState(() {
            _existing = r.exists ? r.artist : null;
            _similar = r.similar;
          });
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return AlertDialog(
      title: Text(s.adminCreateArtist),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLength: 200,
              decoration: InputDecoration(labelText: s.adminArtistName),
              onChanged: (_) => _check(),
            ),
            if (_existing != null)
              Card(
                color: DColors.danger.withValues(alpha: 0.14),
                child: ListTile(
                  title: Text(s.adminArtistExists(_existing!.name)),
                  trailing: TextButton(onPressed: () => Navigator.pop(context, _existing), child: Text(s.select)),
                ),
              ),
            if (_existing == null && _similar.isNotEmpty) ...[
              Text(s.adminSimilarArtists, style: const TextStyle(color: DColors.textMuted)),
              for (final a in _similar)
                ListTile(
                  dense: true,
                  leading: CoverImage(imageId: a.imageId, size: 32, circle: true, icon: Icons.person_rounded),
                  title: Text(a.name),
                  trailing: TextButton(onPressed: () => Navigator.pop(context, a), child: Text(s.select)),
                ),
            ],
            if (_error != null) Text(_error!, style: const TextStyle(color: DColors.danger)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(
          onPressed: _busy || _existing != null || _ctrl.text.trim().isEmpty
              ? null
              : () async {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    final a = await ref.read(adminApiProvider)!.createArtist(_ctrl.text.trim());
                    if (context.mounted) Navigator.pop(context, a);
                  } on ApiException catch (e) {
                    if (e.code == 'ARTIST_EXISTS') {
                      final details = e.details;
                      final artist = details is Map && details['artist'] is Map ? ArtistRef.fromJson((details['artist'] as Map).cast<String, dynamic>()) : null;
                      setState(() {
                        _existing = artist;
                        _error = e.message;
                      });
                    } else {
                      setState(() => _error = e.message);
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(s.adminCreate),
        ),
      ],
    );
  }
}
