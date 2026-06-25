import 'package:flutter/material.dart';

import 'reader_settings.dart';

/// Bottom sheet for adjusting reading font, size, line spacing, and page theme.
/// Calls [onChanged] live so the reader applies each change immediately.
Future<void> showReaderSettingsSheet(
  BuildContext context, {
  required ReaderSettings current,
  required ValueChanged<ReaderSettings> onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) {
      var s = current;
      return StatefulBuilder(
        builder: (context, setSheet) {
          void update(ReaderSettings next) {
            setSheet(() => s = next);
            onChanged(next);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reading settings',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),

                  // Font
                  const _Label('Font'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in ReaderFont.values)
                        ChoiceChip(
                          label: Text(f.label),
                          selected: s.font == f,
                          onSelected: (_) => update(s.copyWith(font: f)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Text size
                  const _Label('Text size'),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Smaller text',
                        onPressed: s.fontSizePercent <= 80
                            ? null
                            : () => update(s.copyWith(
                                fontSizePercent: s.fontSizePercent - 10)),
                        icon: const Icon(Icons.text_decrease),
                      ),
                      Expanded(
                        child: Center(child: Text('${s.fontSizePercent}%')),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Larger text',
                        onPressed: s.fontSizePercent >= 250
                            ? null
                            : () => update(s.copyWith(
                                fontSizePercent: s.fontSizePercent + 10)),
                        icon: const Icon(Icons.text_increase),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Line spacing
                  const _Label('Line spacing'),
                  Slider(
                    value: s.lineHeight,
                    min: 1.0,
                    max: 2.2,
                    divisions: 12,
                    label: s.lineHeight.toStringAsFixed(1),
                    onChanged: (v) => update(s.copyWith(lineHeight: v)),
                  ),
                  const SizedBox(height: 8),

                  // Dyslexia-friendly spacing
                  const _Label('Dyslexia-friendly spacing'),
                  Semantics(
                    label: 'Letter spacing',
                    child: Slider(
                      value: s.letterSpacing,
                      max: 0.25,
                      divisions: 25,
                      label: s.letterSpacing.toStringAsFixed(2),
                      onChanged: (v) => update(s.copyWith(letterSpacing: v)),
                    ),
                  ),
                  Semantics(
                    label: 'Word spacing',
                    child: Slider(
                      value: s.wordSpacing,
                      max: 0.5,
                      divisions: 25,
                      label: s.wordSpacing.toStringAsFixed(2),
                      onChanged: (v) => update(s.copyWith(wordSpacing: v)),
                    ),
                  ),
                  Semantics(
                    label: 'Paragraph spacing',
                    child: Slider(
                      value: s.paragraphSpacing,
                      max: 2.0,
                      divisions: 20,
                      label: s.paragraphSpacing.toStringAsFixed(1),
                      onChanged: (v) => update(s.copyWith(paragraphSpacing: v)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Theme
                  const _Label('Page theme'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final t in ReaderTheme.values)
                        ChoiceChip(
                          label: Text(t.label),
                          selected: s.theme == t,
                          onSelected: (_) => update(s.copyWith(theme: t)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );
}
