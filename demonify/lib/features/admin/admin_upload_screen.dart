import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cover_image.dart';
import '../../core/widgets/media_widgets.dart';
import '../../l10n/l10n.dart';
import '../catalog/models.dart';
import 'admin_api.dart';
import 'artist_picker.dart';

enum _UpState { uploading, validating, ready, error, cancelled }

/// Upload eines Bildes oder einer Audiodatei inkl. Fortschritt, Abbruch und Wiederholung
class _FileUpload {
  _FileUpload(this.file, this.name, this.kind);
  final File file;
  final String name;
  final String kind;
  String? uploadId;
  double progress = 0;
  _UpState state = _UpState.uploading;
  String? error;
  Map<String, dynamic>? probe;
  CancelToken cancel = CancelToken();

  Future<void> run(AdminApi admin, VoidCallback onChange) async {
    cancel = CancelToken();
    state = _UpState.uploading;
    error = null;
    onChange();
    try {
      final r = await admin.upload(
        file,
        kind: kind,
        filename: name,
        cancel: cancel,
        resumeId: uploadId,
        onProgress: (p, phase) {
          progress = p;
          state = phase == 'validate' ? _UpState.validating : _UpState.uploading;
          onChange();
        },
      );
      uploadId = r.id;
      probe = r.probe;
      state = r.valid ? _UpState.ready : _UpState.error;
      error = r.error;
    } on DioException catch (e) {
      state = CancelToken.isCancel(e) ? _UpState.cancelled : _UpState.error;
      error = ApiException.fromDio(e).message;
    } on ApiException catch (e) {
      state = e.code == 'CANCELLED' ? _UpState.cancelled : _UpState.error;
      error = e.message;
    } catch (e) {
      state = _UpState.error;
      error = e.toString();
    }
    onChange();
  }
}

class _TrackDraft {
  _TrackDraft({required this.audio, required this.title, required this.number, required this.artists});
  final _FileUpload audio;
  String title;
  int disc = 1;
  int number;
  List<ArtistRef> artists;
  List<ArtistRef> features = [];
  String genre = '';
  _FileUpload? cover;
  final key = UniqueKey();
}

/// Upload-Panel: Künstler → Typ → Veröffentlichung → Metadaten & Cover → Audiodateien → Prüfen → Bestätigen.
/// Keine Serverpfade: der Server legt die Ordnerstruktur automatisch an.
class AdminUploadScreen extends ConsumerStatefulWidget {
  const AdminUploadScreen({super.key});
  @override
  ConsumerState<AdminUploadScreen> createState() => _AdminUploadScreenState();
}

class _AdminUploadScreenState extends ConsumerState<AdminUploadScreen> {
  int _step = 0;
  ArtistRef? _artist;
  ReleaseType _type = ReleaseType.album;
  bool _newRelease = true;
  Release? _existing;
  List<Release> _releases = [];
  final _title = TextEditingController();
  final _year = TextEditingController(text: '${DateTime.now().year}');
  final _genre = TextEditingController();
  _FileUpload? _cover;
  final List<_TrackDraft> _tracks = [];
  String _idempotencyKey = const Uuid().v4();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;

