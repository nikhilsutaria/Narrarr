# Narrarr — Research & Validation Docs

*Pre-build research phase. Last updated 2026-06-24.*

This folder is the **decision-ready research** behind Narrarr, produced *before* writing any app code. It exists to answer one question honestly: **should this be built, and if so, how?**

> **Narrarr** — a free, open-source, cross-platform (iOS + Android) app that turns the DRM-free EPUBs you already own into a Kindle-style *immersion reading* experience: read aloud by an **on-device, offline AI voice** while the text **highlights in sync**. No subscriptions, no accounts, no data leaving your phone.

## Executive verdict

**Build it — it's feasible for a solo developer, and the niche is genuinely open.** Caveats that shape the build:

- ✅ **The gap is real.** No shipping app combines personal EPUBs + on-device *neural* TTS + synced highlighting + free + open-source + cross-platform. (Closest misses: Readest, and the discontinued Voice Dream Reader.)
- ✅ **The stack exists as mature OSS.** Flutter + **sherpa-onnx** (Piper voice) + **Readium** + `just_audio`. The work is integration, not invention. (~3–5 months full-time for a polished v1.)
- ⚠️ **Be honest about highlighting.** Neural on-device TTS gives **sentence-level** sync reliably; word-perfect "karaoke" is a *later* stretch goal, not v1.
- ⚠️ **One thing must be de-risked first.** Whether `flutter_readium` (currently **v0.1.0**) can render + highlight under an external neural-TTS pipeline → a **1–2 week Phase 0 spike** decides the stack, with named fallbacks if it fails.
- ✅ **Legally and commercially clear.** On-device TTS of owned DRM-free books is legitimate; costs are tiny ($99/yr Apple, $25 once Google, F-Droid free). The real risk is **solo-maintainer sustainability** — answered by being open-source and scope-disciplined.

## Confirmed direction

| Decision | Choice |
|---|---|
| Business model | Free & open-source forever (no monetization) |
| Immersion depth | Synced highlighting — **sentence-level first**, word-level later |
| Platforms | Both iOS & Android (cross-platform) |
| Builder | Solo developer |

## Read in this order

1. **[01 · Product Vision & Strategy](01-product-vision.md)** — the problem, why now, target users, positioning, principles, success criteria, non-goals.
2. **[02 · Market & Competitive Analysis](02-market-competitive-analysis.md)** — the competitor matrix, the precise unfilled gap, the Voice Dream Reader demand signal.
3. **[03 · Technical Feasibility](03-technical-feasibility.md)** — on-device TTS engine survey, the synced-highlighting deep dive, the honest verdict, traps & showstoppers.
4. **[04 · Architecture & Tech Stack](04-architecture-and-stack.md)** — the recommended stack, end-to-end data flow, reusable OSS, and the **validation spike**.
5. **[05 · Risks, Legal & Compliance](05-risks-legal-compliance.md)** — legality, app-store realities, the risk register, and OSS sustainability.
6. **[06 · MVP Scope & Roadmap](06-mvp-scope-and-roadmap.md)** — what v1 is/isn't, the phased plan (Phase 0 = spike), and the Definition of Done.
- **[sources.md](sources.md)** — full bibliography with confidence ratings.

## What happens next

This is a research deliverable, not code. The intended next steps:
1. **You review these docs** and confirm they match your intent (or request changes).
2. If green-lit, **run the Phase 0 validation spike** ([06](06-mvp-scope-and-roadmap.md)) — the cheapest way to confirm the stack before real investment.
3. Then proceed through the roadmap.

> **Update (2026-06-24): a proof-of-concept was built and validated** — see **[../poc/](../poc/README.md)**. It proved the core loop (EPUB → offline neural voice → synced sentence highlight) on Android and pre-solved much of the neural-playback work, but on a custom reader + `audioplayers` rather than `flutter_readium` + `just_audio`. The genuine Phase 0 question (`flutter_readium` under the neural pipeline, on real devices) **remains open**. Read the POC findings before starting real development.

*Method note: research was conducted via parallel web-research agents plus targeted first-hand verification of the most load-bearing claims; confidence is flagged per-source in [sources.md](sources.md).*
