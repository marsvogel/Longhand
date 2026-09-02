//
//  ClaudeWarmPool.swift
//  Longhand
//
//  Pre-spawned `claude` processes, one per agent, started when a recording
//  begins so the CLI's boot cost is paid while the user speaks. Each instance
//  is single-use, and any warm failure falls back to the cold ClaudeCLI path:
//  warming is an optimization, never a new failure mode.
//

import Foundation
import os

/// Holds one waiting `claude` process per agent between recording start and
/// transcript dispatch.
@MainActor
final class ClaudeWarmPool {
    /// Boot tasks of the pre-spawned, single-use processes. Spawning runs in
    /// a task so `prewarm()` returns immediately; `run` awaits it before the
    /// exchange.
    private var instances: [Agent.ID: Task<WarmProcess, any Error>] = [:]

    private static let logger = Logger(subsystem: "co.bischoff.Longhand", category: "ClaudeWarmPool")

    /// Spawns a waiting instance for every agent that has none, so calling
    /// this repeatedly per dictation cannot double-spawn.
    func prewarm() {
        for agent in Agent.all where instances[agent.id] == nil {
            instances[agent.id] = Task { try await WarmProcess.launch(agent: agent) }
        }
    }

    /// Feeds the transcript to the agent's warm instance and returns the
    /// transformed text, streaming text deltas to `onPartial` as they arrive.
    /// Instances are single-use: taken here, re-created only by the next
    /// `prewarm()`. Without an instance, or when anything about the warm
    /// exchange fails, the call transparently falls back to the cold
    /// `ClaudeCLI.run` — which does not stream — so only cold-path errors
    /// escape.
    func run(
        agent: Agent,
        transcript: String,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let boot = instances.removeValue(forKey: agent.id) else {
            return try await ClaudeCLI.run(agent: agent, transcript: transcript)
        }
        do {
            let process = try await boot.value
            let text = try await process.exchange(transcript: transcript, onPartial: onPartial)
            // Usually a no-op: the instance exits by itself after its result.
            process.terminate()
            return text
        } catch {
            Self.logger.warning(
                "Warm claude failed, falling back to cold run: \(error.localizedDescription, privacy: .public)"
            )
            (try? await boot.value)?.terminate()
            return try await ClaudeCLI.run(agent: agent, transcript: transcript)
        }
    }

    /// Terminates every waiting instance once its spawn attempt concludes.
    /// Safe to call at any time, with or without a preceding `prewarm()`.
    func invalidate() {
        for boot in instances.values {
            Task { (try? await boot.value)?.terminate() }
        }
        instances.removeAll()
    }
}