  AdminApi get _admin => ref.read(adminApiProvider)!;
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _title.dispose();
    _year.dispose();
    _genre.dispose();
    for (final t in _tracks) {
      t.audio.cancel.cancel();
    }
    super.dispose();
  }

  Future<void> _loadReleases() async {
    if (_artist == null) return;
    try {
      final list = await _admin.releases(artistId: _artist!.id, type: _type);
      setState(() => _releases = list);
    } catch (_) {
      setState(() => _releases = []);
    }
  }

  Future<File?> _pickImage() async {
    final r = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
    final path = r?.path;
    return path == null ? null : File(path);
  }

  Future<void> _pickAudio() async {
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'flac', 'm4a', 'aac', 'mp4', 'ogg', 'oga', 'opus', 'wav'],
    );
    final files = r.where((f) => f.path != null).toList()..sort((a, b) => a.name.compareTo(b.name));
    for (final f in files) {
      final up = _FileUpload(File(f.path!), f.name, 'AUDIO');
      final draft = _TrackDraft(
        audio: up,
        title: f.name.replaceAll(RegExp(r'\.[^.]+$'), '').replaceFirst(RegExp(r'^\d+\s*[-.]\s*'), ''),
        number: _tracks.length + 1,
        artists: _artist == null ? [] : [_artist!],
      );
      _tracks.add(draft);
      up.run(_admin, () {
        // Tags aus der Prüfung als Vorschlag übernehmen
        final tags = (up.probe?['tags'] as Map?)?.cast<String, dynamic>();
        if (tags != null && up.state == _UpState.ready) {
          if (tags['title'] is String && draft.title == f.name.replaceAll(RegExp(r'\.[^.]+$'), '').replaceFirst(RegExp(r'^\d+\s*[-.]\s*'), '')) {
            draft.title = tags['title'] as String;
          }
          if (tags['trackNumber'] is num) draft.number = (tags['trackNumber'] as num).toInt();
          if (tags['discNumber'] is num) draft.disc = (tags['discNumber'] as num).toInt();
          if (draft.genre.isEmpty && tags['genre'] is String) draft.genre = tags['genre'] as String;
        }
        _changed();
      });
    }
    setState(() {});
  }

  bool get _allReady =>
      _tracks.isNotEmpty &&
      _tracks.every((t) => t.audio.state == _UpState.ready && (t.cover == null || t.cover!.state == _UpState.ready)) &&
      (_cover == null || _cover!.state == _UpState.ready);

  List<String> _validation(S s) {
    final errs = <String>[];
    final seen = <String>{};
    for (var i = 0; i < _tracks.length; i++) {
      final t = _tracks[i];
      if (t.title.trim().isEmpty) errs.add(s.adminTrackTitleMissing(i + 1));
      if (t.artists.isEmpty) errs.add(s.adminTrackArtistMissing(i + 1));
      if (!seen.add('${t.disc}-${t.number}')) errs.add(s.adminTrackNumberDuplicate(t.disc, t.number));
    }
    return errs;
  }

  Future<void> _commit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await _admin.commit({
        'idempotencyKey': _idempotencyKey,
        'artistId': _artist!.id,
        'release': _newRelease
            ? {
                'mode': 'new',
                'title': _title.text.trim(),
                'type': _type.apiName,
                'year': int.tryParse(_year.text.trim()),
                'genre': _genre.text.trim().isEmpty ? null : _genre.text.trim(),
                'coverUploadId': _cover?.uploadId,
              }
            : {'mode': 'existing', 'releaseId': _existing!.id, 'coverUploadId': _cover?.uploadId},
        'tracks': [
          for (final t in _tracks)
            {
              'uploadId': t.audio.uploadId,
              'title': t.title.trim(),
              'discNumber': t.disc,
              'trackNumber': t.number,
              'artistIds': t.artists.map((a) => a.id).toList(),
              'featuredArtistIds': t.features.map((a) => a.id).toList(),
              'genre': t.genre.trim().isEmpty ? null : t.genre.trim(),
              'coverUploadId': t.cover?.uploadId,
            },
        ],
      });
      setState(() => _result = res['result'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      // Erneutes Bestätigen nutzt denselben Idempotenzschlüssel → keine doppelte Veröffentlichung
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final steps = [s.adminStepArtist, s.adminStepType, s.adminStepRelease, s.adminStepMeta, s.adminStepFiles, s.adminStepReview, s.adminStepConfirm];
    if (_result != null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.adminUpload)),
        body: ListView(
          padding: const EdgeInsets.all(DSpacing.xl),
          children: [
            const Icon(Icons.check_circle_rounded, color: DColors.secondary, size: 64),
            const SizedBox(height: DSpacing.l),
            Text(s.adminUploadDone, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: DSpacing.s),
            Text(_result!['releaseFolder'] as String, textAlign: TextAlign.center, style: const TextStyle(color: DColors.textMuted)),
            const SizedBox(height: DSpacing.xl),
            FilledButton(onPressed: () => context.push('/release/${_result!['releaseId']}'), child: Text(s.adminOpenRelease)),
            const SizedBox(height: DSpacing.s),
            OutlinedButton(
              onPressed: () => setState(() {
                _result = null;
                _step = 0;
                _tracks.clear();
                _cover = null;
                _title.clear();
                _existing = null;
                _newRelease = true;
                _idempotencyKey = const Uuid().v4();
              }),
              child: Text(s.adminUploadAnother),
            ),
          ],
        ),
      );
    }
    final canNext = switch (_step) {
      0 => _artist != null,
      2 => _newRelease || _existing != null,
      3 => !_newRelease || _title.text.trim().isNotEmpty,
      4 => _tracks.isNotEmpty,
      5 => _validation(s).isEmpty,
      _ => true,
    };
    return Scaffold(
      appBar: AppBar(title: Text(s.adminUpload)),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: DSpacing.l),
              itemCount: steps.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (c, i) => Center(
                child: Chip(
                  label: Text('${i + 1}. ${steps[i]}', style: TextStyle(color: i == _step ? Colors.white : (i < _step ? DColors.secondary : DColors.textDim), fontWeight: FontWeight.w700, fontSize: 12)),
                  backgroundColor: i == _step ? DColors.primary : DColors.surface2,
                ),
              ),
            ),
          ),
          Expanded(child: ListView(padding: const EdgeInsets.all(DSpacing.l), children: [_stepBody(context)])),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(DSpacing.l),
              child: Row(
                children: [
                  OutlinedButton(onPressed: _step == 0 ? null : () => setState(() => _step--), child: Text(s.back)),
                  const Spacer(),
                  if (_step < steps.length - 1)
                    FilledButton(
                      onPressed: canNext
                          ? () {
                              if (_step == 1) _loadReleases();
                              setState(() => _step++);
                            }
                          : null,
                      child: Text(s.next),
                    )
                  else
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: DColors.secondary, foregroundColor: Colors.black),
                      onPressed: !_allReady || _busy ? null : _commit,
                      child: Text(_busy ? s.adminCommitting : (_error != null ? s.retry : s.adminConfirmUpload)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    final s = context.s;
    switch (_step) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.adminStepArtistHint, style: const TextStyle(color: DColors.textMuted)),
          const SizedBox(height: DSpacing.m),
          if (_artist != null)
            ListTile(
              leading: CoverImage(imageId: _artist!.imageId, size: 48, circle: true, icon: Icons.person_rounded),
              title: Text(_artist!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: TextButton(onPressed: () => setState(() => _artist = null), child: Text(s.change)),
            )
          else
            ArtistPickerField(onSelected: (a) => setState(() => _artist = a)),
        ]);
      case 1:
        return Wrap(spacing: DSpacing.s, children: [
          for (final t in ReleaseType.values)
            ChoiceChip(
              label: Text(releaseTypeLabel(context, t)),
              selected: _type == t,
              showCheckmark: false,
              labelStyle: TextStyle(color: _type == t ? Colors.white : DColors.text),
              onSelected: (_) => setState(() => _type = t),
            ),
        ]);
      case 2:
        return RadioGroup<String>(
          groupValue: _newRelease ? 'new' : _existing?.id,
          onChanged: (v) => setState(() {
            _newRelease = v == 'new';
            _existing = v == 'new' ? null : _releases.firstWhere((r) => r.id == v);
          }),
          child: Column(children: [
            RadioListTile<String>(value: 'new', title: Text(s.adminNewRelease(releaseTypeLabel(context, _type)))),
            for (final r in _releases)
              RadioListTile<String>(
                value: r.id,
                secondary: CoverImage(imageId: r.coverImageId, size: 40),
                title: Text(r.title),
                subtitle: Text('${r.year ?? ''} • ${s.trackCount(r.trackCount)}'),
              ),
          ]),
        );
      case 3:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_newRelease) ...[
            TextField(controller: _title, decoration: InputDecoration(labelText: s.adminReleaseTitle), onChanged: (_) => setState(() {})),
            const SizedBox(height: DSpacing.m),
            Row(children: [
              Expanded(child: TextField(controller: _year, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.adminYear))),
              const SizedBox(width: DSpacing.m),
              Expanded(child: TextField(controller: _genre, decoration: InputDecoration(labelText: s.adminGenre))),
            ]),
            const SizedBox(height: DSpacing.l),
          ],
          Text(s.adminReleaseCover, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: DSpacing.s),
          Row(children: [
            if (_cover != null)
              ClipRRect(borderRadius: BorderRadius.circular(DRadius.s), child: Image.file(_cover!.file, width: 96, height: 96, fit: BoxFit.cover))
            else
              CoverImage(imageId: _existing?.coverImageId, size: 96),
            const SizedBox(width: DSpacing.l),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.image_rounded),
                  label: Text(_cover == null ? s.adminChooseCover : s.adminChangeCover),
                  onPressed: () async {
                    final f = await _pickImage();
                    if (f == null) return;
                    _cover?.cancel.cancel();
                    final up = _FileUpload(f, f.uri.pathSegments.last, 'IMAGE');
                    setState(() => _cover = up);
                    await up.run(_admin, _changed);
                  },
                ),
                if (_cover != null) _UploadStatus(up: _cover!, onRetry: () => _cover!.run(_admin, _changed)),
              ]),
            ),
          ]),
        ]);
      case 4:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OutlinedButton.icon(onPressed: _pickAudio, icon: const Icon(Icons.library_add_rounded), label: Text(s.adminChooseAudio)),
          const SizedBox(height: DSpacing.m),
          for (final t in _tracks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.audio.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: _UploadStatus(up: t.audio, onRetry: () => t.audio.run(_admin, _changed)),
              trailing: IconButton(
                tooltip: s.remove,
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  t.audio.cancel.cancel();
                  if (t.audio.uploadId != null) _admin.abortUpload(t.audio.uploadId!);
                  setState(() => _tracks.remove(t));
                },
              ),
            ),
        ]);
      case 5:
        final errs = _validation(s);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.adminReviewHint, style: const TextStyle(color: DColors.textMuted)),
          const SizedBox(height: DSpacing.m),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => setState(() {
              final t = _tracks.removeAt(from);
              _tracks.insert(to, t);
              for (var i = 0; i < _tracks.length; i++) {
                _tracks[i].number = i + 1;
              }
            }),
            children: [
              for (var i = 0; i < _tracks.length; i++) _TrackEditor(key: _tracks[i].key, draft: _tracks[i], index: i, admin: _admin, onChanged: _changed),
            ],
          ),
          if (errs.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: DSpacing.m),
              padding: const EdgeInsets.all(DSpacing.m),
              decoration: BoxDecoration(color: DColors.danger.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(DRadius.m)),
              child: Text(errs.join('\n')),
            ),
        ]);
      default:
        final totalBytes = _tracks.fold<int>(0, (s, t) => s + t.audio.file.lengthSync());
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            '${_artist?.name} • ${releaseTypeLabel(context, _type)} • ${_newRelease ? _title.text : _existing?.title}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: DSpacing.s),
          Text('${s.trackCount(_tracks.length)} • ${formatBytes(totalBytes)}', style: const TextStyle(color: DColors.textMuted)),
          const SizedBox(height: DSpacing.m),
          Text(s.adminConfirmHint, style: const TextStyle(color: DColors.textMuted)),
          if (!_allReady) Padding(padding: const EdgeInsets.only(top: DSpacing.m), child: Text(s.adminWaitingUploads)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: DSpacing.m), child: Text(_error!, style: const TextStyle(color: DColors.danger))),
        ]);
    }
  }
}

