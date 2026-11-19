import 'package:flutter/material.dart';

import '../library/bookmark_repository.dart';

/// Bookmarks list for the current book (#48): add a bookmark at the current
/// place, jump to one, or delete one — every action an explicit, labelled
/// control (no hidden long-press, see #17).
Future<void> showBookmarksSheet(
  BuildContext context, {
  required BookmarkRepository repository,
  required String bookId,
  required String Function(String chapterHref) chapterTitle,
  required Future<void> Function() onAdd,
  required Future<void> Function(Bookmark b) onOpen,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _BookmarksSheet(
      repository: repository,
      bookId: bookId,
      chapterTitle: chapterTitle,
      onAdd: onAdd,
      onOpen: onOpen,
    ),
  );
}

class _BookmarksSheet extends StatefulWidget {
  const _BookmarksSheet({
    required this.repository,
    required this.bookId,
    required this.chapterTitle,
    required this.onAdd,
    required this.onOpen,
  });

  final BookmarkRepository repository;
  final String bookId;
  final String Function(String chapterHref) chapterTitle;
  final Future<void> Function() onAdd;
  final Future<void> Function(Bookmark b) onOpen;

  @override
  State<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<_BookmarksSheet> {
  List<Bookmark>? _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await widget.repository.forBook(widget.bookId);
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Bookmarks', style: theme.textTheme.titleLarge),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    await widget.onAdd();
                    await _reload();
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Add here'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No bookmarks yet. Tap “Add here” to save your '
                            'place — while listening, it saves the sentence '
                            'being read.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scroll,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final b = items[i];
                          final title = widget.chapterTitle(b.chapterHref);
                          final date = MaterialLocalizations.of(context)
                              .formatMediumDate(DateTime.fromMillisecondsSinceEpoch(
                                  b.createdAtMs));
                          return ListTile(
                            leading: const Icon(Icons.bookmark),
                            title: Text(b.snippet,
                                maxLines: 3, overflow: TextOverflow.ellipsis),
                            subtitle: Text('$title · $date'),
                            onTap: () async {
                              Navigator.of(context).pop();
                              await widget.onOpen(b);
                            },
                            trailing: IconButton(
                              tooltip: 'Delete bookmark',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await widget.repository.delete(b.id);
                                await _reload();
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