/// The spawned warm process with its pipe ends. NSTask and NSFileHandle are
/// used from one thread at a time here but are not marked Sendable.
nonisolated private struct WarmProcess: @unchecked Sendable {
    /// One line of `--input-format stream-json`: a single user message whose
    /// content is the agent's user message for the transcript. Schema
    /// validated against claude 2.1.217.
    private struct UserMessage: Encodable {
        struct Content: Encodable {
            let type = "text"
            let text: String
        }
        struct Message: Encodable {
            let role = "user"
            let content: [Content]
        }

        let type = "user"
        let message: Message

        init(text: String) {
            message = Message(content: [Content(text: text)])
        }
    }

    /// One event line of `--output-format stream-json`. Only the routing,
    /// result, and (with `--include-partial-messages`) text-delta fields are
    /// decoded; every other event shape is skipped. The result event carries
    /// the same fields as the cold path's envelope.
    private struct StreamEvent: Decodable {
        let type: String?
        let subtype: String?
        let isError: Bool?
        let result: String?
        let event: Payload?

        /// The nested Anthropic streaming event a `stream_event` line wraps.
        /// Only the `content_block_delta` → `text_delta` path is read.
        struct Payload: Decodable {
            let type: String?
            let delta: Delta?

            struct Delta: Decodable {
                let type: String?
                let text: String?
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type = "type"
            case subtype = "subtype"
            case result = "result"
            case event = "event"
            case isError = "is_error"
        }
    }

    /// The agent this instance was launched for; builds the user message.
    private let agent: Agent
    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle

    /// Spawns a hardened claude in stream-json mode. It boots and then blocks
    /// on stdin: 2.1.217 emits no ready event before the first user message,
    /// so a successful spawn is the only readiness signal there is.
    @concurrent
    static func launch(agent: Agent) async throws -> Self {
        let executable = try await ClaudeCLI.resolveExecutable()
        let process = Process()
        process.executableURL = executable
        // stream-json on both ends is mandatory (json output rejects
        // stream-json input) and stream-json output requires --verbose.
        // --include-partial-messages is what makes the CLI emit the
        // content_block_delta events the variant streams from; without it
        // only the whole-message and result events arrive.
        process.arguments = ClaudeCLI.baseArguments(for: agent) + [
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose"
        ]
        // Neutral working directory so no repository CLAUDE.md shapes the answer.
        process.currentDirectoryURL = AppLocations.supportDirectory
        process.environment = ClaudeCLI.environment
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        // Stderr is not part of the protocol; discard it so it can never fill.
        process.standardError = FileHandle.nullDevice
        try process.run()
        return Self(
            agent: agent,
            process: process,
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe.fileHandleForReading
        )
    }

    /// Sends the transcript as the single user message and returns the text
    /// of the final result event, applying the cold path's success checks and
    /// timeout, both counted from the moment the message is sent. Text deltas
    /// stream to `onPartial` as they arrive so the variant fills in live.
    func exchange(
        transcript: String,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard process.isRunning else {
            throw ClaudeCLI.Error.exitedWithFailure(code: process.terminationStatus, stderr: "")
        }
        var payload = try JSONEncoder().encode(UserMessage(text: agent.userMessage(for: transcript)))
        payload.append(UInt8(ascii: "\n"))

        let didTimeOut = OSAllocatedUnfairLock(initialState: false)
        let watchdog = Task { [self] in
            do {
                try await Task.sleep(for: ClaudeCLI.timeout)
            } catch {
                return // Cancelled because the exchange finished in time.
            }
            guard process.isRunning else {
                return
            }
            didTimeOut.withLock { $0 = true }
            terminate()
        }
        defer { watchdog.cancel() }

        // Closing stdin after the one message ends the conversation: the CLI
        // prints its result event and exits on its own.
        ClaudeCLI.feedStdin(payload, to: stdin)
        let event = await resultEvent(onPartial: onPartial)

        // A parsed result wins over a concurrent timeout: the process lingers
        // a moment after printing its result event, and a watchdog firing in
        // that window must not turn the success into a spurious failure.
        guard let event else {
            throw didTimeOut.withLock { $0 }
                ? ClaudeCLI.Error.timedOut
                : ClaudeCLI.Error.undecodableOutput
        }
        return try ClaudeCLI.finalText(subtype: event.subtype, isError: event.isError, result: event.result)
    }

    /// SIGTERM now, SIGKILL five seconds later if the process ignores it.
    func terminate() {
        guard process.isRunning else {
            return
        }
        process.terminate()
        Task.detached { [self] in
            try? await Task.sleep(for: .seconds(5))
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    /// Reads stdout line-wise until the result event, or nil at EOF. Text
    /// deltas are accumulated and handed to `onPartial` — throttled to ~25 Hz
    /// so a long variant does not flood the main actor — while everything else
    /// is skipped. The blocking chunk reads run on a GCD thread, not the
    /// cooperative pool.
    private func resultEvent(
        onPartial: @escaping @Sendable (String) -> Void
    ) async -> StreamEvent? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let decoder = JSONDecoder()
                var partial = ""
                var lastEmit = ContinuousClock.now
                let minInterval = Duration.milliseconds(40)

                // Returns the result event to finish on, or nil to keep
                // reading; text-delta lines fold into `partial` as a side
                // effect and stream out.
                func handle(_ line: Data) -> StreamEvent? {
                    guard let event = try? decoder.decode(StreamEvent.self, from: line) else {
                        return nil
                    }
                    if event.type == "result" {
                        return event
                    }
                    if event.type == "stream_event",
                       event.event?.type == "content_block_delta",
                       event.event?.delta?.type == "text_delta",
                       let text = event.event?.delta?.text {
                        partial += text
                        let now = ContinuousClock.now
                        if now - lastEmit >= minInterval {
                            lastEmit = now
                            onPartial(partial)
                        }
                    }
                    return nil
                }
                var buffer = Data()
                while let chunk = try? stdout.read(upToCount: 65_536), !chunk.isEmpty {
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let line = buffer.subdata(in: buffer.startIndex..<newline)
                        buffer.removeSubrange(buffer.startIndex...newline)
                        if let event = handle(line) {
                            continuation.resume(returning: event)
                            return
                        }
                    }
                }
                // A final line can arrive without a trailing newline at EOF.
                continuation.resume(returning: handle(buffer))
            }
        }
    }
}
