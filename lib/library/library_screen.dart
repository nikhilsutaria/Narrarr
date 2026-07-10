import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../build_flavor.dart';
import '../reader/reader_screen.dart';
import '../settings/settings_screen.dart';
import 'book.dart';
import 'drift/drift_library_repository.dart';
import 'import_service.dart';
import 'library_repository.dart';

/// Home screen: the on-device library. Lists imported EPUBs and the bundled
/// sample, and lets the user add more. Minimal single-column layout, one
/// primary CTA (Add book), warm book palette (ui-ux-pro-max direction).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibraryRepository? _repo;
  List<Book> _books = const [];
  bool _loading = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final repo = await openAppLibrary();
    // The sample book ships only in the QA flavor; prod starts empty.
    if (BuildFlavor.isQa) await _seedSampleIfEmpty(repo);
    _repo = repo;
    await _refresh();
  }

  Future<void> _refresh() async {
    final books = await _repo!.all();
    if (!mounted) return;
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  /// On first run of the QA flavor, seed the bundled Odyssey so the library
  /// is never empty. (The prod flavor doesn't bundle the sample asset.)
  Future<void> _seedSampleIfEmpty(LibraryRepository repo) async {
    if ((await repo.all()).isNotEmpty) return;
    final support = await getApplicationSupportDirectory();
    final dest = File(p.join(support.path, 'the-odyssey-homer.epub'));
    if (!await dest.exists()) {
      final data = await rootBundle.load('assets/the-odyssey-homer.epub');
      await dest.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    await repo.add(Book(
      id: 'sample-odyssey',
      title: 'The Odyssey',
      author: 'Homer',
      filePath: dest.path,
      addedAtMs: 0, // sorts last; it's the seeded sample
      isBundledSample: true,
    ));
  }

  Future<void> _addBook() async {
    if (_repo == null) return;
    setState(() => _importing = true);
    try {
      final support = await getApplicationSupportDirectory();
      final booksDir = Directory(p.join(support.path, 'books'));
      final result = await pickAndImportEpub(
        booksDir: booksDir,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      if (result.canceled) return;
      if (result.error != null) {
        _showSnack(result.error!);
        return;
      }
      await _repo!.add(result.book!);
      await _refresh();
      _showSnack('Added "${result.book!.title}"');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _remove(Book book) async {
    await _repo!.remove(book.id);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Removed "${book.title}"'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await _repo!.add(book);
          await _refresh();
        },
      ),
    ));
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _open(Book book) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(book: book, repository: _repo),
      ),
    );
    // Reading position may have changed; refresh so resume state is current.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Library'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? _EmptyLibrary(onAdd: _addBook)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _books.length,
                  itemBuilder: (context, i) => _BookTile(
                    book: _books[i],
                    onTap: () => _open(_books[i]),
                    onRemove: () => _remove(_books[i]),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _addBook,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('Add book'),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book, required this.onTap, required this.onRemove});

  final Book book;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      // Cover art is decorative; the title/author already convey the book to
      // screen readers.
      leading: ExcludeSemantics(child: _Cover(book: book, scheme: scheme)),
      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: book.author != null ? Text(book.author!) : null,
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        tooltip: 'Book options',
        onSelected: (v) {
          if (v == 'remove') onRemove();
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'remove',
            enabled: !book.isBundledSample,
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.book, required this.scheme});
  final Book book;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // Reserve a fixed 40x56 (5:7) box to avoid layout shift; typographic
    // placeholder until cover extraction lands.
    final cover = book.coverPath;
    return SizedBox(
      width: 40,
      height: 56,
      child: cover != null && File(cover).existsSync()
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(File(cover), fit: BoxFit.cover),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  book.title.isNotEmpty ? book.title[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Your library is empty',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Add a DRM-free EPUB you own to start reading and listening.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add book'),
            ),
          ],
        ),
      ),
    );
  }
}
