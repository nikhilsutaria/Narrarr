import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../library/book.dart';
import '../narration/neural_narrator.dart';
import '../sync/narration_controller.dart';
import '../ui/theme.dart';
import 'book_text.dart';

/// Renders an EPUB chapter with flutter_readium and plays it aloud with the
/// offline neural voice while the current sentence highlights and the page
/// auto-follows.
///
/// Reads the bundled sample's Book IX (its hand-picked demo chapter) and the
/// first substantive chapter of any imported book. Persisted position,
/// multi-chapter navigation, position-driven sync, background playback, and
/// speed control are subsequent MVP tasks (see the Phase 1 plan + MVP spec).
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _highlightGroup = 'narrarr-utterance';

  final _readium = FlutterReadium();
  late final NarrationController _narration;

  Publication? _pub;
  String _status = 'Opening book…';
  String _chapterHref = '';
  bool _narratorReady = false;
  bool _preparingNarrator = false;

  @override
  void initState() {
    super.initState();
    _narration = NarrationController(engine: NeuralNarrator())
      ..onHighlight = _highlightSentence;
    _narration.addListener(_onNarrationChanged);
    _open();
  }

  void _onNarrationChanged() => setState(() {});

  Future<void> _open() async {
    try {
      final path = widget.book.filePath;
      final pub = await _readium.openPublication('file://$path');

      final bytes = await File(path).readAsBytes();
      final chapter = await resolveChapter(
        bytes,
        contentFileHint: widget.book.isBundledSample ? 'book-9' : null,
      );

      final link = pub.readingOrder.firstWhere(
        (l) => l.href.toLowerCase().contains(chapter.hrefHint.toLowerCase()),
        orElse: () => pub.readingOrder.first,
      );

      _narration.setSentences(chapter.sentences);
      setState(() {
        _pub = pub;
        _chapterHref = link.href;
        _status = chapter.sentences.isEmpty
            ? 'No readable text found in this book.'
            : 'Ready';
      });
    } catch (e, st) {
      debugPrint('[reader] open failed: $e\n$st');
      setState(() => _status = 'Failed to open book: $e');
    }
  }

  Locator _sentenceLocator(int index) => Locator(
        href: _chapterHref,
        type: 'application/xhtml+xml',
        text: LocatorText(highlight: _narration.sentenceTextAt(index)),
      );

  Future<void> _highlightSentence(int index) async {
    final loc = _sentenceLocator(index);
    final highlight =
        Theme.of(context).extension<ReadingColors>()!.sentenceHighlight;
    await _readium.applyDecorations(_highlightGroup, [
      ReaderDecoration(
        id: 'utterance',
        locator: loc,
        style: ReaderDecorationStyle(
          style: DecorationStyle.highlight,
          tint: highlight,
        ),
      ),
    ]);
    await _readium.goToLocator(loc);
  }

  Future<void> _togglePlay() async {
    if (_narration.isPlaying) {
      await _narration.stop();
      return;
    }
    if (!_narratorReady) {
      setState(() => _preparingNarrator = true);
      await _narration.engine.init();
      setState(() {
        _narratorReady = true;
        _preparingNarrator = false;
      });
    }
    await _narration.play();
  }

  @override
  void dispose() {
    _narration.removeListener(_onNarrationChanged);
    _narration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pub = _pub;
    if (pub == null) {
      return Scaffold(body: Center(child: Text(_status)));
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.book.title)),
      body: ReadiumReaderWidget(
        publication: pub,
        loadingWidget: const Center(child: CircularProgressIndicator()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _narration.sentenceCount == 0 ? null : _togglePlay,
        icon: _preparingNarrator
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(_narration.isPlaying ? Icons.stop : Icons.play_arrow),
        label: Text(
          _preparingNarrator
              ? 'Loading voice…'
              : _narration.isPlaying
                  ? 'Stop'
                  : 'Listen',
        ),
      ),
    );
  }
}
