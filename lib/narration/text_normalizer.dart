/// Written-form → spoken-form normalization (#36), applied to each sentence
/// just before it reaches a TTS engine (system or neural). Piper/espeak-ng's
/// own handling of numbers, dashes and curly punctuation is weak and won't be
/// fixed upstream (rhasspy/piper#122; repo archived) — this is the app's own
/// front-end, the same layer every production TTS pipeline has.
///
/// Deliberately conservative: anything ambiguous passes through unchanged
/// (espeak-ng still has fallback rules). Pure and Flutter-free like
/// [Segmenter], so it's table-testable.
///
/// IMPORTANT: normalization is engine-input only. Highlighting locates
/// sentences by their **original** text; callers must never feed normalized
/// text to the reader/locator side.
class TextNormalizer {
  const TextNormalizer();

  String normalize(String sentence) {
    var s = sentence;
    s = _canonicalizePunctuation(s);
    s = _romanHeading(s);
    s = _numberRanges(s);
    s = _emDashes(s);
    s = _abbreviations(s);
    s = _currency(s);
    s = _percent(s);
    s = _ordinals(s);
    s = _decimals(s);
    s = _integers(s);
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ---- punctuation ----

  String _canonicalizePunctuation(String s) => s
      .replaceAll('‘', "'") // ‘
      .replaceAll('’', "'") // ’ (curly apostrophe garbles espeak words)
      .replaceAll('“', '"') // “
      .replaceAll('”', '"') // ”
      .replaceAll('…', '...') // …
      .replaceAll(RegExp(r'\s*\.\s+\.\s+\.'), '...') // spaced ellipsis
      .replaceAll('­', '') // soft hyphen splits words for espeak
      .replaceAll(RegExp('[​‌‍﻿]'), '') // zero-width
      .replaceAll(' ', ' '); // nbsp

  /// `word—word` and ` — ` asides read most naturally as a comma pause.
  String _emDashes(String s) =>
      s.replaceAll(RegExp(r'\s*—\s*'), ', ');

  /// En-dash (and hyphen) between numbers is a range: `1914–1918` → "to".
  String _numberRanges(String s) => s.replaceAllMapped(
        RegExp(r'(\d)\s*[–-]\s*(\d)'),
        (m) => '${m[1]} to ${m[2]}',
      );

  // ---- abbreviations ----

  static final List<(RegExp, String Function(Match))> _abbrevRules = [
    (RegExp(r'\bMr\.(?=\s)'), (_) => 'Mister'),
    (RegExp(r'\bMrs\.(?=\s)'), (_) => 'Missus'),
    (RegExp(r'\bDr\.(?=\s[A-Z])'), (_) => 'Doctor'),
    (RegExp(r'\bProf\.(?=\s[A-Z])'), (_) => 'Professor'),
    (RegExp(r'\bCapt\.(?=\s[A-Z])'), (_) => 'Captain'),
    (RegExp(r'\bLt\.(?=\s[A-Z])'), (_) => 'Lieutenant'),
    (RegExp(r'\bGen\.(?=\s[A-Z])'), (_) => 'General'),
    (RegExp(r'\bCol\.(?=\s[A-Z])'), (_) => 'Colonel'),
    (RegExp(r'\bSgt\.(?=\s[A-Z])'), (_) => 'Sergeant'),
    (RegExp(r'\bRev\.(?=\s[A-Z])'), (_) => 'Reverend'),
    (RegExp(r'\bHon\.(?=\s[A-Z])'), (_) => 'Honorable'),
    (RegExp(r'\bJr\.'), (_) => 'Junior'),
    (RegExp(r'\bSr\.(?=\s)'), (_) => 'Senior'),
    (RegExp(r'\bMt\.(?=\s[A-Z])'), (_) => 'Mount'),
    // St. before a capitalized word is almost always Saint ("St. Peter");
    // after a name it's usually Street, which espeak already reads fine —
    // only the Saint case is rewritten.
    (RegExp(r'\bSt\.(?=\s[A-Z])'), (_) => 'Saint'),
    (RegExp(r'\bvs\.'), (_) => 'versus'),
    (RegExp(r'\betc\.'), (_) => 'et cetera'),
    (RegExp(r'\be\.g\.'), (_) => 'for example'),
    (RegExp(r'\bi\.e\.'), (_) => 'that is'),
    (RegExp(r'\bNo\.(?=\s*\d)'), (_) => 'Number'),
    (RegExp(r'\ba\.m\.'), (_) => 'ay em'),
    (RegExp(r'\bp\.m\.'), (_) => 'pee em'),
  ];

  String _abbreviations(String s) {
    for (final (re, replace) in _abbrevRules) {
      s = s.replaceAllMapped(re, replace);
    }
    return s;
  }

  // ---- roman-numeral headings ----

  static final _strictRoman = RegExp(
      r'^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$');
  static final _headingRoman = RegExp(
      r'^((?:Chapter|Book|Part|Canto|Section)\s+)([IVXLCDM]{1,15})(\.?)$',
      caseSensitive: false);

  /// "XIV." or "Book XIV" as a whole sentence (chapter headings) → words.
  String _romanHeading(String s) {
    final t = s.trim();
    final h = _headingRoman.firstMatch(t);
    if (h != null) {
      final n = _parseRoman(h.group(2)!.toUpperCase());
      if (n != null) return '${h.group(1)}${_cardinal(n)}${h.group(3)}';
      return s;
    }
    final bare = t.endsWith('.') ? t.substring(0, t.length - 1) : t;
    if (bare.length >= 2 &&
        _strictRoman.hasMatch(bare) &&
        bare == bare.toUpperCase()) {
      final n = _parseRoman(bare);
      if (n != null) return _cardinal(n) + (t.endsWith('.') ? '.' : '');
    }
    return s;
  }

  int? _parseRoman(String r) {
    if (r.isEmpty || !_strictRoman.hasMatch(r)) return null;
    const values = {
      'M': 1000, 'D': 500, 'C': 100, 'L': 50, 'X': 10, 'V': 5, 'I': 1,
    };
    var total = 0;
    for (var i = 0; i < r.length; i++) {
      final v = values[r[i]]!;
      final next = i + 1 < r.length ? values[r[i + 1]]! : 0;
      total += v < next ? -v : v;
    }
    return total == 0 ? null : total;
  }

  // ---- numbers ----

  String _currency(String s) => s.replaceAllMapped(
        RegExp(r'([$£€])(\d[\d,]*)(?:\.(\d{2}))?'),
        (m) {
          final unit = switch (m[1]) {
            r'$' => ('dollar', 'cent'),
            '£' => ('pound', 'penny'),
            _ => ('euro', 'cent'),
          };
          final whole = int.tryParse(m[2]!.replaceAll(',', ''));
          if (whole == null) return m[0]!;
          final cents = m[3] == null ? 0 : int.parse(m[3]!);
          var out =
              '${_cardinal(whole)} ${unit.$1}${whole == 1 ? '' : 's'}';
          if (cents > 0) {
            final centWord = unit.$2 == 'penny'
                ? (cents == 1 ? 'penny' : 'pence')
                : '${unit.$2}${cents == 1 ? '' : 's'}';
            out += ' and ${_cardinal(cents)} $centWord';
          }
          return out;
        },
      );

  String _percent(String s) => s.replaceAllMapped(
        RegExp(r'\b(\d[\d,]*)%'),
        (m) {
          final n = int.tryParse(m[1]!.replaceAll(',', ''));
          return n == null ? m[0]! : '${_cardinal(n)} percent';
        },
      );

  String _ordinals(String s) => s.replaceAllMapped(
        RegExp(r'\b(\d+)(st|nd|rd|th)\b'),
        (m) {
          final n = int.tryParse(m[1]!);
          return n == null ? m[0]! : _ordinal(n);
        },
      );

  String _decimals(String s) => s.replaceAllMapped(
        RegExp(r'\b(\d+)\.(\d+)\b'),
        (m) {
          final whole = int.tryParse(m[1]!);
          if (whole == null) return m[0]!;
          final digits = m[2]!.split('').map(_digitWord).join(' ');
          return '${_cardinal(whole)} point $digits';
        },
      );

  String _integers(String s) => s.replaceAllMapped(
        RegExp(r'\b\d[\d,]*\b'),
        (m) {
          final raw = m[0]!.replaceAll(',', '');
          if (raw.length > 12) return m[0]!; // leave the absurd to espeak
          final n = int.tryParse(raw);
          if (n == null) return m[0]!;
          // A standalone 4-digit 1100–2099 almost always reads as a year
          // ("eighteen seventy-six") — also the natural reading for counts
          // ("fifteen hundred ships").
          if (m[0]!.length == 4 && n >= 1100 && n <= 2099) return _year(n);
          return _cardinal(n);
        },
      );

  String _year(int n) {
    final high = n ~/ 100;
    final low = n % 100;
    if (n >= 2000 && n < 2010) return _cardinal(n); // "two thousand five"
    if (low == 0) return '${_cardinal(high)} hundred';
    if (low < 10) return '${_cardinal(high)} oh ${_cardinal(low)}';
    return '${_cardinal(high)} ${_cardinal(low)}';
  }

  String _digitWord(String d) => const [
        'zero', 'one', 'two', 'three', 'four',
        'five', 'six', 'seven', 'eight', 'nine',
      ][int.parse(d)];

  static const _units = [
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
    'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
    'sixteen', 'seventeen', 'eighteen', 'nineteen',
  ];
  static const _tens = [
    '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy',
    'eighty', 'ninety',
  ];

  String _cardinal(int n) {
    if (n < 0) return 'minus ${_cardinal(-n)}';
    if (n < 20) return _units[n];
    if (n < 100) {
      final t = _tens[n ~/ 10];
      final r = n % 10;
      return r == 0 ? t : '$t-${_units[r]}';
    }
    if (n < 1000) {
      final h = '${_units[n ~/ 100]} hundred';
      final r = n % 100;
      return r == 0 ? h : '$h ${_cardinal(r)}';
    }
    for (final (scale, word) in [
      (1000000000000, 'trillion'),
      (1000000000, 'billion'),
      (1000000, 'million'),
      (1000, 'thousand'),
    ]) {
      if (n >= scale) {
        final head = '${_cardinal(n ~/ scale)} $word';
        final r = n % scale;
        return r == 0 ? head : '$head ${_cardinal(r)}';
      }
    }
    return '$n'; // unreachable
  }

  String _ordinal(int n) {
    final c = _cardinal(n);
    final lastSpace = c.lastIndexOf(RegExp(r'[ -]'));
    final head = lastSpace < 0 ? '' : c.substring(0, lastSpace + 1);
    final last = lastSpace < 0 ? c : c.substring(lastSpace + 1);
    const irregular = {
      'one': 'first', 'two': 'second', 'three': 'third', 'five': 'fifth',
      'eight': 'eighth', 'nine': 'ninth', 'twelve': 'twelfth',
    };
    final tail = irregular[last] ??
        (last.endsWith('y')
            ? '${last.substring(0, last.length - 1)}ieth'
            : '${last}th');
    return '$head$tail';
  }
}
