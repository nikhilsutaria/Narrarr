# Security Policy

Narrarr is a fully offline reading app: there are no accounts, no servers, and your books and reading activity never leave your phone. That keeps the attack surface small — but security issues are still possible (EPUB parsing, voice-model downloads, local storage), and we want to hear about them.

## Supported versions

Only the latest release receives security fixes.

| Version | Supported |
| ------- | --------- |
| 1.0.x (latest release) | ✅ |
| Older versions | ❌ |

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, report them privately via **GitHub's private vulnerability reporting**:

1. Go to the repository's **[Security tab → Report a vulnerability](https://github.com/nikhilsutaria/Narrarr/security/advisories/new)**.
2. Fill in the details (see below) and submit.

Please include as much of the following as you can:

- The type of issue (e.g. malformed-EPUB parsing crash, path traversal during import/extraction, download integrity bypass)
- Steps to reproduce, ideally with a proof-of-concept file or minimal repro
- The app version (or commit) and Android version/device you tested on
- The impact you believe it has

### What to expect

Narrarr is maintained by a solo developer in spare time, so response times are best-effort:

- **Acknowledgement** of your report within **7 days**
- A fix or mitigation plan communicated within **30 days** for confirmed issues
- Credit in the release notes (if you'd like it) once a fix ships

Please give us a reasonable window to ship a fix before disclosing publicly.

## Scope

Things we especially care about:

- **EPUB handling** — crashes or code execution from malicious/malformed EPUBs, zip-slip / path traversal during import or extraction
- **Voice downloads** — anything that bypasses the checksum verification of downloaded voice models, or lets a tampered model be installed
- **Local data** — library database or imported books being readable/writable by other apps in ways they shouldn't be
- **Privacy regressions** — any network traffic beyond the documented one-time voice downloads

Out of scope:

- Vulnerabilities in upstream dependencies (Flutter, sherpa-onnx, Piper, Readium, etc.) with no Narrarr-specific impact — please report those upstream (though a heads-up here is welcome)
- Anything requiring a rooted device or physical access with the screen unlocked
- Requests to add or bypass DRM — Narrarr only opens DRM-free EPUBs you own and will not circumvent DRM

Thank you for helping keep Narrarr's readers safe. 🙏
