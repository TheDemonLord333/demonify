import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/cover_image.dart';
import '../../core/widgets/media_widgets.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_controller.dart';
import '../catalog/models.dart';
import 'admin_api.dart';
import 'artist_picker.dart';

final _adminStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => ref.watch(adminApiProvider)!.stats());

/// Verwaltung (nur Administratoren; der Server prüft jede Aktion zusätzlich)
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final stats = ref.watch(_adminStatsProvider);
    Widget tile(IconData icon, String title, String sub, String path) => Card(
          color: DColors.surface1,
          child: ListTile(
            leading: Icon(icon, color: DColors.primary),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(path),
          ),
        );
    return RefreshIndicator(
      onRefresh: () => ref.refresh(_adminStatsProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(DSpacing.l),
        children: [
          SafeArea(bottom: false, child: Text(s.navAdmin, style: Theme.of(context).textTheme.headlineMedium)),
          const SizedBox(height: DSpacing.l),
          stats.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorView(error: e, compact: true, onRetry: () => ref.invalidate(_adminStatsProvider)),
            data: (st) => Wrap(spacing: DSpacing.s, runSpacing: DSpacing.s, children: [
              _Stat(s.artists, st['artists']),
              _Stat(s.releases, st['releases']),
              _Stat(s.songs, st['tracks']),
              _Stat(s.adminUsers, st['users']),
              _Stat(s.adminUnavailable, st['unavailable'], warn: (st['unavailable'] as num) > 0),
              _Stat(s.adminIssues, st['openIssues'], warn: (st['openIssues'] as num) > 0),
            ]),
          ),
          const SizedBox(height: DSpacing.l),
          tile(Icons.cloud_upload_rounded, s.adminUpload, s.adminUploadSub, '/admin/upload'),
          tile(Icons.person_rounded, s.adminArtistsTitle, s.adminArtistsSub, '/admin/artists'),
          tile(Icons.album_rounded, s.adminReleasesTitle, s.adminReleasesSub, '/admin/releases'),
          tile(Icons.group_rounded, s.adminUsers, s.adminUsersSub, '/admin/users'),
          tile(Icons.sync_rounded, s.adminJobs, s.adminJobsSub, '/admin/jobs'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.warn = false});
  final String label;
  final Object? value;
  final bool warn;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 140),
        padding: const EdgeInsets.all(DSpacing.m),
        decoration: BoxDecoration(color: DColors.surface1, borderRadius: BorderRadius.circular(DRadius.m), border: Border.all(color: DColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: warn ? DColors.warning : DColors.text)),
          Text(label, style: const TextStyle(color: DColors.textMuted)),
        ]),
      );
}

Future<File?> _pickImageFile() async {
  final r = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
  final p = r?.path;
  return p == null ? null : File(p);
}

