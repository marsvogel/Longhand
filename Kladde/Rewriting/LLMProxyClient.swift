//
//  LLMProxyClient.swift
//  Kladde
//
//  CHECK24 LLM Proxy rewrite backend (Anthropic Messages API).
//  API key: ~/Library/Application Support/Kladde/llm-proxy-api-key
//  (one line, the raw key) — or env LLM_PROXY_API_KEY.
//

import Foundation

nonisolated enum LLMProxyClient {
    enum Error: LocalizedError {
        case emptyResult
        case httpStatus(Int, String)
        case missingAPIKey
        case undecodableOutput

        var errorDescription: String? {
            switch self {
            case .emptyResult:
                "LLM Proxy returned an empty result."

            case let .httpStatus(code, body):
                body.isEmpty ? "LLM Proxy HTTP \(code)." : "LLM Proxy HTTP \(code): \(body)"

            case .missingAPIKey:
                """
                No LLM Proxy API key. Put it in \(AppLocations.llmProxyAPIKeyFile.path) \
                (one line) or set LLM_PROXY_API_KEY.
                """

            case .undecodableOutput:
                "LLM Proxy returned an unexpected response."
            }
        }
    }

    // ponytail: Anthropic path required for Claude models; OpenAI /auto returns model_not_found
    private static let baseURL = URL(string: "https://llmproxy.check24.global/api/v1/proxy/anthropic/auto/v1/messages")!

    /// The rewrite of a long dictation runs to roughly the length of the
    /// transcript, and the budget covers the whole response — an exhausted one
    /// returns a truncated document, or none at all. A generous ceiling costs
    /// nothing: only the tokens actually produced are billed.
    private static let maxTokens = 32_000

    static var hasAPIKey: Bool {
        (try? apiKey()) != nil
    }

    private struct MessagesRequest: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]
        let thinking = Thinking()

        struct Message: Encodable {
            let role: String
            let content: String
        }

        /// This model thinks adaptively and decides for itself how much, and on
        /// a prompt this size it decided to spend the entire token budget on it:
        /// 8191 thinking tokens, zero text, which arrived here as
        /// `Error.emptyResult`. Nothing about a rewrite needs deliberation
        /// ahead of the answer, so it is off.
        struct Thinking: Encodable {
            let type = "disabled"
        }

        private enum CodingKeys: String, CodingKey {
            case maxTokens = "max_tokens"
            case messages = "messages"
            case model = "model"
            case system = "system"
            case thinking = "thinking"
        }
    }

    private struct MessagesResponse: Decodable {
        struct Block: Decodable {
            let type: String?
            let text: String?
        }

        let content: [Block]?
        let error: APIError?

        struct APIError: Decodable {
            let message: String?
        }
    }

    static func run(agent: Agent, transcript: String) async throws -> String {
        let apiKey = try apiKey()
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("kladde", forHTTPHeaderField: "X-LLM-Proxy-App")
        request.setValue("dictation-rewrite", forHTTPHeaderField: "X-LLM-Proxy-Usecase")
        request.setValue("dev", forHTTPHeaderField: "X-LLM-Proxy-Env")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-LLM-Proxy-Trace-ID")
        request.httpBody = try JSONEncoder().encode(
            MessagesRequest(
                model: agent.model,
                maxTokens: Self.maxTokens,
                system: agent.systemPrompt,
                messages: [.init(role: "user", content: agent.userMessage(for: transcript))]
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(MessagesResponse.self, from: data)
        if !(200..<300).contains(status) {
            let detail = decoded?.error?.message
                ?? String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Error.httpStatus(status, String(detail.prefix(400)))
        }
        let text = decoded?.content?
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard decoded?.content != nil else {
            throw Error.undecodableOutput
        }
        guard !text.isEmpty else {
            throw Error.emptyResult
        }
        return text
    }

    static func apiKey() throws -> String {
        if let env = ProcessInfo.processInfo.environment["LLM_PROXY_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        let file = AppLocations.llmProxyAPIKeyFile
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else {
            throw Error.missingAPIKey
        }
        let key = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { String($0) }?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            ?? ""
        guard !key.isEmpty else {
            throw Error.missingAPIKey
        }
        return key
    }
}
