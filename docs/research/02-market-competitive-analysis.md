# 02 · Market & Competitive Analysis

*Narrarr — pre-build research. Last updated 2026-06-24. Sources in [sources.md](sources.md).*

Because Narrarr is a free, open-source project, this is **not** a market-sizing or pricing study. Its job is to answer three questions: **Does the niche already have a winner? What can we reuse? Where exactly do we differentiate?**

**Bottom line:** the precise combination Narrarr targets — *personal EPUBs + on-device/offline **neural** TTS + synced highlighting + free + open-source + cross-platform iOS **and** Android* — **is not occupied by any shipping app as of mid-2026.** The two closest contenders each miss on a defining axis (Readest: system-voice TTS, immersion not its focus; Voice Dream Reader: proprietary, iOS-only, and discontinued).

---

## 1. The five defining criteria

Narrarr is defined by the intersection of these, and the gap exists precisely *because* no one satisfies all of them at once:

1. Reads **your own** (DRM-free) EPUB files
2. **On-device / offline neural** TTS (not cloud, not just robotic system voices)
3. **Synced** word/sentence **highlighting** (immersion-reading UX)
4. **Free**
5. **Open-source** and **cross-platform (iOS + Android)**

## 2. Competitor matrix

| App | Own EPUBs | On-device neural TTS | Synced highlight | Free | OSS | Cross-platform | Verdict |
|---|---|---|---|---|---|---|---|
| **Speechify** | ✅ | ❌ cloud-primary | ✅ | ❌ ~$139/yr | ❌ | ✅ | Dominant but paid, proprietary, cloud |
| **Voice Dream Reader** | ✅ | ✅ (on-device) | ✅ sentence | ❌ paid | ❌ | ❌ iOS-only | **Discontinued 2024** — the orphaned niche |
| **ElevenReader** | ✅ | ❌ cloud-primary | ⚠️ unclear | freemium | ❌ | ✅ | Best voices, but cloud + privacy cost |
| **NaturalReader** | ✅ | ❌ cloud for AI voices | ✅ word | ❌ $10+/mo | ❌ | ✅ | Paid, cloud |
| **@Voice Aloud Reader** | ✅ | ⚠️ system TTS | ✅ word/sentence | ✅ (ads) | ❌ | ❌ Android-only | Closest *proprietary* match; no iOS |
| **Moon+ Reader Pro** | ✅ | ⚠️ system TTS | ⚠️ basic | ❌ ~$12 | ❌ | ❌ Android-only | Reader-first; basic TTS |
| **Legado (开源阅读)** | ✅ | ⚠️ system/plugin | ⚠️ basic | ✅ | ✅ | ❌ Android-only | OSS, but Android-only; TTS secondary |
| **Librera** | ✅ | ⚠️ system TTS | ⚠️ basic | ✅ | ✅ | ❌ Android-only | OSS, 10M+ installs; no iOS, basic TTS |
| **KOReader** | ✅ | ⚠️ system TTS (plugin) | ✅ (plugin) | ✅ | ✅ | ❌ e-ink/Android | OSS + sync highlight, but e-ink-first UX, no iOS App Store |
| **eBoox** | ✅ | ⚠️ system TTS | ⚠️ basic | ✅ | ❓ | ❌ Android-only | Lightweight; Android-only |
| **Kindle (Immersion/Whispersync)** | ❌ | ❌ human audiobook | ✅ (gold standard) | ❌ buy both | ❌ | ✅ | UX benchmark, but Amazon catalog only |
| **Apple Books** | ⚠️ limited | ✅ Spoken Content | ❌ (for imported) | ✅ | ❌ | ❌ iOS-only | No sync highlight for personal EPUBs |
| **Google Play Books** | ✅ | ⚠️ degraded offline | ❌ no read-along sync | ✅ | ❌ | ✅ | Good voices need internet; no immersion sync |
| **Readest** | ✅ | ⚠️ **system TTS only** | ✅ sentence | ✅ | ✅ | ✅ | **Closest OSS** — but TTS is system-voice-dependent & weak off-Windows; immersion not its core |
| **➡️ Narrarr (proposed)** | ✅ | ✅ | ✅ sentence→word | ✅ | ✅ | ✅ | The unoccupied intersection |

Legend: ✅ yes · ⚠️ partial/qualified · ❌ no · ❓ unclear

## 3. The gap, stated precisely

> No shipping app in mid-2026 combines **personal DRM-free EPUBs + on-device/offline *neural* TTS + synced highlighting + free + open-source + cross-platform (iOS & Android)**.

The misses cluster into predictable patterns:

- **Cloud-quality-or-nothing** (Speechify, ElevenReader, NaturalReader, Google Play Books): great voices, but only online, only paid, and your books are uploaded.
- **Android-only OSS with system voices** (Librera, Legado, @Voice, eBoox, KOReader): free and often open, but no iOS, and the read-aloud uses the OS's robotic voices rather than bundled neural models.
- **Walled gardens** (Kindle, Apple Books): polished immersion exists, but only for content bought in *their* store, not your files.

## 4. The two closest contenders (worth understanding deeply)

### Readest — the closest open-source app
Readest (Next.js + Tauri v2) is genuinely impressive: open-source, cross-platform (desktop + Android + iOS + web), with EPUB reading, sentence-level highlighting, and a TTS bar. **But:** its TTS relies on **platform/system voices** (community issues report it works well only where a good system voice exists, e.g., Windows/Edge, and is weak elsewhere), it is **not architected around bundling on-device neural TTS**, and immersion reading is *one feature among many* in a general-purpose reader whose roadmap trends toward cloud/AI extras. Narrarr's wedge is to make **neural, offline, immersion reading the entire point** rather than a side feature. *(Readest is also a model to study and, where licenses permit, learn from — see [04 · Architecture & Stack](04-architecture-and-stack.md).)*

### Voice Dream Reader — the demand signal
VDR was the beloved on-device option for exactly Narrarr's primary users (accessibility, dyslexia). Its **2024 discontinuation** — reportedly due to the unsustainability of one developer maintaining a complex accessibility app — is the single most important market event here. It (a) proves sustained demand for offline, personal-file read-aloud, (b) left users *actively* searching for alternatives, and (c) is a cautionary tale: **a proprietary solo app dies with its maintainer.** Narrarr's open-source, community-maintainable model is a direct answer to that failure mode.

## 5. Differentiation strategy

Narrarr should not try to out-feature Speechify. It should own a sharp, defensible position:

- **"Offline neural voices for your own books, free and open."** That sentence is true of *nothing else shipping*.
- **Accessibility-first**, explicitly courting the community VDR abandoned.
- **Privacy as a feature, not a footnote** — provably no uploads, auditable source.
- **Cross-platform parity** — the OSS competitors stop at Android; reaching iOS too is a real differentiator.

## 6. Implications for the build

- The niche is open, so **execution and reliability** — not novelty — decide success.
- The closest competitor (Readest) validates the form factor while leaving the *neural-offline-TTS-as-core* angle open.
- The biggest competitive risk is **not** another app; it's **the technical difficulty of synced highlighting with neural on-device TTS** (see [03 · Technical Feasibility](03-technical-feasibility.md)) and **solo-maintainer sustainability** (see [05 · Risks, Legal & Compliance](05-risks-legal-compliance.md)).

---

*Previous: [01 · Product Vision](01-product-vision.md) · Next: [03 · Technical Feasibility](03-technical-feasibility.md)*