/// Bild hochladen und Upload-ID liefern (mit Fortschrittsdialog)
Future<UploadResult?> uploadImageWithDialog(BuildContext context, AdminApi admin, File file) async {
  final progress = ValueNotifier<double>(0);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (c, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [Text(c.s.adminUploading), const SizedBox(height: 16), LinearProgressIndicator(value: v)]),
      ),
    ),
  ));
  try {
    final r = await admin.upload(file, kind: 'IMAGE', filename: file.uri.pathSegments.last, onProgress: (p, _) => progress.value = p);
    return r;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

// ───────────────────────── Künstler

class AdminArtistsScreen extends ConsumerStatefulWidget {
  const AdminArtistsScreen({super.key});
  @override
  ConsumerState<AdminArtistsScreen> createState() => _AdminArtistsScreenState();
}

class _AdminArtistsScreenState extends ConsumerState<AdminArtistsScreen> {
  String _q = '';
  Timer? _debounce;
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() => setState(() => _future = ref.read(adminApiProvider)!.listArtists(q: _q));

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.adminArtistsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final a = await showCreateArtistDialog(context, _q);
          if (a != null) _reload();
        },
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(s.adminCreateArtist),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(DSpacing.l),
          child: TextField(
            decoration: InputDecoration(hintText: s.adminArtistSearch, prefixIcon: const Icon(Icons.search_rounded)),
            onChanged: (v) {
              _q = v;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 150), _reload);
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (c, snap) {
              if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final items = snap.data!;
              if (items.isEmpty) return EmptyView(icon: Icons.person_search_rounded, title: s.adminNoArtistFound);
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: items.length,
                itemBuilder: (c, i) {
                  final a = items[i];
                  return ListTile(
                    leading: CoverImage(imageId: a['imageId'] as String?, size: 48, circle: true, icon: Icons.person_rounded),
                    title: Text(a['name'] as String),
                    subtitle: Text('${s.adminReleaseCount(a['releaseCount'] as int)} • ${s.trackCount(a['trackCount'] as int)}'),
                    onTap: () => _edit(a),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _edit(Map<String, dynamic> a) async {
    final s = context.s;
    final admin = ref.read(adminApiProvider)!;
    final ctrl = TextEditingController(text: a['name'] as String);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(c).bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: CoverImage(imageId: a['imageId'] as String?, size: 120, circle: true, icon: Icons.person_rounded)),
          const SizedBox(height: 16),
          TextField(controller: ctrl, decoration: InputDecoration(labelText: s.adminArtistName)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              try {
                await admin.renameArtist(a['id'] as String, ctrl.text.trim());
                if (c.mounted) Navigator.pop(c);
                _reload();
              } on ApiException catch (e) {
                if (c.mounted) showSnack(c, e.message);
              }
            },
            child: Text(s.save),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.image_rounded),
            label: Text(a['imageId'] == null ? s.adminUploadArtistImage : s.adminReplaceArtistImage),
            onPressed: () async {
              final f = await _pickImageFile();
              if (f == null || !c.mounted) return;
              try {
                final up = await uploadImageWithDialog(c, admin, f);
                if (up == null || !up.valid) throw ApiException(code: 'INVALID', message: up?.error ?? s.error);
                // Zuschnitt: quadratischer Ausschnitt aus der Bildmitte (feiner Zuschnitt in der Verwaltungswebseite)
                final w = (up.probe?['width'] as num).toInt();
                final h = (up.probe?['height'] as num).toInt();
                final side = w < h ? w : h;
                await admin.setArtistImage(a['id'] as String, up.id, {'left': (w - side) ~/ 2, 'top': (h - side) ~/ 2, 'width': side, 'height': side});
                if (c.mounted) Navigator.pop(c);
                _reload();
              } on ApiException catch (e) {
                if (c.mounted) showSnack(c, e.message);
              }
            },
          ),
          if (a['imageId'] != null)
            TextButton(
              onPressed: () async {
                await admin.removeArtistImage(a['id'] as String);
                if (c.mounted) Navigator.pop(c);
                _reload();
              },
              child: Text(s.adminRemoveArtistImage, style: const TextStyle(color: DColors.danger)),
            ),
        ]),
      ),
    );
  }
}

// ───────────────────────── Veröffentlichungen

class AdminReleasesScreen extends ConsumerStatefulWidget {
  const AdminReleasesScreen({super.key});
  @override
  ConsumerState<AdminReleasesScreen> createState() => _AdminReleasesScreenState();
}

