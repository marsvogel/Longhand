//
//  ClaudeCLI.swift
//  Longhand
//
//  Bridge to the user's local `claude` command-line tool, which rewrites
//  transcripts. The binary location varies by install method, so the path
//  is resolved at runtime with a login-shell lookup as the last resort.
//

import Foundation
import os

/// Runs the local `claude` CLI with an instruction and stdin input.
nonisolated enum ClaudeCLI {
    enum Error: LocalizedError {
        case emptyResult
        case executableNotFound
        case exitedWithFailure(code:
            Int32, stderr: String)

        case reportedFailure(subtype:
            String, message: String)

        case timedOut
        case undecodableOutput

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                "The claude command-line tool was not found. Install Claude Code and try again."

            case .timedOut:
                "claude did not finish within 180 seconds."

            case let .exitedWithFailure(code, stderr):
                stderr.isEmpty ? "claude exited with code \(code)." : "claude exited with code \(code): \(stderr)"

            case .undecodableOutput:
                "claude did not return the expected JSON result envelope."

            case let .reportedFailure(subtype, message):
                "claude reported a failure: \(message.isEmpty ? subtype : message)"

            case .emptyResult:
                "claude returned an empty result."
            }
        }
    }

    /// The single-result envelope `claude -p --output-format json` prints on
    /// stdout. Only the fields we act on are decoded; unknown fields are
    /// ignored. Validated against claude 2.1.217, where an API failure keeps
    /// subtype "success" but sets is_error and puts the message into result.
    private struct ResultEnvelope: Decodable {
        let subtype: String?
        let isError: Bool?
        let result: String?

        private enum CodingKeys: String, CodingKey {
            case subtype = "subtype"
            case isError = "is_error"
            case result = "result"
        }
    }

    static let timeout: Duration = .seconds(180)

    /// Environment for claude processes. Locale variables nudge the model
    /// toward the OS language; the output language must follow the transcript
    /// alone.
    static var environment: [String: String] {
        ProcessInfo.processInfo.environment.filter { item in
            item.key != "LANG" && !item.key.hasPrefix("LC_")
        }
    }

    private static let executableResolution =
        OSAllocatedUnfairLock<Task<URL, any Swift.Error>?>(initialState: nil)

    /// Resolves the claude binary once; concurrent first callers share a
    /// single lookup instead of racing three login-shell fallbacks.
    static func resolveExecutable() async throws -> URL {
        let task = executableResolution.withLock { state in
            if let existing = state {
                return existing
            }
            let created = Task.detached { try findExecutable() }
            state = created
            return created
        }
        do {
            return try await task.value
        } catch {
            // Never cache a failure: the user may install claude and retry.
            executableResolution.withLock { $0 = nil }
            throw error
        }
    }

    /// Pipes the agent's user message for `transcript` to a locked-down
    /// `claude -p` and returns the trimmed `result` field of its JSON output
    /// envelope.
    @concurrent
    static func run(agent: Agent, transcript: String) async throws -> String {
        let executable = try await resolveExecutable()

        let process = Process()
        process.executableURL = executable
        process.arguments = baseArguments(for: agent) + [
            "--output-format", "json"
        ]
        // Neutral working directory so no repository CLAUDE.md shapes the answer.
        process.currentDirectoryURL = AppLocations.supportDirectory
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Both output pipes must be drained while the process runs; waiting
        // for exit first deadlocks once a pipe buffer fills.
        async let stdoutData = drain(UncheckedSendable(value: stdoutPipe.fileHandleForReading))
        async let stderrData = drain(UncheckedSendable(value: stderrPipe.fileHandleForReading))

        let processBox = UncheckedSendable(value: process)
        let didTimeOut = OSAllocatedUnfairLock(initialState: false)
        let watchdog = Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return // Cancelled because the process finished in time.
            }
            guard processBox.value.isRunning else {
                return
            }
            didTimeOut.withLock { $0 = true }
            processBox.value.terminate()
            // Escalate in case the process ignores SIGTERM.
            try? await Task.sleep(for: .seconds(5))
            if processBox.value.isRunning {
                kill(processBox.value.processIdentifier, SIGKILL)
            }
        }
        defer { watchdog.cancel() }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Swift.Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                // Cold stdin stays plain text: it is already a pure data
                // channel, and claude 2.1.217 only accepts stream-json input
                // when the output format is stream-json too — that pairing
                // lives in ClaudeWarmPool.
                feedStdin(Data(agent.userMessage(for: transcript).utf8), to: stdinPipe.fileHandleForWriting)
            }
        } catch {
            // Never launched: close our pipe ends so the drain tasks reach EOF.
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            try? stdinPipe.fileHandleForReading.close()
            throw error
        }

        let output = await stdoutData
        let errorOutput = String(decoding: await stderrData, as: UTF8.self)

        if didTimeOut.withLock({ $0 }) {
            throw Error.timedOut
        }
        guard process.terminationStatus == 0 else {
            let stderrText = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            // Execution failures (e.g. an API error) exit non-zero with an
            // empty stderr but still print the envelope, carrying the message
            // in its result field; surface that instead of a bare exit code.
            if stderrText.isEmpty,
               let envelope = try? JSONDecoder().decode(ResultEnvelope.self, from: output),
               envelope.isError == true {
                throw Error.reportedFailure(
                    subtype: envelope.subtype ?? "unknown",
                    message: envelope.result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                )
            }
            throw Error.exitedWithFailure(code: process.terminationStatus, stderr: stderrText)
        }
        return try parseResult(from: output)
    }

    /// The claude arguments common to the cold and warm paths for `agent`;
    /// each path appends its own output-format flags. The system prompt travels
    /// as `--system-prompt` while the transcript arrives on stdin, inside the
    /// agent's user message (`Agent.userMessage(for:)`), so instruction-like
    /// text inside a transcript stays data instead of outranking the prompt.
    static func baseArguments(for agent: Agent) -> [String] {
        [
            "-p",
            "--system-prompt", agent.systemPrompt,
            "--model", agent.model,
            "--effort", agent.effort,
            // Lock claude down to a pure text transformation of untrusted
            // input: no built-in tools, no MCP servers, no slash commands, no
            // user settings or customizations, and no session left on disk.
            "--tools", "",
            "--strict-mcp-config",
            "--disable-slash-commands",
            "--safe-mode",
            "--setting-sources", "",
            "--no-session-persistence"
        ]
    }

    /// Extracts the transformed text from the JSON result envelope, treating
    /// undecodable output as a failure.
    private static func parseResult(from output: Data) throws -> String {
        guard let envelope = try? JSONDecoder().decode(ResultEnvelope.self, from: output) else {
            throw Error.undecodableOutput
        }
        return try finalText(subtype: envelope.subtype, isError: envelope.isError, result: envelope.result)
    }

    /// The success checks shared by both paths — cold result envelope and warm
    /// result event carry the same fields: a reported error or an empty result
    /// is a failure, anything else is the transformed text.
    static func finalText(subtype: String?, isError: Bool?, result: String?) throws -> String {
        guard isError != true, subtype == "success" else {
            throw Error.reportedFailure(
                subtype: subtype ?? "unknown",
                message: result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        let text = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw Error.emptyResult
        }
        return text
    }

    // MARK: - Executable resolution

    private static func findExecutable() throws -> URL {
        let fileManager = FileManager.default
        let candidates = [
            fileManager.homeDirectoryForCurrentUser.appending(path: ".local/bin/claude"),
            URL(filePath: "/opt/homebrew/bin/claude"),
            URL(filePath: "/usr/local/bin/claude")
        ]
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        // Last resort: a login shell sees the user's full PATH.
        if let path = loginShellLookup(), fileManager.isExecutableFile(atPath: path) {
            return URL(filePath: path)
        }
        throw Error.executableNotFound
    }

    private static func loginShellLookup() -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // One-line output stays far below the pipe buffer, so reading after
        // exit cannot deadlock.
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try? stdout.fileHandleForReading.readToEnd()
        else { return nil }
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    // MARK: - Pipe handling

    /// Reads a pipe to EOF in chunks. `read(upToCount:)` blocks until data
    /// arrives, so the loop runs on a GCD thread, not the cooperative pool.
    private static func drain(_ handleBox: UncheckedSendable<FileHandle>) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var data = Data()
                while let chunk = try? handleBox.value.read(upToCount: 65_536), !chunk.isEmpty {
                    data.append(chunk)
                }
                continuation.resume(returning: data)
            }
        }
    }

    /// Writes `input` to the handle and closes it. Writing can block on a full
    /// pipe buffer, so it runs on a GCD thread instead of the cooperative
    /// pool. F_SETNOSIGPIPE prevents a fatal SIGPIPE if the process exits
    /// before consuming its input.
    static func feedStdin(_ input: Data, to handle: FileHandle) {
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        let handleBox = UncheckedSendable(value: handle)
        DispatchQueue.global(qos: .userInitiated).async {
            try? handleBox.value.write(contentsOf: input)
            try? handleBox.value.close()
        }
    }
}

/// NSTask and NSFileHandle are safe to use from another thread here but are
/// not marked Sendable.
nonisolated private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}
