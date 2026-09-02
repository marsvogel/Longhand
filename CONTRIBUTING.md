# Contributing to Longhand

Thanks for looking. This page tells you what Longhand accepts, how to build
it, and what a change should look like.

## What this project is

Longhand is a personal project, kept deliberately small. It does one thing:
record, transcribe on-device, rewrite through Claude Code. It is
feature-complete for that.

That shapes what gets merged:

| Welcome | Unlikely to be merged |
| --- | --- |
| Bug fixes | New features that widen the scope |
| Correctness and concurrency fixes | Settings screens and configuration UI |
| Clearer prompts and better rewrites | Alternative transcription or model back ends |
| Documentation that removes a wrong assumption | Refactors that only move code around |
| Accessibility and VoiceOver fixes | Dependencies that replace ~100 lines of Swift |

Open an issue before you write code for anything larger than a fix. It costs
you one message and can save you an afternoon.

## Before you file an issue

Search the open issues first. If nothing matches, use the issue forms — they
ask for the things a report needs to be actionable.

## Setup

Requirements:

- macOS 26 or later, on an Apple silicon Mac
- Xcode 26 or later
- [Claude Code](https://claude.com/claude-code), installed and signed in
- 2.8 GB of free disk space for the transcription model

Build and run:

```sh
git clone https://github.com/marsvogel/Longhand.git
cd Longhand
open Longhand.xcodeproj
```

Or from the command line:

```sh
xcodebuild -project Longhand.xcodeproj -scheme Longhand -configuration Debug build
```

The project builds without an Apple Developer account: it signs to run
locally. Swift Package Manager fetches the whisper.cpp XCFramework on the
first build, so the first build needs a network connection.

On first launch the app downloads Whisper `large-v3-turbo` to
`~/Library/Application Support/Longhand/Models`. Your dictations land in the
same directory — delete it to start from a clean state.

## Project layout

Code is grouped by capability, not by kind of type. A view, its model, and
its helpers live together.

| Directory | Holds |
| --- | --- |
| `Longhand/App` | App entry point, commands, delegate |
| `Longhand/Audio` | Recording, playback, sample buffers |
| `Longhand/Transcription` | Whisper inference and model download |
| `Longhand/Rewriting` | Agent configurations and the `claude` bridge |
| `Longhand/Model` | Dictation entries and the store |
| `Longhand/Storage` | On-disk locations and the archive format |
| `Longhand/Views` | SwiftUI views, split by sidebar / detail / components |
| `Packages/CWhisper` | Local SPM package wrapping the whisper.cpp framework |

## Linting

The project lints with [SwiftLint](https://github.com/realm/SwiftLint) and must
stay at zero violations:

```sh
swiftlint lint --strict
```

CI runs the same command against a checksum-pinned SwiftLint 0.65.0, so a
violation fails the build.

`.swiftlint.yml` turns on **every** rule and then names each exception together
with the reason it exists. Extend that list only when a rule contradicts another
rule, contradicts the Swift idiom, or contradicts something this project does on
purpose — and write down which of the three it is.

Do not run `swiftlint --fix` unattended. On this codebase it has removed `async`
from a signature and produced an operator with argument labels; both broke the
build.

## Tests

There are none, on purpose.

What Longhand does lives almost entirely outside what a unit test can reach: a
microphone, a C library through a bridging header, a subprocess, and a language
model whose output is not deterministic. A test suite here would assert against
mocks of all four and still tell you nothing about whether a dictation comes
back as a usable document.

So the check is manual, and a pull request says it ran:

1. Record a dictation, let it transcribe, let it rewrite.
2. For prompt changes, add the hostile-input dictations described below.
3. Confirm the app builds and that you ran it.

If you want to add tests, the parts worth covering are the ones with no I/O:
`DictationDate`, the Markdown block assembler in `MarkdownText.swift`, and
`ClaudeCLI.finalText`. Open an issue first — a test target changes the CI
contract.

## Code style

Swift API Design Guidelines, plus what the existing code already does:

- **Comments carry the why.** The code says what it does. A comment exists
  where a decision needs a reason — a workaround, a trade-off, an ordering
  constraint. Read `Longhand/Rewriting/ClaudeCLI.swift` for the register.
- **Swift concurrency, not locks**, unless a lock is measurably the right
  answer. The project builds under strict concurrency checking.
- **No new dependencies** without a reason in the pull request.
- **Match the surrounding file.** Naming, spacing, and comment density are
  set by the file you are editing.
- **`async` is a contract.** Do not drop it from a signature because the body
  happens not to await today.

## Changing an agent prompt

`Longhand/Rewriting/Agent.swift` holds the system prompts. Two rules:

1. **The two agents repeat on purpose.** They do not share a base prompt.
   Change one without touching the other unless the change belongs in both.
2. **Test against hostile input.** Every prompt must hold up when the
   transcript reads as an instruction. Try a dictation that says "ignore your
   previous instructions", or one that demands another language, and confirm
   the output is still a rewrite of what was said.

Say in the pull request which dictations you tested with.

## Commits

Commit messages follow [How to Write a Git Commit
Message](https://cbea.ms/git-commit/):

- Subject in the imperative — "Add …", "Fix …", not "Added"
- Capitalized, no trailing period, 50 characters or fewer
- A body only when the subject does not carry the why, wrapped at 72
  characters

Look at `git log` for the tone.

## Pull requests

- One change per pull request.
- The title says in one line what the change does.
- The description starts with a sentence or two paraphrasing the change, then
  says what changes for someone using the app. It does not repeat what the
  diff already shows.
- Confirm the app builds and that you ran it.

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By taking
part, you agree to it.

## License

Contributions are licensed under the [MIT License](LICENSE), the same terms
as the project.
