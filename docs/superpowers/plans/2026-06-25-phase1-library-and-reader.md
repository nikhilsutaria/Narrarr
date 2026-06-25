# Phase 1 — Library & Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Turn the single-bundled-book foundation slice into a real **library + reader**: import DRM-free EPUBs, see them in a home library, open any of them, read comfortably (font/size/theme), and have the reading position remembered — with the read-aloud + synced-highlight loop working on imported books.

**Architecture:** Add two subsystems to the existing `lib/` (`narration/`, `reader/`, `sync/`, `ui/`): `library/` (model + repository + home screen + import) and reader generalization (open any book's chapters, not just the bundled Odyssey's Book IX). Persistence starts behind a `LibraryRepository` interface (JSON store) and migrates to **drift** (the spec's choice) without touching callers.

**Tech Stack:** Flutter · flutter_readium · sherpa_onnx · `file_picker` · (later) `drift` + `sqlite3_flutter_libs` · `receive_sharing_intent` (share-sheet, later).

## Global Constraints

- **Android-first**; keep iOS-clean. Real-device perf checks still outstanding (per [reader-spike findings](../../poc/04-reader-spike-findings.md)).
- **DRM-free EPUB only.** Detect & reject DRM/corrupt files with a clear message — never crash.
- **Offline, no account, no telemetry.**

## UI/UX Decisions (from ui-ux-pro-max — apply throughout)

These are locked design tokens/rules for Phase 1 (source: ui-ux-pro-max design-system + accessibility rules):

- **Palette:** warm "book/page" — app seed `#8D6E63` (warm brown); avoid the old indigo. Calm chrome that doesn't compete with the page. (Implemented in `lib/ui/theme.dart`.)
- **Sentence highlight:** warm highlighter-yellow semantic token `ReadingColors.sentenceHighlight` (≈ amber-300 @ 0.55). Keeps dark body text ≥ 4.5:1; low-glare. Never hardcode the color in widgets.
- **Reading font:** **Atkinson Hyperlegible** (dyslexia-friendly, WCAG) for body text where we control it; expose it as a reader font option. Bundle the font (offline requirement — no Google Fonts network fetch).
- **Layout:** minimal, single-column, generous whitespace; one primary CTA per screen (`primary-action`).
- **Touch targets:** ≥ 48dp; ≥ 8dp spacing (`touch-target-size`).
- **Lists:** virtualize the library list (`ListView.builder`) (`virtualize-lists`).
- **Empty/error/loading states:** every screen has them (`empty-states`, `progressive-loading`).
- **Accessibility:** semantic labels on icon-only buttons; support dynamic text scale; respect reduced-motion; color never the sole signal (`aria-labels`/`voiceover-sr`, `dynamic-type`, `reduced-motion`, `color-not-only`).
- **Covers:** reserve aspect-ratio space to avoid layout shift (`image-dimension`); show a typographic placeholder when an EPUB has no cover.

---

## Tasks

### Task 1: Library model + repository (JSON store behind an interface)
**Files:** `lib/library/book.dart`, `lib/library/library_repository.dart`, `test/library_repository_test.dart`
- `Book` model: `id`, `title`, `author?`, `filePath`, `coverPath?`, `addedAt`, `lastLocatorJson?`.
- `LibraryRepository` interface: `Future<List<Book>> all()`, `add(Book)`, `remove(id)`, `updateLocator(id, json)`.
- `JsonLibraryRepository`: persists a manifest in app-support storage.
- **Test:** add → all → updateLocator → remove round-trips through a temp dir.
- **Deliverable:** unit-tested repository; no UI yet.

### Task 2: Library home screen (UI)
**Files:** `lib/library/library_screen.dart`, wire as `home:` in `app.dart`
- Minimal single-column list of books (cover thumbnail + title + author), `ListView.builder`.
- App bar "Your Library"; FAB **"Add book"** (single primary CTA, labeled icon).
- **Empty state:** friendly message + the Add-book CTA.
- Tap a book → `ReaderScreen(book)`. Long-press / overflow → Remove (with confirm + undo).
- The bundled Odyssey is seeded into the library on first run so there's always content.
- **Deliverable:** library renders the seeded book; navigation to reader works.

### Task 3: EPUB import (file picker)
**Files:** `lib/library/import_service.dart`, hook into `library_screen.dart`
- `file_picker` (extension `epub`) → copy into app-sandbox `books/` → extract metadata (title/author/cover via `epubx`) → `repository.add`.
- **DRM/corrupt detection:** if `EpubReader.readBook` throws or an encryption.xml/DRM marker is present, reject with a clear snackbar; don't add.
- Progress + success/error feedback (`submit-feedback`).
- **Deliverable:** import a real EPUB from device storage; it appears in the library and opens.

### Task 4: Generalize the reader to any book/chapter
**Files:** `lib/reader/book_text.dart`, `lib/reader/reader_screen.dart`
- Replace the hardcoded `book-9` hint: read the **first substantive chapter** (reuse the POC's ">600 chars prose" heuristic), and expose chapter next/prev.
- `ReaderScreen` takes a `Book`; highlight/locator logic uses the current chapter's href (from `onTextLocatorChanged`).
- **Deliverable:** open an arbitrary imported EPUB and read+listen to it.

### Task 5: Persisted reading position (Locator)
**Files:** `reader_screen.dart`, `library_repository.dart`
- Subscribe to `onTextLocatorChanged`; debounce-save the serialized `Locator` to the book record.
- On open, pass `initialLocator` to `ReadiumReaderWidget` to restore position (survives restart **and** font change — Locators are reflow-stable).
- **Deliverable:** close mid-chapter, reopen, land in the same place.

### Task 6: Reader controls (font / size / theme)
**Files:** `lib/reader/reader_settings_sheet.dart`, `reader_screen.dart`; bundle Atkinson Hyperlegible
- Bottom sheet: font (incl. **Atkinson Hyperlegible**), text size, line spacing, and light/sepia/dark **reading theme** via `flutter_readium`'s `EPUBPreferences` / `setEPUBPreferences`.
- When the reader theme is dark, switch the highlight token to a dark-page variant (the `ReadingColors` TODO).
- **Deliverable:** adjustable, comfortable reading; preferences persisted.

### Task 7: Migrate library store to drift
**Files:** `lib/library/drift/*.dart`, swap the `LibraryRepository` implementation
- Add `drift` + `sqlite3_flutter_libs` + `drift_dev`/`build_runner`; define the books table; codegen; implement `DriftLibraryRepository`; migrate the JSON manifest on first run.
- **Deliverable:** library backed by SQLite (the spec's choice); callers unchanged.

### Task 8: Accessibility pass
**Files:** across screens
- TalkBack labels on all icon controls; verify dynamic-type scaling doesn't truncate; reduced-motion respected; contrast audit (4.5:1) in light + dark.
- **Deliverable:** the library + reader are usable end-to-end with TalkBack.

---

## Phase 1 Definition of Done
- [ ] Import a DRM-free EPUB (picker); DRM/corrupt rejected clearly.
- [ ] Library lists books with covers; add/remove with confirm+undo.
- [ ] Open any book; read it reflowed with adjustable font/size/theme (incl. Atkinson Hyperlegible).
- [ ] Reading position remembered across restart and font change.
- [ ] Read-aloud + synced yellow highlight works on imported books.
- [ ] Library persisted via drift.
- [ ] Usable with TalkBack; warm palette; no indigo; contrast ≥ 4.5:1.

*Predecessor: [MVP spec](../specs/2026-06-25-narrarr-mvp-design.md) Phase 1. Foundation: commit `258e6f3`.*
