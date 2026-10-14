# Contributing to NotarIA

Thanks for considering a contribution. This is a small, local-first macOS
app — the bar for merging is "keeps privacy guarantees intact and keeps the
test suite green," not "adds the most features."

## Before you start

- Open an issue describing the bug or feature before writing a large patch,
  so we can agree on the approach.
- Changes that add a network call, a new third-party dependency, or a way
  for audio/transcripts to leave the Mac need extra scrutiny — explain the
  privacy trade-off in the issue/PR description.

## Development setup

- macOS 14+, Xcode 15+ (the full app, not just the Command Line Tools).
- `./scripts/build.sh` to build, `./scripts/test.sh` to run the headless
  test suite. Both must stay green.
- No comments in code unless strictly necessary to explain a non-obvious
  decision — prefer clear naming and small functions.
- No GUI/audio/focus-stealing smoke tests in the automated suite; those live
  outside CI by design (see `docs/ARCHITECTURE.md`).

## Pull requests

- Keep PRs focused on one change.
- Add or update tests for any logic change; `scripts/test.sh` must pass.
- Describe what changed and why in the PR description, not just what.
- No AI-generated boilerplate commit messages — write what the change does
  and why, in your own words.

## Reporting bugs

Open a GitHub issue with: macOS version, Mac model/chip, steps to reproduce,
and the relevant CLI output (NotarIA never needs you to share audio or
transcript content to debug a bug report — redact it if it's ever requested).

For security issues, see [SECURITY.md](./SECURITY.md) instead of opening a
public issue.