class _AdminReleasesScreenState extends ConsumerState<AdminReleasesScreen> {
  String _q = '';
  Timer? _debounce;
  late Future<List<Release>> _future = ref.read(adminApiProvider)!.releases();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.adminReleasesTitle)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(DSpacing.l),
          child: TextField(
            decoration: InputDecoration(hintText: s.adminReleaseSearch, prefixIcon: const Icon(Icons.search_rounded)),
            onChanged: (v) {
              _q = v;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 150), () => setState(() => _future = ref.read(adminApiProvider)!.releases(q: _q)));
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Release>>(
            future: _future,
            builder: (c, snap) {
              if (snap.hasError) return ErrorView(error: snap.error!);
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return ListView(children: [
                for (final r in snap.data!)
                  ListTile(
                    leading: CoverImage(imageId: r.coverImageId, size: 48),
                    title: Text(r.title),
                    subtitle: Text('${releaseTypeLabel(context, r.type)} • ${r.albumArtist.name} • ${s.trackCount(r.trackCount)}'),
                    onTap: () => context.push('/admin/releases/${r.id}'),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class AdminReleaseDetailScreen extends ConsumerStatefulWidget {
  const AdminReleaseDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<AdminReleaseDetailScreen> createState() => _AdminReleaseDetailScreenState();
}

class _AdminReleaseDetailScreenState extends ConsumerState<AdminReleaseDetailScreen> {
  Map<String, dynamic>? _data;
  Object? _error;
  List<Track>? _order;
  final _title = TextEditingController();
  final _year = TextEditingController();
  final _genre = TextEditingController();
  ReleaseType _type = ReleaseType.album;

  AdminApi get _admin => ref.read(adminApiProvider)!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _admin.releaseDetail(widget.id);
      final r = Release.fromJson(d['release'] as Map<String, dynamic>);
      setState(() {
        _data = d;
        _order = null;
        _title.text = r.title;
        _year.text = r.year?.toString() ?? '';
        _genre.text = r.genre ?? '';
        _type = r.type;
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (mounted) showSnack(context, ok);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_error != null) return Scaffold(appBar: AppBar(), body: ErrorView(error: _error!, onRetry: _load));
    if (_data == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final release = Release.fromJson(_data!['release'] as Map<String, dynamic>);
    final tracks = _order ?? (_data!['tracks'] as List).map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(release.title)),
      body: ListView(padding: const EdgeInsets.all(DSpacing.l), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CoverImage(imageId: release.coverImageId, size: 120, radius: DRadius.m),
          const SizedBox(width: DSpacing.l),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(release.albumArtist.name, style: const TextStyle(color: DColors.textMuted)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.image_rounded),
                label: Text(release.coverImageId == null ? s.adminChooseCover : s.adminChangeCover),
                onPressed: () async {
                  final f = await _pickImageFile();
                  if (f == null || !context.mounted) return;
                  final up = await uploadImageWithDialog(context, _admin, f);
                  if (up == null || !up.valid) {
                    if (context.mounted) showSnack(context, up?.error ?? s.error);
                    return;
                  }
                  await _run(() => _admin.setReleaseCover(release.id, up.id), s.saved);
                },
              ),
            ]),
          ),
        ]),
        const SizedBox(height: DSpacing.l),
        TextField(controller: _title, decoration: InputDecoration(labelText: s.adminReleaseTitle)),
        const SizedBox(height: DSpacing.m),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<ReleaseType>(
              initialValue: _type,
              decoration: InputDecoration(labelText: s.adminType),
              items: [for (final t in ReleaseType.values) DropdownMenuItem(value: t, child: Text(releaseTypeLabel(context, t)))],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
          ),
          const SizedBox(width: DSpacing.m),
          Expanded(child: TextField(controller: _year, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.adminYear))),
        ]),
        const SizedBox(height: DSpacing.m),
        TextField(controller: _genre, decoration: InputDecoration(labelText: s.adminGenre)),
        const SizedBox(height: DSpacing.m),
        FilledButton(
          onPressed: () => _run(
            () => _admin.updateRelease(release.id, {
              'title': _title.text.trim(),
              'type': _type.apiName,
              'year': int.tryParse(_year.text.trim()),
              'genre': _genre.text.trim().isEmpty ? null : _genre.text.trim(),
            }),
            s.saved,
          ),
          child: Text(s.save),
        ),
        const SizedBox(height: DSpacing.xl),
        Row(children: [
          Expanded(child: Text(s.adminTracks, style: Theme.of(context).textTheme.titleLarge)),
          if (_order != null)
            FilledButton(
              onPressed: () => _run(() => _admin.setReleaseOrder(release.id, [for (final t in tracks) {'id': t.id, 'discNumber': t.discNumber}]), s.saved),
              child: Text(s.adminSaveOrder),
            ),
        ]),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorderItem: (from, to) => setState(() {
            final list = List.of(tracks);
            final t = list.removeAt(from);
            list.insert(to, t);
            _order = list;
          }),
          children: [
            for (final t in tracks)
              ListTile(
                key: ValueKey(t.id),
                leading: CoverImage(imageId: t.coverImageId, size: 44),
                title: Text('${t.trackNumber}. ${t.title}'),
                subtitle: Text([t.artistLine, formatDuration(t.duration), if (!t.available) s.unavailable, if (t.hasOwnCover) s.adminOwnCover].join(' • ')),
                onTap: () => _editTrack(t),
              ),
          ],
        ),
      ]),
    );
  }

  Future<void> _editTrack(Track t) async {
    final s = context.s;
    final title = TextEditingController(text: t.title);
    var disc = t.discNumber;
    var number = t.trackNumber;
    var artists = t.artists.where((a) => !a.featured).map((a) => ArtistRef(id: a.id, name: a.name)).toList();
    var features = t.artists.where((a) => a.featured).map((a) => ArtistRef(id: a.id, name: a.name)).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(c).bottom + 24),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: title, decoration: InputDecoration(labelText: s.adminTitle)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextFormField(initialValue: '$disc', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(labelText: s.adminDisc), onChanged: (v) => disc = int.tryParse(v) ?? 1)),
                const SizedBox(width: 8),
                Expanded(child: TextFormField(initialValue: '$number', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(labelText: s.adminTrackNo), onChanged: (v) => number = int.tryParse(v) ?? 1)),
              ]),
              const SizedBox(height: 8),
              Text(s.adminArtists, style: const TextStyle(color: DColors.textMuted)),
              Wrap(spacing: 6, children: [for (final a in artists) InputChip(label: Text(a.name), onDeleted: () => setSt(() => artists = artists.where((x) => x.id != a.id).toList()))]),
              ArtistPickerField(hint: s.adminAddArtist, excludeIds: artists.map((a) => a.id).toList(), onSelected: (a) => setSt(() => artists = [...artists, a])),
              const SizedBox(height: 8),
              Text(s.adminFeatures, style: const TextStyle(color: DColors.textMuted)),
              Wrap(spacing: 6, children: [for (final a in features) InputChip(label: Text(a.name), onDeleted: () => setSt(() => features = features.where((x) => x.id != a.id).toList()))]),
              ArtistPickerField(hint: s.adminAddFeature, excludeIds: features.map((a) => a.id).toList(), onSelected: (a) => setSt(() => features = [...features, a])),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: artists.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(c);
                        await _run(
                          () => _admin.updateTrack(t.id, {
                            'title': title.text.trim(),
                            'discNumber': disc,
                            'trackNumber': number,
                            'artistIds': artists.map((a) => a.id).toList(),
                            'featuredArtistIds': features.map((a) => a.id).toList(),
                          }),
                          s.saved,
                        );
                      },
                child: Text(s.save),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.image_rounded),
                label: Text(t.hasOwnCover ? s.adminReplaceSongCover : s.adminSongCover),
                onPressed: () async {
                  final f = await _pickImageFile();
                  if (f == null || !c.mounted) return;
                  final up = await uploadImageWithDialog(c, _admin, f);
                  if (c.mounted) Navigator.pop(c);
                  if (up == null || !up.valid) {
                    if (mounted) showSnack(context, up?.error ?? s.error);
                    return;
                  }
                  await _run(() => _admin.setTrackCover(t.id, up.id), s.saved);
                },
              ),
              if (t.hasOwnCover)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(c);
                    await _run(() => _admin.removeTrackCover(t.id), s.saved);
                  },
                  child: Text(s.adminRemoveSongCover),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Benutzer & Einladungen

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _future = _load();
  AdminApi get _admin => ref.read(adminApiProvider)!;

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async => (await _admin.users(), await _admin.invites());
  void _reload() => setState(() => _future = _load());

  Future<void> _act(Future<void> Function() f) async {
    try {
      await f();
      _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.adminUsers), actions: [
        IconButton(tooltip: s.adminCreateInvite, icon: const Icon(Icons.mail_outline_rounded), onPressed: _invite),
        IconButton(tooltip: s.adminCreateUser, icon: const Icon(Icons.person_add_rounded), onPressed: _create),
      ]),
      body: FutureBuilder(
        future: _future,
        builder: (c, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (users, invites) = snap.data!;
          return ListView(children: [
            for (final u in users)
              ListTile(
                leading: Icon(u['role'] == 'ADMIN' ? Icons.admin_panel_settings_rounded : Icons.person_rounded, color: u['role'] == 'ADMIN' ? DColors.primary : null),
                title: Text(u['username'] as String),
                subtitle: Text([
                  u['role'] == 'ADMIN' ? s.roleAdmin : s.roleUser,
                  if (u['disabled'] == true) s.adminDisabled,
                  s.adminSessions(u['activeSessions'] as int),
                ].join(' • ')),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => _act(() async {
                    switch (v) {
                      case 'role':
                        await _admin.updateUser(u['id'] as String, {'role': u['role'] == 'ADMIN' ? 'USER' : 'ADMIN'});
                      case 'disable':
                        await _admin.updateUser(u['id'] as String, {'disabled': !(u['disabled'] as bool)});
                      case 'revoke':
                        await _admin.revokeSessions(u['id'] as String);
                      case 'delete':
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text(s.adminDeleteUserTitle),
                            content: Text(s.adminDeleteUserMessage(u['username'] as String)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.cancel)),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: DColors.danger),
                                onPressed: () => Navigator.pop(c, true),
                                child: Text(s.delete),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) await _admin.deleteUser(u['id'] as String);
                    }
                  }),
                  itemBuilder: (c) => [
                    PopupMenuItem(value: 'role', child: Text(u['role'] == 'ADMIN' ? s.adminMakeUser : s.adminMakeAdmin)),
                    PopupMenuItem(value: 'disable', child: Text(u['disabled'] == true ? s.adminEnable : s.adminDisable)),
                    PopupMenuItem(value: 'revoke', child: Text(s.adminRevokeSessions)),
                    if (u['id'] != ref.read(currentUserProvider)?.id)
                      PopupMenuItem(value: 'delete', child: Text(s.adminDeleteUser, style: const TextStyle(color: DColors.danger))),
                  ],
                ),
              ),
            Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 8), child: Text(s.adminInvites, style: Theme.of(context).textTheme.titleMedium)),
            for (final i in invites)
              ListTile(
                leading: const Icon(Icons.mail_outline_rounded),
                title: Text((i['note'] as String?) ?? (i['role'] == 'ADMIN' ? s.roleAdmin : s.roleUser)),
                subtitle: Text('${i['status']} • ${(i['expiresAt'] as String).substring(0, 16).replaceFirst('T', ' ')}'),
                trailing: i['status'] == 'OPEN'
                    ? IconButton(tooltip: s.adminRevoke, icon: const Icon(Icons.block_rounded), onPressed: () => _act(() => _admin.revokeInvite(i['id'] as String)))
                    : null,
              ),
          ]);
        },
      ),
    );
  }

  Future<void> _create() async {
    final s = context.s;
    final user = TextEditingController();
    final pass = TextEditingController();
    var admin = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) => AlertDialog(
          title: Text(s.adminCreateUser),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: user, decoration: InputDecoration(labelText: s.username)),
            TextField(controller: pass, obscureText: true, decoration: InputDecoration(labelText: s.adminStartPassword)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(s.roleAdmin), value: admin, onChanged: (v) => setSt(() => admin = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.cancel)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.adminCreate)),
          ],
        ),
      ),
    );
    if (ok == true) await _act(() => _admin.createUser({'username': user.text.trim(), 'password': pass.text, 'role': admin ? 'ADMIN' : 'USER'}));
  }

  Future<void> _invite() async {
    final s = context.s;
    try {
      final link = await _admin.createInvite(role: 'USER', hours: 72);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(s.adminInviteCreated),
          content: SelectableText(link),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
                Navigator.pop(c);
              },
              child: Text(s.copy),
            ),
          ],
        ),
      );
      _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }
}

