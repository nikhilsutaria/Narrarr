# Bundled neural voices (local-only)

The Piper voice models (`*.tar`, ~80 MB each) are **git-ignored** — they are too
large to commit and, per the [MVP plan](../../docs/research/06-mvp-scope-and-roadmap.md),
voices will be **downloaded on demand** (Phase 4) rather than bundled.

For now, the foundation slice loads a bundled voice. To run the app you need:

- `vits-piper-en_US-amy-low.tar` — the current default (sherpa-onnx + Piper).

Obtain it from the sherpa-onnx / Piper voice releases (an uncompressed `.tar`
containing `*.onnx`, `tokens.txt`, and `espeak-ng-data/`) and place it in this
directory. On first run it is extracted into app-support storage.

> The recommended quality voice for v1 is a `ryan-medium`-class voice
> (see [POC findings §8](../../docs/poc/02-tts-pipeline-findings.md)); `amy-low`
> is the POC/spike carry-over and will be revisited when download-on-demand lands.
