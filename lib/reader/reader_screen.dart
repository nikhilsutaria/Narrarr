import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../library/book.dart';
import '../library/bookmark_repository.dart';
import '../library/drift/library_database.dart';
import '../a11y/a11y_policy.dart';
import '../library/library_repository.dart';
import '../narration/narration_audio_handler.dart';
import '../narration/pronunciation.dart';
import '../narration/pronunciation_dialog.dart';
import '../narration/pronunciation_repository.dart';
import '../narration/text_normalizer.dart';
import '../narration/voice_settings.dart';
import '../sync/book_position.dart';
import '../sync/narration_controller.dart';
import '../sync/progress_estimate.dart';
import '../sync/sentence_match.dart';
import '../sync/sentence_timing.dart';
import '../sync/sleep_timer.dart';
import '../sync/timing_repository.dart';
import '../ui/theme.dart';
import 'book_text.dart';
import 'bookmarks_sheet.dart';
import 'chapter_picker.dart';
import 'chapter_titles.dart';
import 'display_epub.dart';
import 'page_anchor.dart';
import 'reader_settings.dart';
import 'reader_settings_sheet.dart';

/// Renders an EPUB chapter with flutter_readium and plays it aloud with the
/// offline neural voice while the current sentence highlights and the page
/// auto-follows. Supports adjustable font/size/spacing/theme and remembers the
/// reading position.
///
/// Narrates the whole book across chapters (starting at the bundled sample's
/// Book IX, or the first substantive chapter of an imported book), with
/// background playback + lock-screen controls. Position-driven sync and speed
/// control are subsequent MVP tasks (Phase 3 / fast-follow).
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    this.repository,
    this.timingRepository,
    this.bookmarkRepository,
    this.pronunciationRepository,
  });

  final Book book;

  /// When provided, the reading position is persisted back to this repository.
  final LibraryRepository? repository;

  /// Caches measured sentence timings (Phase 3). Defaults to one backed by the
  /// app's drift database when not injected.
  final TimingRepository? timingRepository;

  /// Bookmarks store (#48); defaults to the shared app database.
  final BookmarkRepository? bookmarkRepository;

  /// Pronunciation fixes (#47); defaults to the shared app database.
  final PronunciationRepository? pronunciationRepository;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
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

  TimingRepository? _timings;
  BookmarkRepository? _bookmarks;
  PronunciationRepository? _pronunciations;
  List<PronunciationEntry> _pronunciationEntries = const [];
  // The active voice, loaded from VoiceSettings in [_applyVoiceSelection]
  // (flavor default: system TTS in prod, bundled Amy in QA). Keys the timing
  // cache and drives engine/voice selection.
  String _voiceId = VoiceSettings.defaultVoiceId;

  /// Whole book, segmented per chapter in reading order; [_spineIndex] is the
  /// chapter currently being narrated. Drives cross-chapter playback.
  List<ResolvedChapter> _spine = const [];
  int _spineIndex = 0;

  /// Character lengths of the whole spine — drives time left and % (#46).
  BookLength? _bookLength;

  Locator? _initialLocator;
  bool _preparingNarrator = false;

  /// Narration speed (#34), mirrored from [VoiceSettings] for the UI.
  double _speechSpeed = 1.0;

  /// Skip interval in seconds (#45), mirrored from [VoiceSettings].
  int _skipSeconds = 30;
  static const _speedOptions = [0.8, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];

  StreamSubscription<Locator>? _locSub;
  Timer? _saveTimer;
  Locator? _pendingLocator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A hard close (swipe-away) or backgrounding may not run dispose(), so the
    // debounced reading position would be lost. Flush it eagerly on these
    // transitions so resume (#10) survives a killed process.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _flushLocator();
    }
  }

  void _onNarrationChanged() {
    if (!mounted) return;
    // A mid-playback engine failure stops the loop and leaves a consumable
    // error (#30) — show it instead of narration just going quiet.
    final err = _narration?.takeError();
    if (err != null) {
      debugPrint('[reader] narration error: $err');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Narration stopped: the voice failed to speak. Try '
            'again, or pick another voice in Settings → Voices.'),
      ));
    }
    final active = _active;
    if (_wasActive && !active) _realignAfterBarCloses();
    _wasActive = active;
    setState(() {});
  }

  bool _wasActive = false;

  /// The narration bar going away re-paginates the reader, and Readium keeps
  /// the page *number* (often landing on the chapter's last page) without
  /// reporting a new location. Once the layout settles, turn back to the
  /// sentence narration stopped on, so the page matches where Listen
  /// continues (#63).
  void _realignAfterBarCloses() {
    Future<void>.delayed(const Duration(milliseconds: 700), () async {
      final c = _narration;
      if (!mounted || c == null || c.isPlaying || c.sentenceCount == 0) return;
      await _readium.goToLocator(_sentenceLocator(c.index));
    });
  }

  Future<void> _init() async {
    _settings = await _settingsStore.load();
    // Apply as defaults before opening so the first render uses them.
    _readium.setDefaultPreferences(_settings.toEpubPreferences());
    _handler = await narrationHandler();
    _handler!.controller.addListener(_onNarrationChanged);
    _handler!.sleepTimer.addListener(_onNarrationChanged);
    _timings = widget.timingRepository ?? TimingRepository(appDatabase());
    _bookmarks = widget.bookmarkRepository ?? BookmarkRepository(appDatabase());
    _pronunciations = widget.pronunciationRepository ??
        PronunciationRepository(appDatabase());
    // Point the engine at the user's persisted selection before opening.
    await _applyVoiceSelection();
    await _open();
  }

  /// Re-read the persisted voice selection and route the switchable engine to
  /// it: the system TTS (#15) or a neural voice. Called at reader open and
  /// again on every Listen press, so a selection made in Settings → Voices
  /// mid-session applies without reopening the book (#30).
  Future<void> _applyVoiceSelection() async {
    final h = _handler;
    if (h == null) return;
    final vs = await h.applyVoiceSettings();
    // Mirror for the UI and the timing-cache key.
    _voiceId = vs.activeVoiceId;
    _speechSpeed = vs.speechSpeed;
    _skipSeconds = vs.skipSeconds;
  }

  Future<void> _open() async {
    try {
      final path = widget.book.filePath;

      // Restore last reading position if we have one.
      final saved = widget.book.lastLocatorJson;
      if (saved != null) _initialLocator = Locator.fromJsonString(saved);

      // Open a display copy that carries the Atkinson web font (#18); the
      // narration text below still comes from the user's original file.
      final displayPath =
          await ensureDisplayCopy(bookId: widget.book.id, sourcePath: path);
      final pub = await _readium.openPublication('file://$displayPath');

      final bytes = await File(path).readAsBytes();
      _spine = await resolveSpine(bytes);
      _bookLength = BookLength([for (final c in _spine) c.sentences]);
      await _reloadPronunciations();

      // Where to begin: a saved position (resume, #10), else the bundled
      // sample's demo chapter (Book IX), else the first substantive chapter.
      // Resolved before the reader is built ([_pub] gates it), as it may
      // re-aim [_initialLocator] (#63).
      final start = _resolveStart();
      _pub = pub;

      // Persist reading position (debounced) as the reader location changes.
      _locSub = _readium.onTextLocatorChanged.listen(_onReaderLocator);
      _narration!.fetchNextChapter = _nextChapterSentences;
      _narration!.peekNextChapter = _peekNextChapterSentences;
      _narration!.fetchPreviousChapter = _previousChapterSentences;
      _narration!.onChapterTimed = _persistTimings;

      await _loadChapterAt(start.spineIndex, startSentence: start.sentenceIndex);

      setState(() {
        _status = _spine.isEmpty
            ? 'No readable text found in this book.'
            : 'Ready';
      });
    } catch (e, st) {
      debugPrint('[reader] open failed: $e\n$st');
      setState(() => _status = 'Failed to open book: $e');
    }
  }

  /// Decide where narration should begin on open: resume from the saved
  /// position if one maps into the narratable spine (#10), otherwise the
  /// default first chapter (Book IX for the bundled sample).
  BookPosition _resolveStart() {
    if (_spine.isEmpty) return (spineIndex: 0, sentenceIndex: 0);

    final loc = _initialLocator;
    if (loc != null) {
      PageAnchor? anchor;
      final pos = _positionFor(loc, onAnchor: (a) => anchor = a);
      if (pos != null) {
        if ((loc.text?.highlight ?? '').trim().isEmpty) {
          _initialLocator = _openingLocator(loc, pos, anchor);
        }
        return pos;
      }
    }

    var spineIndex = 0;
    if (widget.book.isBundledSample) {
      final idx =
          _spine.indexWhere((c) => c.hrefHint.toLowerCase().contains('book-9'));
      if (idx >= 0) spineIndex = idx;
    }
    return (spineIndex: spineIndex, sentenceIndex: 0);
  }

  /// Resolve a reader locator to a narration position (#10). A page locator
  /// (no text) is resolved through its `cssSelector` — the words at the top of
  /// the page — before falling back to its rough progression (#63).
  /// [onAnchor] receives the page anchor when one was found.
  BookPosition? _positionFor(Locator loc,
      {void Function(PageAnchor anchor)? onAnchor}) {
    final selector = loc.locations?.cssSelector;
    return resolveBookPosition(
      spine: [
        for (final c in _spine) (hrefHint: c.hrefHint, sentences: c.sentences)
      ],
      locatorHref: loc.href,
      highlightText: loc.text?.highlight,
      progression: loc.locations?.progression,
      anchorTextAt: selector == null
          ? null
          : (i) {
              final a = pageAnchorAt(_spine[i].html, selector);
              if (a != null) onAnchor?.call(a);
              return a?.matchText;
            },
    );
  }

  /// The locator to open the reader at, for a saved page locator (#63).
  /// Readium places a text-less locator by progression, which depends on the
  /// layout (the narration bar's height changes the page size), so the page
  /// shown could differ from where Listen starts. Give it text instead: the
  /// page anchor within its element when narration starts there, else the
  /// start sentence itself (the same kind of locator narration navigates by).
  Locator _openingLocator(Locator loc, BookPosition pos, PageAnchor? anchor) {
    final sentences = _spine[pos.spineIndex].sentences;
    final progression = loc.locations?.progression;
    final onAnchor = anchor != null &&
        resolveAnchorIndex(anchor.matchText, sentences, near: progression) ==
            pos.sentenceIndex;
    return Locator(
      href: loc.href,
      type: loc.type,
      title: loc.title,
      locations: Locations(
        progression: progression,
        cssSelector: onAnchor ? anchor.cssSelector : null,
      ),
      text: LocatorText(
        highlight: onAnchor
            ? anchor.highlight
            : (sentences.isEmpty ? null : sentences[pos.sentenceIndex]),
      ),
    );
  }

  /// Point the narration session at spine chapter [spineIndex], with the
  /// highlight positioned at [startSentence] (not auto-playing). The single
  /// "start at position X" path — used for resume (#10) and chapter jumps
  /// (#12). Primes the timing cache so tap-to-seek works before playback.
  Future<void> _loadChapterAt(int spineIndex, {int startSentence = 0}) async {
    final pub = _pub;
    if (pub == null) return;
    final chapter = _spine.isEmpty
        ? (
            hrefHint: '',
            sentences: <String>[],
            paragraphStarts: <int>[],
            html: '',
          )
        : _spine[spineIndex.clamp(0, _spine.length - 1)];
    _spineIndex = _spine.isEmpty ? 0 : spineIndex.clamp(0, _spine.length - 1);
    _chapterHref = _hrefFor(pub, chapter.hrefHint);

    _handler!.loadChapter(
      bookId: widget.book.id,
      title: widget.book.title,
      author: widget.book.author,
      sentences: chapter.sentences,
      voiceId: _voiceId,
      chapterHref: chapter.hrefHint,
      startSentence: startSentence,
      paragraphStarts: chapter.paragraphStarts,
      onHighlight: _highlightSentence,
    );

    // Re-listen fast path: if this chapter was measured before with this voice,
    // seed the timing table so tap-to-seek works before playback.
    final cached = await _timings?.load(
      bookId: widget.book.id,
      chapterHref: chapter.hrefHint,
      voiceId: _voiceId,
    );
    if (cached != null) _narration!.primeTimings(cached);
  }

  /// Jump narration to a chapter chosen from the Contents picker and start
  /// playing from its first sentence (#12). Stops any running session first so
  /// the play loop doesn't read the swapped-in sentences with a stale index.
  Future<void> _jumpToChapter(int spineIndex) async {
    // controller.stop, not handler.stop: a restart keeps the sleep timer.
    await _narration!.stop();
    await _loadChapterAt(spineIndex);
    await _startNarration();
  }

  /// Display titles for every spine chapter, from the book's table of contents.
  List<String> _chapterTitleList() {
    final toc = <TocEntry>[
      for (final l in (_pub?.tocFlattened ?? const <Link>[]))
        if (l.title != null) (href: l.href, title: l.title!),
    ];
    return chapterTitles(
      hrefHints: [for (final c in _spine) c.hrefHint],
      toc: toc,
    );
  }

  // ---- pronunciation (#47) ----

  /// Load this book's (and global) fixes into the speech pipeline: the
  /// dictionary runs first, then the normaliser; highlighting is unaffected.
  Future<void> _reloadPronunciations() async {
    final repo = _pronunciations;
    final c = _narration;
    if (repo == null || c == null) return;
    try {
      _pronunciationEntries = await repo.forBook(widget.book.id);
    } catch (e) {
      debugPrint('[reader] pronunciation load failed: $e');
      _pronunciationEntries = const [];
    }
    final dict = PronunciationDictionary(_pronunciationEntries);
    const normalizer = TextNormalizer();
    c.normalizeForSpeech = dict.isEmpty
        ? normalizer.normalize
        : (s) => normalizer.normalize(dict.apply(s));
  }

  Future<void> _previewSpeech(String text) async {
    try {
      await _handler?.previewSpeech(text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Couldn’t play the preview with the current voice.')));
    }
  }

  /// Teach the voice how to say [word] (#47).
  Future<void> _fixPronunciation(String word) async {
    final repo = _pronunciations;
    if (repo == null) return;
    final w = word.trim();
    final existing = _pronunciationEntries
        .where((e) => e.word.toLowerCase() == w.toLowerCase())
        .fold<PronunciationEntry?>(
            null, (best, e) => best == null || e.bookId != null ? e : best);
    final edit = await showPronunciationDialog(
      context,
      word: w,
      replacement: existing?.replacement ?? '',
      caseSensitive: existing?.caseSensitive ?? false,
      thisBookOnly: existing == null || existing.bookId != null,
      bookTitle: widget.book.title,
      onPreview: _previewSpeech,
    );
    if (edit == null) return;
    await repo.save(
      word: edit.word,
      replacement: edit.replacement,
      caseSensitive: edit.caseSensitive,
      bookId: edit.thisBookOnly ? widget.book.id : null,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _reloadPronunciations();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('“${edit.word}” will be read as “${edit.replacement}”.')));
  }

  /// ⋯ › Fix pronunciation: pick the word from the sentence being read.
  Future<void> _fixPronunciationFromSentence() async {
    final c = _narration;
    if (c == null || c.sentenceCount == 0) return;
    // Hold narration so the offered words match the highlighted sentence.
    if (c.isPlaying && !c.isPaused) await _handler!.pause();
    if (!mounted) return;
    final word = await showWordPicker(context, c.sentenceTextAt(c.index));
    if (word != null && mounted) await _fixPronunciation(word);
  }

  void _onSelectionAction(SelectionActionEvent e) {
    if (e.actionId != 'pronounce') return;
    final text = (e.selectedText ?? e.locator.text?.highlight ?? '').trim();
    if (text.isEmpty || text.length > 60) return;
    _fixPronunciation(text);
  }

  // ---- bookmarks (#48) ----

  /// Where the reader is: the narrated sentence while a session is live,
  /// otherwise the page being viewed (resolved like resume), falling back to
  /// the narration start position.
  BookPosition _currentPosition() {
    final c = _narration;
    if (c != null && c.isPlaying) {
      return (spineIndex: _spineIndex, sentenceIndex: c.index);
    }
    final loc = _pendingLocator;
    if (loc != null) {
      final pos = _positionFor(loc);
      if (pos != null) return pos;
    }
    return (spineIndex: _spineIndex, sentenceIndex: c?.index ?? 0);
  }

  Future<void> _addBookmark() async {
    final repo = _bookmarks;
    if (repo == null || _spine.isEmpty) return;
    final pos = _currentPosition();
    final chapter = _spine[pos.spineIndex.clamp(0, _spine.length - 1)];
    if (chapter.sentences.isEmpty) return;
    final si = pos.sentenceIndex.clamp(0, chapter.sentences.length - 1);
    await repo.add(
      bookId: widget.book.id,
      chapterHref: chapter.hrefHint,
      sentenceIndex: si,
      snippet: chapter.sentences[si],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Bookmark added')));
  }

  /// Jump to a bookmark: land on its sentence and highlight it; keep
  /// narrating from there if narration was playing.
  Future<void> _openBookmark(Bookmark b) async {
    final spineIndex = _spine.indexWhere((c) => c.hrefHint == b.chapterHref);
    if (spineIndex < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That bookmark’s chapter couldn’t be found.')));
      return;
    }
    final c = _narration!;
    final wasPlaying = c.isPlaying && !c.isPaused;
    await c.stop(); // a restart, not the end of the session (keeps sleep timer)
    await _loadChapterAt(spineIndex, startSentence: b.sentenceIndex);
    if (wasPlaying) {
      await _startNarration();
    } else {
      await _highlightSentence(_narration!.index);
    }
  }

  Future<void> _openBookmarks() async {
    final repo = _bookmarks;
    if (repo == null || _spine.isEmpty) return;
    final titles = _chapterTitleList();
    await showBookmarksSheet(
      context,
      repository: repo,
      bookId: widget.book.id,
      chapterTitle: (href) {
        final i = _spine.indexWhere((c) => c.hrefHint == href);
        return i < 0 ? '' : titles[i];
      },
      onAdd: _addBookmark,
      onOpen: _openBookmark,
    );
  }

  /// Open the Table of Contents and, if a chapter is chosen, jump to it (#12).
  Future<void> _openContents() async {
    if (_spine.isEmpty) return;
    final titles = _chapterTitleList();
    final chosen = await showChapterPicker(
      context,
      titles: titles,
      currentIndex: _spineIndex,
    );
    if (chosen != null && mounted) await _jumpToChapter(chosen);
  }

  /// Match a chapter's content-file hint to a reading-order href.
  String _hrefFor(Publication pub, String hrefHint) {
    if (hrefHint.isEmpty) {
      return pub.readingOrder.isEmpty ? '' : pub.readingOrder.first.href;
    }
    return pub.readingOrder
        .firstWhere(
          (l) => l.href.toLowerCase().contains(hrefHint.toLowerCase()),
          orElse: () => pub.readingOrder.first,
        )
        .href;
  }

  /// Controller callback: advance to the next spine chapter for whole-book
  /// playback. Re-points the highlight target before returning its sentences;
  /// empty list signals end of book.
  Future<List<String>> _nextChapterSentences() async {
    if (_spineIndex + 1 >= _spine.length) return const [];
    _spineIndex++;
    final next = _spine[_spineIndex];
    final pub = _pub;
    if (pub != null) _chapterHref = _hrefFor(pub, next.hrefHint);
    // Key the next chapter's timing builder before the controller swaps to it.
    _narration?.chapterHref = next.hrefHint;
    _narration?.paragraphStarts = next.paragraphStarts;
    return next.sentences;
  }

  /// Controller callback for backward skips across a chapter start (#45):
  /// step back one spine chapter, re-pointing the highlight target.
  Future<List<String>> _previousChapterSentences() async {
    if (_spineIndex <= 0) return const [];
    _spineIndex--;
    final prev = _spine[_spineIndex];
    final pub = _pub;
    if (pub != null) _chapterHref = _hrefFor(pub, prev.hrefHint);
    _narration?.chapterHref = prev.hrefHint;
    _narration?.paragraphStarts = prev.paragraphStarts;
    return prev.sentences;
  }

  /// Side-effect-free peek for the controller's cross-chapter look-ahead
  /// (#35): the spine's sentences are already segmented, so this is a plain
  /// list read — no highlight re-pointing, no state change.
  Future<List<String>> _peekNextChapterSentences() async {
    if (_spineIndex + 1 >= _spine.length) return const [];
    return _spine[_spineIndex + 1].sentences;
  }

  /// Persist a chapter's measured timings so re-listening doesn't re-measure.
  Future<void> _persistTimings(ChapterTimings t) async {
    await _timings?.save(bookId: widget.book.id, timings: t);
  }

  // ---- reading position persistence ----

  /// Page count of the chapter as last laid out, to spot re-pagination.
  int? _lastTotalPages;

  /// Page changes reported by the reader. While a narration session is live
  /// (playing or paused) the narrated sentence is the reading position: the
  /// page turns narration makes, or a look at another page while paused, must
  /// not replace it with a page locator — resume continues from the sentence,
  /// so reopening must too (#63).
  ///
  /// When the reader re-paginates (the narration bar appearing or going away
  /// resizes it) Readium keeps the page *number*, which now holds other text:
  /// pressing Listen showed a page or more away from the sentence being read.
  /// Bring the narrated sentence back into view instead (#63).
  void _onReaderLocator(Locator loc) {
    final total = loc.locations?.toJson()['totalPages'];
    final repaginated =
        total is int && _lastTotalPages != null && total != _lastTotalPages;
    if (total is int) _lastTotalPages = total;
    final c = _narration;
    if (c != null && c.isPlaying) {
      if (repaginated && c.sentenceCount > 0) {
        unawaited(_readium.goToLocator(_sentenceLocator(c.index)));
      }
      return;
    }
    // Idle right after narration stopped: the last position saved is the
    // narrated sentence; keep showing it rather than the shifted page.
    final last = _pendingLocator;
    if (repaginated && (last?.text?.highlight ?? '').isNotEmpty) {
      unawaited(_readium.goToLocator(last!));
      return;
    }
    _onLocatorChanged(loc);
  }

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
    final progress = _bookProgressAt(loc);
    // Submit both writes synchronously (no await in between) so they're queued
    // ahead of the library's refresh query when the reader closes.
    await Future.wait([
      repo.updateLocator(widget.book.id, jsonEncode(loc.toJson())),
      if (progress != null) repo.updateProgress(widget.book.id, progress),
    ]);
  }

  /// Book progress (0..1) for the library card (#46): the narrated sentence
  /// while a session is live, otherwise wherever the page locator resolves to.
  double? _bookProgressAt(Locator loc) {
    final length = _bookLength;
    final c = _narration;
    if (length == null || length.totalChars == 0) return null;
    if (c != null && c.isPlaying) {
      return length.fractionAt(spineIndex: _spineIndex, sentenceIndex: c.index);
    }
    final pos = _positionFor(loc);
    if (pos == null) return null;
    return length.fractionAt(
        spineIndex: pos.spineIndex, sentenceIndex: pos.sentenceIndex);
  }

  /// Time left in chapter/book and % through the book, from the current
  /// narration position (#46).
  ProgressEstimate? _estimate() {
    final length = _bookLength;
    final c = _narration;
    if (length == null || c == null || length.totalChars == 0) return null;
    return length.estimate(
      spineIndex: _spineIndex,
      sentenceIndex: c.index,
      speed: _speechSpeed,
      chapterTimings: c.currentTimings,
      msPerChar: c.msPerChar,
    );
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
    // Persist the narrated sentence (debounced) so resume lands on it, not just
    // the reader's scroll position (#10).
    _onLocatorChanged(loc);
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

  /// Tap-to-seek: the reader fires [onTextSelected] when the user selects text;
  /// resolve the selection to a sentence and jump narration there.
  Future<void> _seekToSelection(TextSelectionEvent e) async {
    final c = _narration;
    if (c == null || c.sentenceCount == 0) return;
    final selected =
        (e.selectedText ?? e.locator.text?.highlight ?? '').trim();
    final i = resolveSentenceIndex(selected, [
      for (var k = 0; k < c.sentenceCount; k++) c.sentenceTextAt(k),
    ]);
    if (i < 0) return;
    if (c.isPlaying) {
      await _handler!.seekToSentence(i);
    } else {
      // Idle: just move the start point (and highlight it) — Listen starts
      // there. Auto-playing here went through an engine that may not be
      // initialised yet ("speak() called before init()"), and selecting a
      // word to fix its pronunciation (#47) shouldn't start narration.
      await c.moveToSentence(i);
    }
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

  /// Start narration: apply the current voice selection, lazily init the
  /// engine (system TTS is instant; a neural voice may load — or on prod
  /// first-use, download — its model), then play. Engine init is deferred to
  /// here (not app/reader launch) to keep startup light — see the Phase-1
  /// cold-start note.
  ///
  /// Init is cheap when already initialised and single-flight when not (#30),
  /// and the FAB is disabled while [_preparingNarrator] — so a failed attempt
  /// is safely retryable and an impatient tap can't wedge the engine. Failures
  /// surface as a message instead of a forever-spinner.
  Future<void> _startNarration() async {
    final h = _handler;
    if (h == null || _preparingNarrator) return;
    setState(() => _preparingNarrator = true);
    try {
      await _applyVoiceSelection();
      await h.controller.engine.init();
    } catch (e) {
      debugPrint('[reader] narrator init failed: $e');
      if (!mounted) return;
      setState(() => _preparingNarrator = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Couldn\'t prepare the voice. Check your connection '
            'and try again, or manage voices in Settings → Voices.'),
      ));
      return;
    }
    if (!mounted) return;
    setState(() => _preparingNarrator = false);
    await h.play();
  }

  /// Persist and apply a narration speed change (#34). The engine picks it up
  /// from the next sentence; the highlight loop is untouched (it advances on
  /// real audio completion regardless of pace).
  Future<void> _setSpeed(double v) async {
    setState(() => _speechSpeed = v);
    final store = VoiceSettingsStore();
    final vs = await store.load();
    vs.speechSpeed = v;
    await store.save(vs);
    _handler?.controller.speechSpeed = v;
    await _handler?.controller.engine.setSpeed(v);
  }

  String _speedLabel(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}×' : '$v×';

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
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _flushLocator();
    _locSub?.cancel();
    // The handler is process-wide; don't dispose it. Just detach this reader
    // (clears the highlight callback) and stop audio when leaving the reader.
    _handler?.controller.removeListener(_onNarrationChanged);
    _handler?.sleepTimer.removeListener(_onNarrationChanged);
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
            tooltip: 'Contents',
            onPressed: _spine.isEmpty ? null : _openContents,
            icon: const Icon(Icons.list, semanticLabel: 'Contents — jump to a chapter'),
          ),
          IconButton(
            tooltip: 'Bookmarks',
            onPressed: _spine.isEmpty ? null : _openBookmarks,
            icon: const Icon(Icons.bookmarks_outlined),
          ),
          IconButton(
            tooltip: 'Reading settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.text_format),
          ),
        ],
      ),
      // While TalkBack is on AND we're narrating, hide the book content from the
      // a11y tree so the screen reader doesn't double-read what we speak (#12).
      body: ExcludeSemantics(
        excluding: shouldExcludeContentSemantics(
          screenReaderOn: MediaQuery.of(context).accessibleNavigation,
          narrating: _active,
        ),
        child: ReadiumReaderWidget(
          publication: pub,
          initialLocator: _initialLocator,
          loadingWidget: const Center(child: CircularProgressIndicator()),
          // Tap-to-seek: selecting a sentence jumps narration to it.
          onTextSelected: _seekToSelection,
          // "Fix pronunciation" in the text-selection menu (#47).
          selectionActions: const [
            SelectionAction(id: 'pronounce', title: 'Fix pronunciation'),
          ],
          onSelectionAction: _onSelectionAction,
        ),
      ),
      // When narration is active, the bottom bar carries the transport controls;
      // otherwise a single "Listen" FAB starts it.
      bottomNavigationBar: _active ? _buildNarrationBar(context) : null,
      floatingActionButton: _active
          ? null
          : FloatingActionButton.extended(
              // Disabled while preparing: a second tap during a slow first-time
              // model load would race a concurrent init (#30).
              onPressed:
                  ((_narration?.sentenceCount ?? 0) == 0 || _preparingNarrator)
                      ? null
                      : _playPause,
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

  /// Two-row narration bar (v1.3 "option A"): an info row with progress and
  /// time left plus quick settings, above large transport buttons.
  Widget _buildNarrationBar(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow(context),
              const SizedBox(height: 4),
              _buildTransportRow(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context) {
    final theme = Theme.of(context);
    final est = _estimate();
    final pct = est == null ? null : (est.bookFraction * 100).floor();
    final timeText = est == null
        ? ''
        : '${formatDurationShort(est.chapterRemaining)} left in chapter · '
            '${formatDurationShort(est.bookRemaining)} in book';
    final spoken = est == null
        ? ''
        : '${formatDurationSpoken(est.chapterRemaining)} left in chapter, '
            '${formatDurationSpoken(est.bookRemaining)} left in book, '
            '$pct percent through';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: spoken,
          excludeSemantics: true,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: est?.bookFraction ?? 0,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(pct == null ? '' : '$pct%',
                      style: theme.textTheme.labelLarge),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(timeText, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
        Row(
          children: [
            _buildSpeedChip(context),
            const SizedBox(width: 8),
            _buildSleepChip(context),
            const Spacer(),
            IconButton(
              tooltip: 'Bookmark this sentence',
              onPressed: _addBookmark,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
          ],
        ),
      ],
    );
  }

  /// Sleep timer chip (#44): shows the countdown (or "End of chapter") while
  /// active; tapping opens presets, extend and cancel.
  Widget _buildSleepChip(BuildContext context) {
    final t = _handler!.sleepTimer;
    final String label;
    final String spoken;
    if (t.endOfChapter) {
      label = 'End of chapter';
      spoken = 'Sleep timer, pausing at the end of this chapter';
    } else if (t.remaining != null) {
      label = formatCountdown(t.remaining!);
      spoken = 'Sleep timer, ${formatDurationSpoken(t.remaining!)} left';
    } else {
      label = 'Sleep';
      spoken = 'Sleep timer, off';
    }
    return PopupMenuButton<String>(
      tooltip: 'Sleep timer',
      onSelected: (v) {
        switch (v) {
          case 'extend':
            t.extend();
          case 'cancel':
            t.cancel();
          case 'chapter':
            t.startEndOfChapter();
          default:
            t.start(Duration(minutes: int.parse(v)));
        }
      },
      itemBuilder: (_) => [
        if (t.isActive) ...[
          PopupMenuItem(
            value: 'extend',
            child: Text('Add ${t.lastDuration.inMinutes} minutes'),
          ),
          const PopupMenuItem(value: 'cancel', child: Text('Turn off')),
          const PopupMenuDivider(),
        ],
        for (final d in SleepTimer.presets)
          PopupMenuItem(
            value: '${d.inMinutes}',
            child: Text('${d.inMinutes} minutes'),
          ),
        const PopupMenuItem(value: 'chapter', child: Text('End of chapter')),
      ],
      child: Semantics(
        label: spoken,
        button: true,
        excludeSemantics: true,
        child: Chip(
          avatar: Icon(
              t.isActive ? Icons.bedtime : Icons.bedtime_outlined,
              size: 18),
          label: Text(label),
        ),
      ),
    );
  }

  Widget _buildSpeedChip(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Narration speed',
      initialValue: _speechSpeed,
      onSelected: _setSpeed,
      itemBuilder: (_) => [
        for (final v in _speedOptions)
          PopupMenuItem(value: v, child: Text(_speedLabel(v))),
      ],
      child: Semantics(
        label: 'Narration speed, ${_speedLabel(_speechSpeed)}',
        button: true,
        excludeSemantics: true,
        child: Chip(
          avatar: const Icon(Icons.speed, size: 18),
          label: Text(_speedLabel(_speechSpeed)),
        ),
      ),
    );
  }

  Widget _buildTransportRow(BuildContext context) {
    final paused = _narration!.isPaused;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Back $_skipSeconds seconds',
          onPressed: () => _handler!.rewind(),
          icon: _SkipIcon(seconds: _skipSeconds, forward: false),
        ),
        IconButton(
          tooltip: 'Previous sentence',
          iconSize: 32,
          onPressed: () => _handler!.skipToPrevious(),
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton.filled(
          tooltip: paused ? 'Resume' : 'Pause',
          iconSize: 36,
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
          tooltip: 'Forward $_skipSeconds seconds',
          onPressed: () => _handler!.fastForward(),
          icon: _SkipIcon(seconds: _skipSeconds, forward: true),
        ),
        PopupMenuButton<String>(
          tooltip: 'More narration options',
          icon: const Icon(Icons.more_vert, size: 28),
          onSelected: (v) {
            switch (v) {
              case 'prevPara':
                _narration?.skipParagraph(-1);
              case 'nextPara':
                _narration?.skipParagraph(1);
              case 'pronounce':
                _fixPronunciationFromSentence();
              case 'stop':
                _handler!.stop();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'prevPara',
              child: ListTile(
                leading: Icon(Icons.vertical_align_top),
                title: Text('Previous paragraph'),
              ),
            ),
            PopupMenuItem(
              value: 'nextPara',
              child: ListTile(
                leading: Icon(Icons.vertical_align_bottom),
                title: Text('Next paragraph'),
              ),
            ),
            PopupMenuItem(
              value: 'pronounce',
              child: ListTile(
                leading: Icon(Icons.record_voice_over_outlined),
                title: Text('Fix pronunciation…'),
              ),
            ),
            PopupMenuItem(
              value: 'stop',
              child: ListTile(
                leading: Icon(Icons.stop),
                title: Text('Stop narration'),
              ),
            ),
          ],
        ),
      ],
    );
  }

}

/// Circular-arrow skip icon with the interval drawn inside (any of 10/15/30/60,
/// which Material's fixed replay_N / forward_N icons don't all cover).
class _SkipIcon extends StatelessWidget {
  const _SkipIcon({required this.seconds, required this.forward});
  final int seconds;
  final bool forward;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.flip(
            flipX: forward,
            child: Icon(Icons.replay, size: 32, color: color),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$seconds',
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
