//
//  AIService.swift
//  AIHelper — macOS AI writing assistant
//


import Foundation

// MARK: - Provider config stored in UserDefaults

enum AIProvider: String, CaseIterable, Codable, Sendable {
    case openAI = "OpenAI"
    case ollama = "Ollama"

    nonisolated var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.groq.com/openai/v1"
        case .ollama: return "http://localhost:11434/v1"
        }
    }

    nonisolated var defaultModel: String {
        switch self {
        case .openAI: return "meta-llama/llama-4-scout-17b-16e-instruct"
        case .ollama: return "gemma4:e4b"
        }
    }

    nonisolated var requiresAPIKey: Bool { self == .openAI }
}

extension UserDefaults {
    nonisolated private enum K {
        static let provider = "aiProvider"
        static let baseURL  = "aiBaseURL"
        static let model    = "aiModel"
        static let enableThinking = "aiEnableThinking"
    }

    nonisolated var aiProvider: AIProvider {
        get {
            guard let raw = string(forKey: K.provider) else { return .openAI }
            return AIProvider(rawValue: raw) ?? .openAI
        }
        set { set(newValue.rawValue, forKey: K.provider) }
    }

    nonisolated var aiBaseURL: String {
        get {
            if let v = string(forKey: K.baseURL), !v.isEmpty { return v }
            return aiProvider.defaultBaseURL
        }
        set { set(newValue, forKey: K.baseURL) }
    }

    nonisolated var aiModel: String {
        get {
            if let v = string(forKey: K.model), !v.isEmpty { return v }
            return aiProvider.defaultModel
        }
        set { set(newValue, forKey: K.model) }
    }

    nonisolated var aiEnableThinking: Bool {
        get { bool(forKey: K.enableThinking) }
        set { set(newValue, forKey: K.enableThinking) }
    }
}

// MARK: - Prompts

enum AIAction: String, CaseIterable, Sendable {
    case fixSpelling   = "Fix Spelling and Grammar"
    case rephrase      = "Rephrase"
    case makeShorter   = "Make Shorter"
    case makeList      = "Make into List"
    case changeTone    = "Change Tone"
    case followUp      = "Follow-up"

    nonisolated var systemPrompt: String {
        switch self {
        case .fixSpelling:
            return "You are a grammar and spelling assistant. Fix any spelling, grammar, and punctuation errors in the user's text. Return only the corrected text with no explanation."
        case .rephrase:
            return "You are a writing assistant. Rephrase the user's text to improve clarity and flow while preserving the original meaning. Return only the rephrased text."
        case .makeShorter:
            return "You are a writing assistant. Make the user's text more concise, removing unnecessary words while keeping the key information. Return only the shortened text."
        case .makeList:
            return "You are a writing assistant. Convert the user's text into a clean bullet-point list. Return only the list."
        case .changeTone:
            return "You are a writing assistant. Rewrite the user's text in a professional and polished tone. Return only the rewritten text."
        case .followUp:
            return "You are a helpful assistant. Provide a helpful and nuanced response based on the text context provided."
        }
    }

    nonisolated var icon: String {
        switch self {
        case .fixSpelling:  return "wand.and.stars"
        case .rephrase:     return "arrow.trianglehead.2.clockwise"
        case .makeShorter:  return "arrow.down.left.and.arrow.up.right"
        case .makeList:     return "list.bullet"
        case .changeTone:   return "textformat"
        case .followUp:     return "bubble.left.and.bubble.right"
        }
    }

    nonisolated var color: String {
        switch self {
        case .fixSpelling:  return "purple"
        case .rephrase:     return "blue"
        case .makeShorter:  return "orange"
        case .makeList:     return "green"
        case .changeTone:   return "pink"
        case .followUp:     return "cyan"
        }
    }
}

// MARK: - Service

