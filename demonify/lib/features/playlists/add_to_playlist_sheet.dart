import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/cover_image.dart';
import '../../l10n/l10n.dart';
import '../catalog/catalog_providers.dart';

Future<String?> askPlaylistName(BuildContext context, {String? initial, required String title, required String action}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 100,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: ctx.s.playlistName),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.s.cancel)),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: Text(action)),
      ],
    ),
  );
}

Future<void> showAddToPlaylistSheet(BuildContext context, List<String> trackIds) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final lists = ref.watch(playlistsProvider);
      final s = ctx.s;
      Future<void> add(String id, String name) async {
        Navigator.of(ctx).pop();
        try {
          await ref.read(playlistActionsProvider).addTracks(id, trackIds);
          if (context.mounted) showSnack(context, s.playlistAdded(name));
        } catch (e) {
          if (context.mounted) showSnack(context, errorText(e));
        }
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(s.addToPlaylist, style: Theme.of(ctx).textTheme.titleLarge)),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.add_rounded)),
              title: Text(s.playlistNew),
              onTap: () async {
                final name = await askPlaylistName(ctx, title: s.playlistNew, action: s.playlistCreate);
                if (name == null || name.isEmpty) return;
                if (ctx.mounted) Navigator.of(ctx).pop();
                try {
                  await ref.read(playlistActionsProvider).create(name, trackIds: trackIds);
                  if (context.mounted) showSnack(context, s.playlistAdded(name));
                } catch (e) {
                  if (context.mounted) showSnack(context, errorText(e));
                }
              },
            ),
            ...lists.when(
              data: (items) => items.map((p) => ListTile(
                    leading: CoverImage(imageId: p.coverImageIds.isEmpty ? null : p.coverImageIds.first, size: 44, icon: Icons.queue_music_rounded),
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(s.trackCount(p.trackCount)),
                    onTap: () => add(p.id, p.name),
                  )),
              loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
              error: (e, _) => [ErrorView(error: e, compact: true, onRetry: () => ref.invalidate(playlistsProvider))],
            ),
          ],
        ),
      );
    }),
  );
}
