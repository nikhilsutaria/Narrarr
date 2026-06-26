import 'package:flutter/material.dart';

/// Bottom-sheet Table of Contents (#12). Lists the book's narratable chapters
/// and resolves to the chosen index (or `null` if dismissed) so the reader can
/// jump narration there and start playing.
///
/// Accessibility-first (the app's audience includes dyslexia / low-vision /
/// screen-reader users): each row is a ≥48dp target, the chapter currently
/// being narrated is marked with both an icon and a "Now playing" label (not
/// colour alone), exposes `selected` semantics to TalkBack, and the list
/// auto-scrolls so that chapter is visible on open.
Future<int?> showChapterPicker(
  BuildContext context, {
  required List<String> titles,
  required int currentIndex,
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) =>
        _ChapterPicker(titles: titles, currentIndex: currentIndex),
  );
}

class _ChapterPicker extends StatefulWidget {
  const _ChapterPicker({required this.titles, required this.currentIndex});

  final List<String> titles;
  final int currentIndex;

  @override
  State<_ChapterPicker> createState() => _ChapterPickerState();
}

class _ChapterPickerState extends State<_ChapterPicker> {
  // Roughly a ListTile's height; used to bring the current chapter into view.
  static const _rowExtent = 64.0;
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    // Scroll the currently-narrating chapter into view once laid out, so the
    // user lands on "where I am" rather than the top of a long book.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients || widget.currentIndex <= 1) return;
      final target = (widget.currentIndex - 1) * _rowExtent;
      _controller.jumpTo(target.clamp(0, _controller.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final count = widget.titles.length;
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('Contents', style: theme.textTheme.titleLarge),
            ),
            Flexible(
              child: ListView.builder(
                controller: _controller,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: count,
                itemBuilder: (context, i) {
                  final isCurrent = i == widget.currentIndex;
                  return Semantics(
                    selected: isCurrent,
                    button: true,
                    label: isCurrent
                        ? 'Chapter ${i + 1} of $count, ${widget.titles[i]}, now playing'
                        : 'Chapter ${i + 1} of $count, ${widget.titles[i]}',
                    child: ListTile(
                      selected: isCurrent,
                      selectedTileColor: cs.secondaryContainer,
                      leading: isCurrent
                          ? Icon(Icons.graphic_eq, color: cs.primary)
                          : SizedBox(
                              width: 24,
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                      title: Text(
                        widget.titles[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: isCurrent
                            ? const TextStyle(fontWeight: FontWeight.w700)
                            : null,
                      ),
                      subtitle: isCurrent ? const Text('Now playing') : null,
                      onTap: () => Navigator.of(context).pop(i),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
