---
disclosure-default: ai-generated
tools:
  - Claude Code
models:
  - Anthropic Claude
providers:
  - Anthropic
  - OpenAI
scope: repository
last-updated: 2026-09-02
---

# AI Disclosure

Longhand is developed with AI coding tools. This document discloses how AI is
involved, which tooling is used, and what human oversight applies. It describes
provenance only — it makes no statement about code quality or security.

## Default disclosure level

**`ai-generated`** — the code in this repository is, by default, AI-generated
with human prompting and review. The vocabulary is adapted from the
[ai-disclosure convention](https://github.com/ggfevans/ai-disclosure) (aligned
with the W3C AI Content Disclosure vocabulary):

| Level | Meaning |
|---|---|
| `none` | No AI involvement. |
| `ai-assisted` | Human-authored; AI edited, refactored, or filled in boilerplate. |
| `ai-generated` | AI-generated with human prompting and review. |
| `autonomous` | AI-generated without substantial human review. |

## Tools and models

- **Claude Code** (Anthropic), running Anthropic Claude models. The app itself
  was generated with Claude Code; its tooling, CI, and documentation are as well.
- **The app icon** (`Longhand/AppIcon.icon/Assets/icon.png`) was generated with
  OpenAI's `gpt-image`. It arrived carrying C2PA Content Credentials that named
  the generator; those were stripped along with every other metadata chunk when
  the file was recompressed, so this document is now the only record of where it
  came from.

Note that this is separate from what the app *does* at runtime: Longhand sends
each transcript to the Anthropic API through your own local `claude` CLI. The
[README](README.md#privacy) and [SECURITY.md](SECURITY.md) describe that path.

## Human review

- The maintainer directs the work through prompts and reviews changes at the
  pull-request level; changes to `main` land through pull requests.
- CI runs on every pull request and push to `main`
  (`.github/workflows/build.yml`): SwiftLint `--strict` (pinned and
  checksum-verified) and a Release build.
- There is no test suite. Longhand is a small app whose behaviour lives in
  audio capture, a C library, and a subprocess; [CONTRIBUTING.md](CONTRIBUTING.md#tests)
  explains what is checked by hand instead.
- [@marsvogel](https://github.com/marsvogel) is the sole maintainer and code
  owner (`.github/CODEOWNERS`).

## Copyright

AI is used as a tool; it is not claimed as an author. The human maintainer
([@marsvogel](https://github.com/marsvogel)) holds the copyright and licenses the
project under the [MIT License](LICENSE).

## Machine-readable disclosure

- **Commit trailer:** commits with AI involvement carry a `Co-Authored-By:`
  trailer with the address `noreply@anthropic.com`; the name part may include the
  model, e.g. `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` — match on
  the email address.

## Scope and non-claims

- This disclosure applies to this repository only.
- The level describes **provenance, not quality** — not correctness, security, or
  fitness for purpose.
- A missing tag means `unknown`, not `none`.

---

Last updated: 2026-09-02 · Maintainer: [@marsvogel](https://github.com/marsvogel)
