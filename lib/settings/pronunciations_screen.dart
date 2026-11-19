import 'package:flutter/material.dart';

import '../library/drift/drift_library_repository.dart';
import '../library/drift/library_database.dart';
import '../narration/narration_audio_handler.dart';
import '../narration/pronunciation.dart';
import '../narration/pronunciation_dialog.dart';
import '../narration/pronunciation_repository.dart';

/// Manage pronunciation fixes (#47): every entry, global and per-book, with
/// edit, delete and add.
class PronunciationsScreen extends StatefulWidget {
  const PronunciationsScreen({super.key, this.repository});

  final PronunciationRepository? repository;

  @override
  State<PronunciationsScreen> createState() => _PronunciationsScreenState();
}

class _PronunciationsScreenState extends State<PronunciationsScreen> {
  late final PronunciationRepository _repo =
      widget.repository ?? PronunciationRepository(appDatabase());
  List<PronunciationEntry>? _entries;
  Map<String, String> _titles = const {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await _repo.all();
    var titles = _titles;
    try {
      final books = await DriftLibraryRepository(appDatabase()).all();
      titles = {for (final b in books) b.id: b.title};
    } catch (_) {}
    if (mounted) {
      setState(() {
        _entries = entries;
        _titles = titles;
      });
    }
  }

  Future<void> _preview(String text) async =>
      (await narrationHandler()).previewSpeech(text);

  Future<void> _edit(PronunciationEntry? e) async {
    final bookTitle = e?.bookId == null ? null : _titles[e!.bookId];
    final result = await showPronunciationDialog(
      context,
      word: e?.word ?? '',
      replacement: e?.replacement ?? '',
      caseSensitive: e?.caseSensitive ?? false,
      thisBookOnly: e?.bookId == null ? null : true,
      bookTitle: bookTitle,
      onPreview: _preview,
    );
    if (result == null) return;
    await _repo.save(
      id: e?.id,
      word: result.word,
      replacement: result.replacement,
      caseSensitive: result.caseSensitive,
      bookId: (e?.bookId != null && result.thisBookOnly) ? e!.bookId : null,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Pronunciations')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No fixes yet. While listening, open ⋯ › Fix '
                      'pronunciation (or select a word in the book) to teach '
                      'the voice how to say it.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final scope = e.bookId == null
                        ? 'All books'
                        : 'Only in ${_titles[e.bookId] ?? 'a removed book'}';
                    return ListTile(
                      title: Text('${e.word}  →  ${e.replacement}'),
                      subtitle: Text(e.caseSensitive
                          ? '$scope · exact capitalisation'
                          : scope),
                      onTap: () => _edit(e),
                      trailing: IconButton(
                        tooltip: 'Delete pronunciation for ${e.word}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _repo.delete(e.id);
                          await _reload();
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
