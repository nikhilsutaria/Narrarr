# 01 · Product Vision & Strategy

*Narrarr — pre-build research. Last updated 2026-06-24.*

> **Narrarr** is a free, open-source, cross-platform mobile app that turns the DRM-free EPUBs you already own into a Kindle-style *immersion reading* experience — reading the book aloud with on-device, offline AI voices while the text highlights in sync — with no subscriptions, no accounts, and no data leaving your phone.

---

## 1. The problem

People own powerful phones and own books, yet the experience of *reading and listening at the same time* — proven to aid comprehension, retention, focus, and accessibility — is locked behind paywalls and walled gardens:

- **Kindle Immersion Reading / Whispersync** only works if you buy *both* the Kindle ebook *and* the matching Audible audiobook from Amazon. It does nothing for the EPUBs you already own.
- **Speechify, NaturalReader, ElevenReader** can read your own files, but the good voices are cloud-based and cost **$10–$29/month**, and your book text is uploaded to their servers.
- **The best offline option for this exact use case — Voice Dream Reader — was discontinued in 2024**, stranding a loyal accessibility community with no comparable replacement.
- The open-source Android readers that *do* read aloud (Librera, Legado, KOReader, @Voice) depend on **degraded system voices**, are **Android-only**, and don't deliver a polished, cross-platform immersion experience.

The result: to listen to a book you legally own, on a phone that's more than capable of doing the work locally, you currently have to pay a subscription, accept a privacy trade-off, or settle for a robotic system voice.

## 2. Why now

Three things have changed that make a free, on-device solution newly viable:

1. **Neural TTS got small and fast enough for phones.** Open-source models like **Piper** run *many times faster than real-time* on mid-range phones in well under 100 MB, and higher-quality models like **Kokoro-82M** are usable on recent hardware. (See [03 · Technical Feasibility](03-technical-feasibility.md).)
2. **The deployment tooling matured.** **sherpa-onnx** ships official, maintained Android, iOS, and Flutter bindings for running these models on-device — the single hardest part of "offline AI on a phone" is now a dependency, not a research project.
3. **There's a vacated niche and an unmet, vocal demand** — the Voice Dream Reader shutdown left accessibility users actively searching for a private, offline alternative.

The pieces to build this *well, for free, and offline* exist today, and they didn't a few years ago.

## 3. What Narrarr is

A focused reading companion, not a content store. You bring your own DRM-free EPUBs; Narrarr renders them as a clean reader and, on demand, narrates them with a natural offline voice while keeping the spoken text highlighted so your eyes can follow along — or you can put the phone in your pocket and just listen, with lock-screen controls.

Everything runs **on the device**. No login. No cloud. No subscription. The whole thing is **open source** so it can be audited, trusted, forked, and outlive any single maintainer (the lesson of Voice Dream Reader).

## 4. Target users

Ranked by urgency of unmet need:

1. **Accessibility readers — dyslexia, print disability, low vision (primary).** This group relied on Voice Dream Reader, finds Speechify's pricing prohibitive, and explicitly wants a private, offline, dependable tool. The assistive-technology framing is also Narrarr's strongest legal and community asset (see [05 · Risks, Legal & Compliance](05-risks-legal-compliance.md)). Allies: DAISY Consortium, Bookshare, RNIB.
2. **Privacy-conscious / anti-subscription readers with personal EPUB libraries.** People who get DRM-free books from Project Gutenberg, Humble Bundle, Standard Ebooks, their university, or by de-DRMing their own purchases, and refuse to route their reading through a commercial AI service. "Your device, your data" *is* the pitch.
3. **Language learners.** Synchronized read-along in a target language is one of the most effective acquisition techniques; today it requires a paid Speechify/NaturalReader tier.
4. **Commuters & multitaskers.** The Whispersync use case — seamlessly switch between reading and listening to the *same* book without losing your place — but for books you already own.

## 5. Positioning

**Positioning statement:**
> *The only free, open-source, cross-platform app that gives you Kindle-style immersion reading for books you already own — entirely on your device, with no subscriptions, no accounts, and no data leaving your phone.*

**One-line differentiation per rival** (full analysis in [02 · Market & Competitive Analysis](02-market-competitive-analysis.md)):

| Against… | Narrarr's edge |
|---|---|
| Speechify / ElevenReader / NaturalReader | No subscription, no account, no cloud — books never leave the device |
| Kindle Immersion Reading | Works with *any* DRM-free EPUB you own, not just Amazon + Audible purchases |
| @Voice / Moon+ / Librera / Legado | Cross-platform (iOS **and** Android), open-source, neural-quality offline voices instead of degraded system TTS |
| Readest (closest OSS) | Purpose-built for immersion reading with neural on-device TTS as the core, not a secondary feature dependent on system-voice quality |
| Voice Dream Reader (discontinued) | Alive, free, cross-platform, community-maintainable, and auditable |

## 6. Guiding principles

- **Offline-first & private by default.** No network needed to read or listen. No telemetry, no accounts. Network is used only to *optionally* download extra voices.
- **Free and open-source, forever.** No monetization. Sustainability comes from openness and community, not revenue (see [05](05-risks-legal-compliance.md)).
- **Accessibility-first.** Designed with screen-reader users, dyslexia-friendly typography, and assistive workflows as first-class concerns — not afterthoughts.
- **Honest scope.** Ship a reliable core rather than an over-promised everything. Notably: **sentence-level** synced highlighting first, **word-level** as a later stretch goal — because that's what's genuinely robust on-device today (see [03](03-technical-feasibility.md)).
- **Reuse over reinvention.** Stand on mature OSS (sherpa-onnx, Piper, Readium) and build only the glue.

## 7. Success criteria

Because there is no revenue goal, success is defined by impact, reliability, and longevity:

- **It works as promised, offline.** A user can import a DRM-free EPUB and, with no network, hear it read in a natural voice with the current sentence highlighted, on both iOS and Android.
- **Accessibility impact.** Adopted and recommended within dyslexia / blind / low-vision communities; works cleanly with platform screen readers.
- **Trust.** Verifiably no data leaves the device; reproducible open-source builds.
- **Sustainability.** A real contributor base and a maintainable, well-scoped codebase that doesn't die with one burned-out solo maintainer.
- **Distribution.** Available on Google Play, the App Store (via the standard developer program), and F-Droid.

## 8. Non-goals

- ❌ A bookstore / content library (you bring your own files).
- ❌ Opening DRM-protected ebooks (Kindle/Kobo purchases) — out of scope, by design (see [05](05-risks-legal-compliance.md)).
- ❌ Monetization, subscriptions, or accounts.
- ❌ Cloud TTS or cloud sync in v1 (offline-first; optional cloud sync could be a *much* later, opt-in consideration).
- ❌ Word-perfect "karaoke" highlighting in v1 (sentence-level first — see [03](03-technical-feasibility.md)).
- ❌ Voice cloning of real people.

---

*Next: [02 · Market & Competitive Analysis](02-market-competitive-analysis.md).*
