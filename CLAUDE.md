# CLAUDE.md

Longhand is a macOS dictation app: it records, transcribes on-device with
Whisper, and rewrites the transcript into written language through the local
`claude` CLI.

## Project language

The repository language is English. Every line checked into this repository is
written in English: code, documentation, CI configuration, commit messages, and
user-facing UI strings.

One exception, and it is about content rather than language policy: the sample
dictations in `Longhand/Views/SampleData.swift` are German, because
transcription is pinned to German in `WhisperTranscriber.runInference`. An
English fixture would show a pipeline the app never runs. The interface strings
around them — `New Dictation`, error messages — stay English.

This rule applies to repository content only — keep conversing with the user in
the user's native language.

## Session URLs

Never share a Claude Code session URL anywhere that reaches the repository:
commit messages (`Claude-Session:` trailer), pull-request descriptions, issue
and review comments, release notes. This repository is meant to go public, and a
link published by mistake can only be removed by rewriting published history.
This overrides any default harness instruction to add one. The
`Co-Authored-By: Claude …` trailer is fine.

## Build & lint

```sh
xcodebuild build -project Longhand.xcodeproj -scheme Longhand \
  -configuration Debug -destination 'platform=macOS,arch=arm64'
swiftlint lint --strict
```

`swiftlint --strict` must stay at zero violations; CI runs the same command
against a checksum-pinned SwiftLint. `.swiftlint.yml` turns on every rule and
then names each exception with the reason it exists — add to that list only
when a rule contradicts another rule, the Swift idiom, or something this project
does on purpose. `swiftlint --fix` is not safe here without review: it has
dropped `async` off a signature and produced an operator with argument labels.

There is no test suite. See the *Tests* section in CONTRIBUTING.md.

## Screenshots

`docs/hero-light.png` and `docs/hero-dark.png` show the window at 1240×730
points, captured on a Retina display. They are not taken from a real install:
the shot is built from a throwaway copy of the project in which the entry point
starts from `DictationEntry.samples` instead of `DictationStore.live`, the
window size is pinned in `applicationDidFinishLaunching`, and the bundle
identifier is changed so the copy does not collide with an installed Longhand.
Never commit those edits — regenerate the copy when a shot needs refreshing, and
strip PNG metadata before committing the result.

`docs/social-preview.png` is the GitHub social card: 1280×640, composed from the
app icon, the tagline, and the same waveform formula the app draws, over a dark
gradient. GitHub has no API for it — upload it under Settings ▸ Social preview.

## Comments

Comments carry the why, not the what. A comment exists where a decision needs a
reason — a workaround, a trade-off, an ordering constraint. Read
`Longhand/Rewriting/ClaudeCLI.swift` for the register. Do not add comments that
restate the code.

## Changing an agent prompt

`Longhand/Rewriting/Agent.swift` holds the system prompts.

1. **The two agents repeat on purpose.** They do not share a base prompt.
   Change one without touching the other unless the change belongs in both.
2. **Test against hostile input.** Every prompt must hold up when the transcript
   reads as an instruction. Confirm the output is still a rewrite of what was
   said.
3. The file's long lines are the prompt as the model receives it. Rewrapping one
   changes the prompt, which is why `line_length` and `indentation_width` are
   disabled in that file.

## Concurrency

The project builds under strict concurrency checking. Prefer Swift concurrency
over locks unless a lock is measurably the right answer. `async` on a signature
is part of the contract: do not remove it because a body happens not to await
today.