class _UploadStatus extends StatelessWidget {
  const _UploadStatus({required this.up, required this.onRetry});
  final _FileUpload up;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final label = switch (up.state) {
      _UpState.uploading => '${(up.progress * 100).round()} %',
      _UpState.validating => s.adminValidating,
      _UpState.ready => s.adminValidated,
      _UpState.error => up.error ?? s.error,
      _UpState.cancelled => s.cancelled,
    };
    final color = switch (up.state) {
      _UpState.ready => DColors.secondary,
      _UpState.error => DColors.danger,
      _ => DColors.primary,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        SizedBox(width: 90, child: LinearProgressIndicator(value: up.state == _UpState.validating ? null : up.progress, color: color, minHeight: 4)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 12))),
        if (up.state == _UpState.uploading)
          TextButton(onPressed: () => up.cancel.cancel(), child: Text(s.cancel))
        else if (up.state == _UpState.error || up.state == _UpState.cancelled)
          TextButton(onPressed: onRetry, child: Text(s.retry)),
      ]),
    );
  }
}

class _TrackEditor extends StatefulWidget {
  const _TrackEditor({super.key, required this.draft, required this.index, required this.admin, required this.onChanged});
  final _TrackDraft draft;
  final int index;
  final AdminApi admin;
  final VoidCallback onChanged;
  @override
  State<_TrackEditor> createState() => _TrackEditorState();
}

