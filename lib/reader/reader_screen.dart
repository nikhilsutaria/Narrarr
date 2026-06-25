import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../library/book.dart';
import '../library/library_repository.dart';
import '../narration/neural_narrator.dart';
import '../sync/narration_controller.dart';
import '../ui/theme.dart';
import 'book_text.dart';
import 'reader_settings.dart';
import 'reader_settings_sheet.dart';

/// Renders an EPUB chapter with flutter_readium and plays it aloud with the
/// offline neural voice while the current sentence highlights and the page
/// auto-follows. Supports adjustable font/size/spacing/theme and remembers the
/// reading position.
///
/// Reads the bundled sample's Book IX (its hand-picked demo chapter) and the
/// first substantive chapter of any imported book. Multi-chapter navigation,
/// position-driven sync, background playback, and speed control are subsequent
/// MVP tasks (see the Phase 1 plan + MVP spec).
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book, this.repository});

  final Book book;

  /// When provided, the reading position is persisted back to this repository.
  final LibraryRepository? repository;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _highlightGroup = 'narrarr-utterance';

  final _readium = FlutterReadium();
  final _settingsStore = ReaderSettingsStore();
  late final NarrationController _narration;

  ReaderSettings _settings = ReaderSettings();
  Publication? _pub;
  String _status = 'Opening book…';
  String _chapterHref = '';
  Locator? _initialLocator;
  bool _narratorReady = false;
  bool _preparingNarrator = false;

  StreamSubscription<Locator>? _locSub;
  Timer? _saveTimer;
  Locator? _pendingLocator;

  @override
  void initState() {
    super.initState();
    _narration = NarrationController(engine: NeuralNarrator())
      ..onHighlight = _highlightSentence;
    _narration.addListener(_onNarrationChanged);
    _init();
  }

  void _onNarrationChanged() => setState(() {});

  Future<void> _init() async {
    _settings = await _settingsStore.load();
    // Apply as defaults before opening so the first render uses them.
    _readium.setDefaultPreferences(_settings.toEpubPreferences());
    await _open();
  }

  Future<void> _open() async {
    try {
      final path = widget.book.filePath;

      // Restore last reading position if we have one.
      final saved = widget.book.lastLocatorJson;
      if (saved != null) _initialLocator = Locator.fromJsonString(saved);

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

      // Persist reading position (debounced) as the reader location changes.
      _locSub = _readium.onTextLocatorChanged.listen(_onLocatorChanged);

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

  // ---- reading position persistence ----

  void _onLocatorChanged(Locator loc) {
    if (widget.repository == null) return;
    _pendingLocator = loc;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), _flushLocator);
  }

  Future<void> _flushLocator() async {
    final loc = _pendingLocator;
    final repo = widget.repository;
    if (loc == null || repo == null) return;
    await repo.updateLocator(widget.book.id, jsonEncode(loc.toJson()));
  }

  // ---- highlight ----

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
          // Highlight matches the reader page (light vs dark), not app chrome.
          tint: ReadingColors.forReaderBrightness(_settings.theme.brightness),
        ),
      ),
    ]);
    await _readium.goToLocator(loc);
  }

  // ---- settings ----

  Future<void> _openSettings() async {
    await showReaderSettingsSheet(
      context,
      current: _settings,
      onChanged: (next) async {
        setState(() => _settings = next);
        await _readium.setEPUBPreferences(next.toEpubPreferences());
        await _settingsStore.save(next);
      },
    );
  }

  // ---- playback ----

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
    _saveTimer?.cancel();
    _flushLocator();
    _locSub?.cancel();
    _narration.removeListener(_onNarrationChanged);
    _narration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pub = _pub;
    if (pub == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.book.title)),
        body: Center(child: Text(_status)),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          IconButton(
            tooltip: 'Reading settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.text_format),
          ),
        ],
      ),
      body: ReadiumReaderWidget(
        publication: pub,
        initialLocator: _initialLocator,
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
          semanticsLabel: _narration.isPlaying
              ? 'Stop narration'
              : 'Listen — read this chapter aloud',
        ),
      ),
    );
  }
}
