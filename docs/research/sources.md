# Sources & Bibliography

*Narrarr — pre-build research. Compiled 2026-06-24.*

Consolidated, de-duplicated references gathered during the research phase (three parallel web-research agents + targeted verification fetches). Grouped by topic.

**Confidence key:**
- ✅ **Verified** — fetched and confirmed first-hand during this research.
- 🔎 **Reported** — surfaced by research agents from reputable sources; consistent with well-established facts but not independently re-fetched.
- ⚠️ **Verify first-hand** — recent/load-bearing and worth confirming before relying on it (e.g., during the Phase 0 spike).

---

## On-device TTS engines & deployment

- ✅ sherpa-onnx TTS docs — platforms (Android/iOS/Flutter), models (VITS/Piper, Kokoro, Matcha…); TTS API returns audio, **no documented word/phoneme timestamps**: https://k2-fsa.github.io/sherpa/onnx/tts/index.html
- ✅ `sherpa_onnx` Flutter package — v1.13.x, Android multi-arch + iOS arm64, Piper/Matcha/Kokoro: https://pub.dev/packages/sherpa_onnx
- 🔎 sherpa-onnx (GitHub, Apache-2.0): https://github.com/k2-fsa/sherpa-onnx
- 🔎 Piper — active GPL-3 fork (MIT weights remain usable): https://github.com/OHF-Voice/piper1-gpl · original (archived): https://github.com/rhasspy/piper
- 🔎 Kokoro-82M (Apache-2.0): https://huggingface.co/hexgrad/Kokoro-82M
- ⚠️ Kokoro timestamped ONNX variant (phoneme→word durations): https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX-timestamped
- 🔎 Matcha-TTS: https://github.com/shivammehta25/Matcha-TTS
- 🔎 Offline TTS benchmark (Piper vs Matcha vs Kokoro RTF on phones): https://voiceping.net/en/blog/research-offline-tts-eval/
- 🔎 Running neural TTS on-device with Piper + sherpa-onnx (walkthrough): https://medium.com/@patare.vivek/running-neural-text-to-speech-on-device-with-piper-and-sherpa-onnx-58f4eed29247
- 🔎 Kokoro on-device notes: https://www.nimbleedge.com/blog/how-to-run-kokoro-tts-model-on-device/
- 🔎 XTTS-v2 / Coqui licensing & mobile non-viability: https://github.com/coqui-ai/TTS/discussions/2306
- 🔎 Parler-TTS memory footprint: https://huggingface.co/parler-tts/parler_tts_mini_v0.1/discussions/2

## Synced highlighting / text–audio alignment

- ⚠️ "Calliope" — TTS-narrated ebook creator; direct timestamp capture vs forced alignment (cited as arXiv 2602.10735 / ACM MMSys 2026): https://arxiv.org/abs/2602.10735
- ⚠️ "BFA" real-time forced alignment (cited as arXiv 2509.23147): https://arxiv.org/abs/2509.23147
- 🔎 OpenReader — EPUB/PDF read-along with Whisper-based word alignment (self-hosted): https://github.com/richardr1126/openreader
- 🔎 iOS `AVSpeechSynthesizerDelegate` willSpeakRange (word callback): https://developer.apple.com/documentation/avfoundation/avspeechsynthesizerdelegate/1619681-speechsynthesizer
- 🔎 Android `UtteranceProgressListener.onRangeStart` (word callback): https://developer.android.com/reference/android/speech/tts/UtteranceProgressListener
- 🔎 aeneas (forced alignment, server-class): https://github.com/readbeyond/aeneas

## Mobile frameworks & on-device ML runtime

- 🔎 Flutter vs React Native vs KMP (2025 comparisons): https://www.mvpappforge.com/blog/kotlin-multiplatform-vs-flutter-vs-react-native · https://www.kmpship.app/blog/kmp-vs-flutter-vs-react-native-2025
- 🔎 `react-native-sherpa-onnx` TurboModule (RN alternative): https://github.com/XDcobra/react-native-sherpa-onnx
- 🔎 ONNX Runtime NNAPI EP + Android NNAPI migration: https://onnxruntime.ai/docs/execution-providers/NNAPI-ExecutionProvider.html · https://developer.android.com/ndk/guides/neuralnetworks/migration-guide
- 🔎 sherpa-onnx Android build (native footprint ~25 MB): https://k2-fsa.github.io/sherpa/onnx/android/build-sherpa-onnx.html

## EPUB rendering & highlighting

