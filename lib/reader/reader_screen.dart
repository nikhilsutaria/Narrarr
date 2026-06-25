import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../library/book.dart';
import '../library/library_repository.dart';
import '../narration/narration_audio_handler.dart';
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

  /// Process-wide narration handler (owns the controller + neural engine).
  /// Resolved in [_init]; this reader attaches its chapter + highlight callback.
  NarrationAudioHandler? _handler;
  NarrationController? get _narration => _handler?.controller;

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
    _init();
  }

  void _onNarrationChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    _settings = await _settingsStore.load();
    // Apply as defaults before opening so the first render uses them.
    _readium.setDefaultPreferences(_settings.toEpubPreferences());
    _handler = await narrationHandler();
    _handler!.controller.addListener(_onNarrationChanged);
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

      _handler!.loadChapter(
        bookId: widget.book.id,
        title: widget.book.title,
        author: widget.book.author,
        sentences: chapter.sentences,
        onHighlight: _highlightSentence,
      );
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
        text: LocatorText(highlight: _narration!.sentenceTextAt(index)),
      );

  Future<void> _highlightSentence(int index) async {
    if (!mounted) return;
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

  /// First press: lazily load the neural voice model, then start. The engine
  /// model load is deferred to here (not app/reader launch) to keep startup
  /// light — see the Phase-1 cold-start note.
  Future<void> _startNarration() async {
    final h = _handler;
    if (h == null) return;
    if (!_narratorReady) {
      setState(() => _preparingNarrator = true);
      await h.controller.engine.init();
      if (!mounted) return;
      setState(() {
        _narratorReady = true;
        _preparingNarrator = false;
      });
    }
    await h.play();
  }

  Future<void> _playPause() async {
    final c = _narration;
    if (c == null) return;
    if (c.isPaused) {
      await _handler!.play(); // resume
    } else if (c.isPlaying) {
      await _handler!.pause();
    } else {
      await _startNarration();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _flushLocator();
    _locSub?.cancel();
    // The handler is process-wide; don't dispose it. Just detach this reader
    // (clears the highlight callback) and stop audio when leaving the reader.
    _handler?.controller.removeListener(_onNarrationChanged);
    _handler?.endSession();
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
      // When narration is active, the bottom bar carries the transport controls;
      // otherwise a single "Listen" FAB starts it.
      bottomNavigationBar: _active ? _buildNarrationBar(context) : null,
      floatingActionButton: _active
          ? null
          : FloatingActionButton.extended(
              onPressed:
                  (_narration?.sentenceCount ?? 0) == 0 ? null : _playPause,
              icon: _preparingNarrator
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(
                _preparingNarrator ? 'Loading voice…' : 'Listen',
                semanticsLabel: 'Listen — read this chapter aloud',
              ),
            ),
    );
  }

  /// Narration is "active" while playing or paused (the session is live).
  bool get _active => _narration?.isPlaying ?? false;

  /// Transport bar: previous sentence / play-pause / next sentence / stop.
  Widget _buildNarrationBar(BuildContext context) {
    final c = _narration!;
    final paused = c.isPaused;
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: 'Previous sentence',
            iconSize: 32,
            onPressed: () => _handler!.skipToPrevious(),
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton.filled(
            tooltip: paused ? 'Resume' : 'Pause',
            iconSize: 32,
            onPressed: _playPause,
            icon: Icon(paused ? Icons.play_arrow : Icons.pause,
                semanticLabel: paused ? 'Resume narration' : 'Pause narration'),
          ),
          IconButton(
            tooltip: 'Next sentence',
            iconSize: 32,
            onPressed: () => _handler!.skipToNext(),
            icon: const Icon(Icons.skip_next),
          ),
          IconButton(
            tooltip: 'Stop',
            iconSize: 32,
            onPressed: () => _handler!.stop(),
            icon: const Icon(Icons.stop, semanticLabel: 'Stop narration'),
          ),
        ],
      ),
    );
  }
}
