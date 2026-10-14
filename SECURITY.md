# Security Policy

NotarIA is a local-first macOS app: by design, audio and transcripts never
leave your Mac, and the only outbound call is the optional enhance step to
Claude (CLI or API), which sends text only, and only if you opt in.

## Reporting a vulnerability

Please report security issues privately through
[GitHub Security Advisories](../../security/advisories/new) for this
repository, instead of opening a public issue. This lets us assess the
report and ship a fix before any details become public.

Please include:

- A description of the vulnerability and its potential impact.
- Steps to reproduce (a minimal repro is ideal).
- The macOS version and chip (Intel/Apple Silicon) you tested on.

We'll acknowledge reports within a few days and keep you updated as we
investigate and fix the issue.

## Scope

In scope: the `aria-capture` binary and its Swift sources, the build
scripts, and how secrets (the optional Anthropic API key, the local cache
encryption key) are stored and used.

Out of scope: the vendored `Vendor/whisper.cpp` — please report issues in
that library upstream at
[ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp).

## Supported versions

NotarIA does not yet have tagged releases; security fixes land on the
default branch. Once releases exist, this section will list which versions
receive fixes.