// ───────────────────────── Aufträge, Probleme, nicht verfügbare Dateien

class AdminJobsScreen extends ConsumerStatefulWidget {
  const AdminJobsScreen({super.key});
  @override
  ConsumerState<AdminJobsScreen> createState() => _AdminJobsScreenState();
}

class _AdminJobsScreenState extends ConsumerState<AdminJobsScreen> {
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _issues = [];
  List<Map<String, dynamic>> _unavailable = [];
  Object? _error;
  Timer? _timer;
  AdminApi get _admin => ref.read(adminApiProvider)!;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_jobs.any((j) => j['status'] == 'RUNNING' || j['status'] == 'QUEUED')) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([_admin.jobs(), _admin.issues(), _admin.tracks(available: false)]);
      if (mounted) {
        setState(() {
          _jobs = r[0];
          _issues = r[1];
          _unavailable = r[2];
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.adminJobs)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          try {
            await _admin.startScan();
            await _load();
          } on ApiException catch (e) {
            if (context.mounted) showSnack(context, e.message);
          }
        },
        icon: const Icon(Icons.sync_rounded),
        label: Text(s.adminStartScan),
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                for (final j in _jobs)
                  ListTile(
                    title: Text(_jobLabel(s, j['type'] as String)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: (j['progress'] as num).toDouble(),
                        color: j['status'] == 'FAILED' ? DColors.danger : (j['status'] == 'SUCCEEDED' ? DColors.secondary : DColors.primary),
                      ),
                      const SizedBox(height: 4),
                      Text((j['error'] ?? j['message'] ?? j['status']).toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]),
                    trailing: (j['status'] == 'RUNNING' || j['status'] == 'QUEUED')
                        ? IconButton(tooltip: s.cancel, icon: const Icon(Icons.stop_circle_outlined), onPressed: () => _admin.cancelJob(j['id'] as String).then((_) => _load()))
                        : null,
                  ),
                Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 8), child: Text('${s.adminUnavailable} (${_unavailable.length})', style: Theme.of(context).textTheme.titleMedium)),
                for (final t in _unavailable)
                  ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, color: DColors.warning),
                    title: Text(t['title'] as String),
                    subtitle: Text(t['audioPath'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 8), child: Text('${s.adminIssues} (${_issues.length})', style: Theme.of(context).textTheme.titleMedium)),
                for (final i in _issues)
                  ListTile(
                    leading: Icon(i['kind'] == 'INCOMPLETE_METADATA' ? Icons.edit_note_rounded : Icons.error_outline_rounded, color: i['kind'] == 'INCOMPLETE_METADATA' ? DColors.warning : DColors.danger),
                    title: Text(i['relPath'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(i['message'] as String, maxLines: 3, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(tooltip: s.adminResolve, icon: const Icon(Icons.check_rounded), onPressed: () => _admin.resolveIssue(i['id'] as String).then((_) => _load())),
                  ),
              ]),
            ),
    );
  }

  String _jobLabel(S s, String type) => switch (type) {
        'LIBRARY_SCAN' => s.jobScan,
        'TRANSCODE' => s.jobTranscode,
        _ => s.jobCleanup,
      };
}
