import 'package:flutter/material.dart';

/// What the user chose in the pronunciation dialog (#47).
typedef PronunciationEdit = ({
  String word,
  String replacement,
  bool caseSensitive,
  bool thisBookOnly,
});

/// Add or edit a pronunciation fix. [thisBookOnly] null hides the scope choice
/// (the entry is global); otherwise it is the initial choice, labelled with
/// [bookTitle]. [onPreview] speaks text offline with the current voice.
Future<PronunciationEdit?> showPronunciationDialog(
  BuildContext context, {
  required String word,
  String replacement = '',
  bool caseSensitive = false,
  bool? thisBookOnly,
  String? bookTitle,
  required Future<void> Function(String text) onPreview,
}) {
  return showDialog<PronunciationEdit>(
    context: context,
    builder: (_) => _PronunciationDialog(
      word: word,
      replacement: replacement,
      caseSensitive: caseSensitive,
      thisBookOnly: thisBookOnly,
      bookTitle: bookTitle,
      onPreview: onPreview,
    ),
  );
}

class _PronunciationDialog extends StatefulWidget {
  const _PronunciationDialog({
    required this.word,
    required this.replacement,
    required this.caseSensitive,
    required this.thisBookOnly,
    required this.bookTitle,
    required this.onPreview,
  });

  final String word;
  final String replacement;
  final bool caseSensitive;
  final bool? thisBookOnly;
  final String? bookTitle;
  final Future<void> Function(String text) onPreview;

  @override
  State<_PronunciationDialog> createState() => _PronunciationDialogState();
}

class _PronunciationDialogState extends State<_PronunciationDialog> {
  late final _word = TextEditingController(text: widget.word);
  late final _say = TextEditingController(text: widget.replacement);
  late bool _caseSensitive = widget.caseSensitive;
  late bool _thisBook = widget.thisBookOnly ?? false;
  bool _previewing = false;

  @override
  void dispose() {
    _word.dispose();
    _say.dispose();
    super.dispose();
  }

  bool get _valid => _word.text.trim().isNotEmpty && _say.text.trim().isNotEmpty;

  Future<void> _preview() async {
    final text = _say.text.trim().isNotEmpty ? _say.text : _word.text;
    if (text.trim().isEmpty) return;
    setState(() => _previewing = true);
    try {
      await widget.onPreview(text.trim());
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Fix pronunciation'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _word,
            decoration: const InputDecoration(
              labelText: 'Word or phrase in the book',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _say,
            autofocus: widget.replacement.isEmpty,
            decoration: const InputDecoration(
              labelText: 'Say it as',
              hintText: 'e.g. her-MY-oh-nee',
              helperText: 'Spell it the way it sounds.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _previewing ? null : _preview,
              icon: _previewing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.volume_up),
              label: const Text('Preview'),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Match capitalisation exactly'),
            subtitle: const Text('Off: also fixes it in capitals or lowercase'),
            value: _caseSensitive,
            onChanged: (v) => setState(() => _caseSensitive = v),
          ),
          if (widget.thisBookOnly != null) ...[
            const SizedBox(height: 4),
            Text('Apply to', style: theme.textTheme.titleSmall),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.bookTitle == null
                  ? 'Only this book'
                  : 'Only “${widget.bookTitle}”'),
              value: true,
              groupValue: _thisBook,
              onChanged: (v) => setState(() => _thisBook = v!),
            ),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              title: const Text('All books'),
              value: false,
              groupValue: _thisBook,
              onChanged: (v) => setState(() => _thisBook = v!),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !_valid
              ? null
              : () => Navigator.of(context).pop((
                    word: _word.text.trim(),
                    replacement: _say.text.trim(),
                    caseSensitive: _caseSensitive,
                    thisBookOnly: _thisBook,
                  )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Pick the word the voice got wrong from [sentence] (#47) — the accessible
/// path that doesn't need text selection in the reader.
Future<String?> showWordPicker(BuildContext context, String sentence) {
  final words = <String>[];
  for (final m in RegExp(r"[\p{L}\p{N}][\p{L}\p{N}'’\-]*", unicode: true)
      .allMatches(sentence)) {
    final w = m[0]!.replaceAll(RegExp(r"['’\-]+$"), '');
    if (w.isNotEmpty && !words.contains(w)) words.add(w);
  }
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Which word does the voice get wrong?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in words)
                  ActionChip(
                    label: Text(w),
                    onPressed: () => Navigator.of(context).pop(w),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
