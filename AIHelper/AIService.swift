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
        static let translateVI = "aiTranslateVI"
        static let translateKO = "aiTranslateKO"
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

    nonisolated var aiTranslateVI: Bool {
        get {
            if object(forKey: K.translateVI) == nil { return true }
            return bool(forKey: K.translateVI)
        }
        set { set(newValue, forKey: K.translateVI) }
    }

    nonisolated var aiTranslateKO: Bool {
        get {
            if object(forKey: K.translateKO) == nil { return true }
            return bool(forKey: K.translateKO)
        }
        set { set(newValue, forKey: K.translateKO) }
    }
}

// MARK: - Prompts

enum AIAction: String, CaseIterable, Sendable {
    case fixSpelling   = "Fix Spelling and Grammar"
    case followUp      = "Follow-up"
    case translateVI   = "Dịch sang Tiếng Việt"
    case translateKO   = "Dịch sang Tiếng Hàn"

    nonisolated var systemPrompt: String {
        switch self {
        case .fixSpelling:
            return """
            SYSTEM: You are a robotic grammar correction tool. 
            RULES:
            - Provide ONLY the corrected text.
            - NO preamble. 
            - NO explanation.
            - NO alternatives.
            - If the input is a fragment, complete it naturally.
            - Return exactly one string.
            """
        case .followUp:
            return "You are a helpful and intelligent assistant. Answer the user's question or follow-up request accurately based on the provided text context. Be detailed yet concise."
        case .translateVI:
            return "Translate the following text to natural Vietnamese. Return ONLY the translation. No preamble."
        case .translateKO:
            return "Translate the following text to natural Korean. Return ONLY the translation. No preamble."
        }
    }

    nonisolated var icon: String {
        switch self {
        case .fixSpelling:  return "wand.and.stars"
        case .followUp:     return "bubble.left.and.bubble.right"
        case .translateVI:  return "character.bubble"
        case .translateKO:  return "character.bubble"
        }
    }

    nonisolated var color: String {
        switch self {
        case .fixSpelling:  return "purple"
        case .followUp:     return "cyan"
        case .translateVI:  return "red"
        case .translateKO:  return "blue"
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
