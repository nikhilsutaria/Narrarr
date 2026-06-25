import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_readium/flutter_readium.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../narration/neural_narrator.dart';
import '../sync/narration_controller.dart';
import 'book_text.dart';

/// The v0.1 reader: renders a bundled EPUB chapter with flutter_readium and
/// plays it aloud with the offline neural voice while the current sentence
/// highlights and the page auto-follows.
///
/// This is the foundation vertical slice — a single bundled book and chapter.
/// Library import, persisted position, position-driven sync, background
/// playback, and speed control are the subsequent MVP phases (see the MVP spec).
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    this.bookAsset = 'assets/the-odyssey-homer.epub',
    this.chapterHint = 'book-9',
  });

  /// Bundled EPUB asset to open.
  final String bookAsset;

  /// Spine-file name fragment selecting the chapter to read.
  final String chapterHint;

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
      final path = await _copyAssetToFile(widget.bookAsset);
      final pub = await _readium.openPublication('file://$path');

      final chapter = pub.readingOrder.firstWhere(
        (l) => l.href.toLowerCase().contains(widget.chapterHint),
        orElse: () => pub.readingOrder.first,
      );

      final bytes = await File(path).readAsBytes();
      final sentences =
          await chapterSentences(bytes, contentFileHint: widget.chapterHint);

      _narration.setSentences(sentences);
      setState(() {
        _pub = pub;
        _chapterHref = chapter.href;
        _status = sentences.isEmpty
            ? 'No readable text found in chapter.'
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
    await _readium.applyDecorations(_highlightGroup, [
      ReaderDecoration(
        id: 'utterance',
        locator: loc,
        style: ReaderDecorationStyle(
          style: DecorationStyle.highlight,
          tint: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
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

  Future<String> _copyAssetToFile(String asset) async {
    final dir = await getApplicationSupportDirectory();
    final out = File(p.join(dir.path, p.basename(asset)));
    if (!await out.exists()) {
      final data = await rootBundle.load(asset);
      await out.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    return out.path;
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
      appBar: AppBar(title: Text(pub.metadata.title)),
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