class _TrackEditorState extends State<_TrackEditor> {
  late final _title = TextEditingController(text: widget.draft.title);

  @override
  void didUpdateWidget(covariant _TrackEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_title.text != widget.draft.title) _title.text = widget.draft.title;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = widget.draft;
    return Card(
      color: DColors.surface2,
      margin: const EdgeInsets.only(bottom: DSpacing.m),
      child: Padding(
        padding: const EdgeInsets.all(DSpacing.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ReorderableDragStartListener(index: widget.index, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded))),
            InkWell(
              onTap: () async {
                final r = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
                final path = r?.path;
                if (path == null) return;
                final up = _FileUpload(File(path), r!.name, 'IMAGE');
                d.cover = up;
                widget.onChanged();
                await up.run(widget.admin, widget.onChanged);
              },
              child: d.cover != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(DRadius.s), child: Image.file(d.cover!.file, width: 56, height: 56, fit: BoxFit.cover))
                  : Tooltip(message: s.adminSongCover, child: const CoverPlaceholder(size: 56, icon: Icons.add_photo_alternate_rounded)),
            ),
            const SizedBox(width: DSpacing.m),
            Expanded(
              child: TextField(
                controller: _title,
                decoration: InputDecoration(labelText: s.adminTitle, isDense: true),
                onChanged: (v) => d.title = v,
                onEditingComplete: widget.onChanged,
              ),
            ),
          ]),
          const SizedBox(height: DSpacing.s),
          Row(children: [
            SizedBox(
              width: 80,
              child: TextFormField(
                initialValue: '${d.disc}',
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.adminDisc, isDense: true),
                onChanged: (v) {
                  d.disc = int.tryParse(v) ?? 1;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: DSpacing.s),
            SizedBox(
              width: 80,
              child: TextFormField(
                key: ValueKey('n${d.number}'),
                initialValue: '${d.number}',
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.adminTrackNo, isDense: true),
                onChanged: (v) {
                  d.number = int.tryParse(v) ?? 1;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: DSpacing.s),
            Expanded(
              child: TextFormField(
                initialValue: d.genre,
                decoration: InputDecoration(labelText: s.adminGenre, isDense: true),
                onChanged: (v) => d.genre = v,
              ),
            ),
          ]),
          if (d.cover != null) _UploadStatus(up: d.cover!, onRetry: () => d.cover!.run(widget.admin, widget.onChanged)),
          const SizedBox(height: DSpacing.s),
          _ArtistChips(label: s.adminArtists, list: d.artists, onChanged: (l) {
            d.artists = l;
            widget.onChanged();
          }),
          _ArtistChips(label: s.adminFeatures, list: d.features, onChanged: (l) {
            d.features = l;
            widget.onChanged();
          }),
          if (d.audio.probe != null)
            Text(
              '${d.audio.name} • ${formatDuration(Duration(milliseconds: ((d.audio.probe!['durationMs'] as num?) ?? 0).toInt()))} • ${d.audio.probe!['codec'] ?? ''}',
              style: const TextStyle(color: DColors.textDim, fontSize: 12),
            ),
        ]),
      ),
    );
  }
}

class _ArtistChips extends StatelessWidget {
  const _ArtistChips({required this.label, required this.list, required this.onChanged});
  final String label;
  final List<ArtistRef> list;
  final ValueChanged<List<ArtistRef>> onChanged;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: DColors.textMuted, fontSize: 12)),
      Wrap(spacing: 6, children: [
        for (final a in list) InputChip(label: Text(a.name), onDeleted: () => onChanged(list.where((x) => x.id != a.id).toList())),
        ActionChip(
          avatar: const Icon(Icons.add_rounded, size: 18),
          label: Text(context.s.add),
          onPressed: () async {
            final picked = await showModalBottomSheet<ArtistRef>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (c) => Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(c).bottom + 16),
                child: SingleChildScrollView(child: ArtistPickerField(excludeIds: list.map((a) => a.id).toList(), onSelected: (a) => Navigator.pop(c, a))),
              ),
            );
            if (picked != null) onChanged([...list, picked]);
          },
        ),
      ]),
    ]);
  }
}
