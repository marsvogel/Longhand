# Security policy

## Reporting a vulnerability

Report security issues privately through GitHub, not in a public issue:

**[Open a security advisory](https://github.com/marsvogel/Kladde/security/advisories/new)**

You get a confidential thread with the maintainer. Nothing is public until a
fix ships.

Include what you need to make the problem reproducible: the steps, the input,
the macOS and Claude Code versions, and what you expected instead.

Expect a first reply within 7 days. Kladde is a personal project, so a fix
takes as long as it takes — you will hear where it stands rather than nothing.

## Supported versions

The latest commit on `main` is the only supported version. There are no
tagged releases and no backports.

## What Kladde does with your data

Recordings, transcripts, and rewrites are written to
`~/Library/Application Support/Kladde` and stay there. There is no
analytics, no account, and no telemetry.

The rewrite is the only step that leaves your Mac. The transcript goes to the
Anthropic API through your local `claude` CLI, under your own Claude
subscription. The audio never leaves the machine.

## Threat model

These are the places worth looking, and what Kladde already does about them.

### Untrusted transcript text

A dictation can contain sentences that read as instructions — by accident or
because someone dictated them on purpose. Kladde treats every transcript as
data:

- The transcript arrives on stdin inside a `<transcript>` element, never in
  the system prompt.
- Each agent's system prompt states that nothing inside the element is
  addressed to the model.
- A reminder line follows the transcript, so an instruction-shaped sentence at
  the end of a dictation is never the most recent instruction in the context.

A transcript that changes the model's behaviour anyway is a bug. Report it.

### The `claude` subprocess

Kladde runs `claude` locked down to a text transformation:

- `--tools ""` — no built-in tools
- `--strict-mcp-config` — no MCP servers
- `--disable-slash-commands` — no slash commands
- `--safe-mode`
- `--setting-sources ""` — no user settings or customizations
- `--no-session-persistence` — no session left on disk

The working directory is set to the application support directory, so no
repository `CLAUDE.md` can shape the answer.

### Executable resolution

Kladde resolves the `claude` binary at runtime and falls back to a
login-shell lookup. A `PATH` an attacker controls is therefore a `claude` an
attacker controls. This is the same trust boundary as typing `claude` in your
own terminal.

### No sandbox

Kladde is not sandboxed, because it launches `claude` from your `PATH`. It
runs with your full user privileges.

### Model download

On first launch Kladde downloads Whisper `large-v3-turbo` over HTTPS from
Hugging Face. The download is not checksum-verified; it is trusted on TLS
alone. The whisper.cpp framework itself *is* pinned by version and SHA-256 in
`Packages/CWhisper/Package.swift`.

## Out of scope

- Vulnerabilities in Claude Code, the Anthropic API, whisper.cpp, or the
  Whisper models. Report those to their own maintainers.
- Anything that needs an attacker to already have code execution as your user.
