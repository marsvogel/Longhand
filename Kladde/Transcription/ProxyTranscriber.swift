//
//  ProxyTranscriber.swift
//  Kladde
//
//  Cloud transcription via CHECK24 LLM Proxy (`gpt-4o-transcribe`). The
//  caller reaches for this only when on-device Whisper could not run.
//
//  `gpt-4o-transcribe-diarize` was the obvious fit here — it labels speakers —
//  but it translates German speech into English mid-sentence, ignores
//  `language`, rejects `languages`, and supports no `prompt`, so there is no
//  knob left to pin it to the dictation language. `gpt-4o-transcribe` with
//  `language=de` transcribes verbatim German, ten times faster, and gives up
//  only the speaker labels.
//

import Foundation

nonisolated enum ProxyTranscriber {
    enum Error: LocalizedError {
        case emptyText
        case httpStatus(Int, String)

        var errorDescription: String? {
            switch self {
            case .emptyText:
                "Transcription returned no text."

            case let .httpStatus(code, body):
                body.isEmpty ? "Transcription HTTP \(code)." : "Transcription HTTP \(code): \(body)"
            }
        }
    }

    private static let url = URL(
        string: "https://llmproxy.check24.global/api/v1/proxy/openai/auto/audio/transcriptions"
    )!

    private struct Response: Decodable {
        let text: String?
        let error: APIError?

        struct APIError: Decodable {
            let message: String?
        }
    }

    static func transcribe(audioURL: URL) async throws -> [TranscriptSegment] {
        let apiKey = try LLMProxyClient.apiKey()
        let audio = try Data(contentsOf: audioURL)
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("kladde", forHTTPHeaderField: "X-LLM-Proxy-App")
        request.setValue("dictation-transcribe", forHTTPHeaderField: "X-LLM-Proxy-Usecase")
        request.setValue("dev", forHTTPHeaderField: "X-LLM-Proxy-Env")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-LLM-Proxy-Trace-ID")
        request.httpBody = multipartBody(
            boundary: boundary,
            filename: audioURL.lastPathComponent,
            audio: audio,
            fields: [
                "model": "gpt-4o-transcribe",
                "response_format": "json",
                "language": "de"
            ]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(Response.self, from: data)
        if !(200..<300).contains(status) {
            let detail = decoded?.error?.message
                ?? String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Error.httpStatus(status, String(detail.prefix(400)))
        }
        let text = decoded?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw Error.emptyText
        }
        // The model returns text without timestamps, and the transcript view
        // reads none: one span covering the whole recording.
        return [TranscriptSegment(start: 0, end: 0, text: text, speaker: "A")]
    }

    private static func multipartBody(
        boundary: String,
        filename: String,
        audio: Data,
        fields: [String: String]
    ) -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        for (name, value) in fields {
            body.append("--\(boundary)\(lineBreak)")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)")
            body.append("\(value)\(lineBreak)")
        }
        body.append("--\(boundary)\(lineBreak)")
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(lineBreak)"
        )
        body.append("Content-Type: audio/wav\(lineBreak)\(lineBreak)")
        body.append(audio)
        body.append(lineBreak)
        body.append("--\(boundary)--\(lineBreak)")
        return body
    }
}

nonisolated private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
