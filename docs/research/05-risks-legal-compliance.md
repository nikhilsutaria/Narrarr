# 05 · Risks, Legal & Compliance

*Narrarr — pre-build research. Last updated 2026-06-24. Sources in [sources.md](sources.md).*

> ⚖️ **Not legal advice.** This is researched, good-faith analysis to inform decisions. For anything load-bearing (e.g., terms of service, jurisdiction-specific questions), confirm with a qualified professional before launch.

The headline: **the legal and compliance posture is favorable**, the costs are tiny, and the real risks are **technical** and **sustainability**, not legal.

---

## 1. Legal & ethical position

**Reading aloud a DRM-free book you already own, entirely on your own device, is legitimate** and is fundamentally different from pirating an audiobook:

- **No DRM circumvention.** Narrarr only opens DRM-free EPUBs. It never breaks protection (which *would* be a legal problem under anti-circumvention law). Purchased Kindle/Kobo files simply won't parse — and that's by design.
- **No distribution.** The user supplies their own file; the app neither provides books nor distributes the synthetic narration. Audio is generated on-device, for that user, and isn't shared. Narrarr is a **reading tool**, not a content service — the piracy distinction.
- **Personal, transformative, private use.** Generating speech from text you own, for your own consumption, has not been the target of publisher litigation; the principle aligns with long-standing personal-use doctrine.
- **Accessibility is strong armor.** Converting owned content to an accessible format for personal disability use is explicitly supported by accessibility exceptions (e.g., US fair use, Australia's Copyright Act disability provisions, UK fair dealing). Framing Narrarr as **assistive technology** is both honest and protective.
- **Voice-cloning laws don't apply.** Statutes like Tennessee's ELVIS Act target simulating a *specific identifiable person's* voice. Narrarr uses generic OSS voice models (Piper/Kokoro) trained on consented datasets — out of scope. (Narrarr also explicitly does **not** do voice cloning.)

**Product guardrails that preserve this position:**
- Only open DRM-free files; never add de-DRM functionality.
- Don't export/share generated audio as distributable audiobook files in v1 (keep it ephemeral playback / on-device cache). Re-evaluate any "export audio" feature carefully later.
- State clearly in-app and in docs: *"Narrarr reads DRM-free books you already own; it is not a bookstore and does not remove DRM."*

## 2. App-store & distribution realities

Costs for a free OSS project are small and fixed: **Apple Developer Program $99/year**, **Google Play one-time $25**, **F-Droid free**.

| Channel | Key facts | Notes for Narrarr |
|---|---|---|
| **Apple App Store** | Background audio via standard `AVAudioSession` entitlement (routine for any audio app). Assets >200 MB don't download over cellular → use **On-Demand Resources** for voices. **On-device AI that sends no data off-device avoids the AI data-disclosure rules.** "Reads books aloud" is an established, allowed category. | Bundle one small Piper voice; download bigger voices via ODR. Lead with the accessibility framing in review notes. |
| **Google Play** | Background audio needs `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (standard). Downloading **model weight files is fine** — the policy restricts executable code, not data. One-time $25 + identity verification. | Download-on-first-run for voices is policy-clean. |
| **F-Droid** | OSS-native, no fee, no tracking; builds **from source**, so the app must be reproducibly buildable with **no proprietary deps** — which the all-OSS stack already satisfies. | Natural home for the privacy-focused audience. Watch the evolving Android "developer verification" policy, which could affect sideloading on certified devices. |
| **iOS sideloading** | Outside the EU's alternative marketplaces, **TestFlight** is the practical non-App-Store path (and is beta-only/expiring). | Plan for App Store as the real iOS channel; TestFlight for beta. |
| **GitHub Releases** | Direct APK downloads for Android. | Good secondary OSS channel. |

## 3. Technical risks (consolidated; details in [03](03-technical-feasibility.md)/[04](04-architecture-and-stack.md))

| Risk | Severity | Mitigation |
|---|---|---|
| `flutter_readium` (v0.1.0) too thin/unstable to drive external sync | **High** | **Phase 0 spike first**; fallbacks named (foliate-js WebView, native Readium/KMP) — [04 §5](04-architecture-and-stack.md) |
| Word-level neural highlighting harder than it looks | Med | Ship **sentence-level** in v1; word-level is a stretch goal — [03 §2](03-technical-feasibility.md) |
| Kokoro too slow/heavy on mid-range Android | Med | Piper is the default; Kokoro is an opt-in download gated to capable devices |
| Messy EPUB HTML → bad narration | Med | Use Readium's extraction; invest in content normalization; test on real-world/Calibre exports |
| Model size vs store limits & first-run UX | Med | Bundle one small voice; ODR (iOS) / download-on-run (Android); offline-first onboarding |
| Battery/thermal on long sessions | Low–Med | Piper bursts are short; look-ahead buffering; throttle-aware fallback to smaller model |
| Cross-platform maintenance burden (solo) | Med | Flutter single codebase; ruthless scope discipline (see §4) |

## 4. The real strategic risk: solo-maintainer sustainability

**Voice Dream Reader died because one person couldn't sustain it** ([02](02-market-competitive-analysis.md)). With no revenue, Narrarr must avoid the same fate by design:

- **Open-source from day one** so the project can outlive any single maintainer and accept contributors.
- **Ruthless scope discipline.** The biggest sustainability threat is feature creep. A focused v1 (EPUB + offline neural read-aloud + sentence highlighting) is far more maintainable than chasing Speechify's feature list.
- **Community from launch.** Announce to the audiences who *are* the users — r/Blind, dyslexia and accessibility communities, DAISY forums, Hacker News, F-Droid. Many will be technical contributors with personal stake.
- **Optional, no-strings funding** (compatible with "free forever"): GitHub Sponsors / Open Collective for hosting/donations transparency; potential grants or promotion from accessibility orgs (DAISY, Bookshare, RNIB, Benetech).
- **Boring, documented, testable architecture** ([04](04-architecture-and-stack.md)) so a contributor (or future-you) can pick it up.

## 5. Privacy & data

- **No accounts, no telemetry, no cloud** in v1. Books, positions, highlights, and voices stay on-device. This is both an ethical stance and the core marketing claim — so it must be *true and verifiable* (open source makes it auditable).
- The only network use is **optional voice downloads** from trusted hosts (GitHub Releases / Hugging Face); make it explicit and user-initiated.

---

*Previous: [04 · Architecture & Stack](04-architecture-and-stack.md) · Back to [index](README.md).*