- ✅ `flutter_readium` — **v0.1.0**, EPUB2/3 render + Decorator highlights; **platform-native TTS only, no custom-engine injection advertised**: https://pub.dev/packages/flutter_readium
- 🔎 Readium Kotlin toolkit + TTS guide (PublicationSpeechSynthesizer, Locators, Decorator): https://github.com/readium/kotlin-toolkit · https://readium.org/kotlin-toolkit/2.4.0/guides/tts/
- 🔎 Readium Swift toolkit + TTSEngine: https://github.com/readium/swift-toolkit · https://readium.org/swift-toolkit/
- 🔎 Readium Mobile overview / EDRLab: https://readium.org/mobile/ · https://www.edrlab.org/software/readium-mobile/
- 🔎 foliate-js (WebView renderer, fallback): https://github.com/johnfactotum/foliate-js

## Background audio, file import, storage

- 🔎 `just_audio` / `just_audio_background` / `audio_service`: https://pub.dev/packages/audio_service · https://pub.dev/packages/just_audio_background
- 🔎 Flutter file pickers (iOS Files / Android SAF): https://fluttergems.dev/file-picker/

## Competitors

- 🔎 Speechify pricing & EPUB TTS: https://speechify.com/pricing/ · https://speechify.com/blog/text-to-speech-epub/
- 🔎 Voice Dream Reader (discontinued 2024) — alternatives discussions: https://readaloudreader.com/blog/voice-dream-reader-alternative/ · https://alternativeto.net/software/voice-dream/
- 🔎 ElevenReader: https://elevenreader.io/
- 🔎 NaturalReader pricing: https://help.naturalreaders.com/en/articles/8854700-plans-pricing-personal-version
- 🔎 @Voice Aloud Reader: https://play.google.com/store/apps/details?id=com.hyperionics.avar
- 🔎 Moon+ Reader Pro: https://play.google.com/store/apps/details?id=com.flyersoft.moonreaderp
- 🔎 Legado (gedoor): https://github.com/gedoor/legado
- 🔎 Librera (GitHub + F-Droid): https://github.com/foobnix/LibreraReader · https://f-droid.org/en/packages/com.foobnix.pro.pdf.reader/
- 🔎 KOReader + audiobook plugin: https://github.com/koreader/koreader · https://github.com/stradichenko/audiobook.koplugin
- 🔎 Kindle Whispersync for Voice: https://help.audible.com/s/article/listen-with-whispersync-for-voice
- 🔎 Apple Books digital narration: https://itunespartner.apple.com/books/support/46-digital-narration
- 🔎 Google Play Books read aloud: https://support.google.com/googleplay/answer/11938821
- 🔎 Readest (closest OSS reader) + TTS issue: https://github.com/readest/readest · https://github.com/readest/readest/issues/258

## OSS prior art / reference apps to study

- 🔎 VoxSherpa TTS (Android, sherpa-onnx + Piper/Kokoro): https://github.com/CodeBySonu95/VoxSherpa-TTS
- 🔎 NekoSpeak (Android, multi-model sherpa-onnx): https://github.com/siva-sub/NekoSpeak
- 🔎 Auread (iOS EPUB reader, Readium + SwiftUI): https://github.com/jimjatt1999/Auread
- 🔎 Storyteller (EPUB3 Media Overlays output format): https://storyteller-platform.gitlab.io/storyteller/
- 🔎 Thorium Reader (desktop Readium + TTS + Media Overlays): https://thorium.edrlab.org/en/

## Legal, app-store policy, OSS sustainability

- 🔎 TTS & copyright overview: https://speechify.com/blog/text-to-speech-no-copyright/
- 🔎 TTS AI / IP analysis (Morgan Lewis, 2024): https://www.morganlewis.com/blogs/sourcingatmorganlewis/2024/07/rise-of-text-to-speech-ai-models-part-1-intellectual-property-issues/
- 🔎 Accessibility copyright exceptions (AU example): https://theconversation.com/australias-copyright-reform-could-bring-millions-of-books-and-other-reads-to-the-blind-67709
- 🔎 Apple on-demand resources size limits: https://developer.apple.com/help/app-store-connect/reference/on-demand-resources-size-limits/
- ⚠️ Apple App Store AI disclosure guideline (2025): https://openforge.io/app-store-review-guidelines-2025-essential-ai-app-rules/
- 🔎 F-Droid + Google developer-verification policy concern: https://f-droid.org/2025/09/29/google-developer-registration-decree.html
- 🔎 GitHub Sponsors / Open Collective for OSS funding: https://oscollective.org/

---

### Caveats on recency

The research was conducted as of mid-2026. Some sources are very recent (2025–2026) and a few citations (notably the arXiv alignment papers and exact package version numbers) should be re-confirmed first-hand — most naturally **during the Phase 0 spike**, when the relevant APIs are exercised directly anyway. The architectural conclusions do **not** hinge on any single unverified citation; they rest on the verified package facts (`sherpa_onnx`, `flutter_readium`, sherpa-onnx TTS docs) plus well-established properties of these widely-used OSS projects.
