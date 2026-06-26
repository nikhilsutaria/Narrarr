# Bundled neural voices (local-only)

The Piper voice models (`*.tar`, ~80 MB each) are **git-ignored** — they are too
large to commit; the higher-quality voices are **downloaded on demand** rather
than bundled.

For now, the foundation slice loads a bundled voice. To run the app you need:

- `vits-piper-en_US-amy-low.tar` — the current default (sherpa-onnx + Piper).

Obtain it from the sherpa-onnx / Piper voice releases (an uncompressed `.tar`
containing `*.onnx`, `tokens.txt`, and `espeak-ng-data/`) and place it in this
directory. On first run it is extracted into app-support storage.

> `amy-low` is the bundled offline default; higher-quality `ryan-medium` and
> `amy-medium` voices download on demand from the sherpa-onnx releases.