actor AIService {
    static let shared = AIService()
    
    enum TokenType: Sendable {
        case thinking
        case content
    }

    func stream(
        action: AIAction,
        text: String,
        onToken: @escaping @Sendable (String, TokenType) -> Void,
        onComplete: @escaping @Sendable (Error?) -> Void
    ) {
        let provider = UserDefaults.standard.aiProvider
        let baseURL  = UserDefaults.standard.aiBaseURL
        let model    = UserDefaults.standard.aiModel
        let apiKey   = KeychainService.shared.getAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)

        if provider.requiresAPIKey && apiKey.isEmpty {
            onComplete(AIError.missingAPIKey)
            return
        }

        guard let url = URL(string: baseURL.trimmingCharacters(in: .init(charactersIn: "/")) + "/chat/completions") else {
            onComplete(AIError.badURL)
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("AIHelper/1.0", forHTTPHeaderField: "User-Agent")

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": action.systemPrompt],
                ["role": "user",   "content": text]
            ]
        ]
        
        if provider == .ollama && UserDefaults.standard.aiEnableThinking {
            body["think"] = true
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        Task {
            var isInThinkTag = false
            do {
                let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    var detail = "HTTP \(httpResponse.statusCode)"
                    var bodyData = Data()
                    for try await byte in asyncBytes {
                        bodyData.append(byte)
                        if bodyData.count > 10000 { break }
                    }
                    if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                       let errorObj = json["error"] as? [String: Any],
                       let message = errorObj["message"] as? String {
                        detail = message
                    } else if let str = String(data: bodyData, encoding: .utf8), !str.isEmpty {
                        detail = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    onComplete(AIError.apiError(detail))
                    return
                }
                for try await line in asyncBytes.lines {
                    guard line.hasPrefix("data: ") else {
                        // Some providers might return an error object as the first line if not data:
                        if let jsonData = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let errorObj = json["error"] as? [String: Any],
                           let message = errorObj["message"] as? String {
                            onComplete(AIError.apiError(message))
                            return
                        }
                        continue
                    }
                    let data = String(line.dropFirst(6))
                    if data == "[DONE]" { break }
                    guard let jsonData = data.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }

                    guard let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any] else { continue }
                    
                    // 1. Handle explicit reasoning/thinking fields
                    if let reasoning = (delta["reasoning_content"] as? String) ?? (delta["thinking"] as? String), !reasoning.isEmpty {
                        await MainActor.run { onToken(reasoning, .thinking) }
                        continue
                    }
                    
                    // 2. Handle content field (with potential <think> tags)
                    guard let content = delta["content"] as? String, !content.isEmpty else { continue }
                    
                    var remaining = content
                    while !remaining.isEmpty {
                        if !isInThinkTag {
                            if let range = remaining.range(of: "<think>") {
                                let prefix = String(remaining[..<range.lowerBound])
                                if !prefix.isEmpty {
                                    await MainActor.run { onToken(prefix, .content) }
                                }
                                isInThinkTag = true
                                remaining = String(remaining[range.upperBound...])
                            } else {
                                let finalPart = remaining
                                await MainActor.run { onToken(finalPart, .content) }
                                remaining = ""
                            }
                        } else {
                            if let range = remaining.range(of: "</think>") {
                                let prefix = String(remaining[..<range.lowerBound])
                                if !prefix.isEmpty {
                                    await MainActor.run { onToken(prefix, .thinking) }
                                }
                                isInThinkTag = false
                                remaining = String(remaining[range.upperBound...])
                            } else {
                                let finalPart = remaining
                                await MainActor.run { onToken(finalPart, .thinking) }
                                remaining = ""
                            }
                        }
                    }
                }
                await MainActor.run { onComplete(nil) }
            } catch {
                await MainActor.run { onComplete(error) }
            }
        }
    }

    func fetchModels(
        provider: AIProvider,
        baseURL: String,
        apiKey: String
    ) async throws -> [String] {
        if provider.requiresAPIKey && apiKey.isEmpty {
            throw AIError.missingAPIKey
        }

        guard let url = URL(string: baseURL.trimmingCharacters(in: .init(charactersIn: "/")) + "/models") else {
            throw AIError.badURL
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw AIError.httpError(httpResponse.statusCode)
        }

        struct ModelsResponse: Codable {
            struct ModelItem: Codable {
                let id: String
            }
            let data: [ModelItem]
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map { $0.id }.sorted()
    }
}

// MARK: - Errors

enum AIError: LocalizedError {
    case missingAPIKey
    case httpError(Int)
    case badURL
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Open Settings (⌘,) to add one."
        case .httpError(let code):
            return "Server returned HTTP \(code). Check your model and API key."
        case .badURL:
            return "Invalid base URL. Check your settings."
        case .apiError(let message):
            return "API Error: \(message)"
        }
    }
}
