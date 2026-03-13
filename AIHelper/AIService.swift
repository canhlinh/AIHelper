//
//  AIService.swift
//  AIHelper — macOS AI writing assistant
//


import Foundation

// MARK: - Provider config stored in UserDefaults

enum AIProvider: String, CaseIterable, Codable, Sendable {
    case openAI = "OpenAI"
    case ollama = "Ollama"

    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .ollama: return "http://localhost:11434/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .ollama: return "gemma3:12b"
        }
    }

    var requiresAPIKey: Bool { self == .openAI }
}

extension UserDefaults {
    private enum K {
        static let apiKey   = "openAIApiKey"
        static let provider = "aiProvider"
        static let baseURL  = "aiBaseURL"
        static let model    = "aiModel"
    }

    nonisolated var openAIApiKey: String {
        get { string(forKey: K.apiKey) ?? "" }
        set { set(newValue, forKey: K.apiKey) }
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
            return "You are a helpful assistant. Answer the user's query based on the provided text context. Be concise."
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

    func stream(
        action: AIAction,
        text: String,
        onToken: @escaping @Sendable (String) -> Void,
        onComplete: @escaping @Sendable (Error?) -> Void
    ) {
        let provider = UserDefaults.standard.aiProvider
        let baseURL  = UserDefaults.standard.aiBaseURL
        let model    = UserDefaults.standard.aiModel
        let apiKey   = UserDefaults.standard.openAIApiKey

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

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": action.systemPrompt],
                ["role": "user",   "content": text]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        Task {
            do {
                let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    onComplete(AIError.httpError(httpResponse.statusCode))
                    return
                }
                for try await line in asyncBytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let data = String(line.dropFirst(6))
                    if data == "[DONE]" { break }
                    guard let jsonData = data.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let content = delta["content"] as? String else { continue }
                    await MainActor.run { onToken(content) }
                }
                await MainActor.run { onComplete(nil) }
            } catch {
                await MainActor.run { onComplete(error) }
            }
        }
    }
}

// MARK: - Errors

enum AIError: LocalizedError {
    case missingAPIKey
    case httpError(Int)
    case badURL

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No OpenAI API key set. Open Settings (⌘,) to add one."
        case .httpError(let code):
            return "Server returned HTTP \(code). Check your model and API key."
        case .badURL:
            return "Invalid base URL. Check your settings."
        }
    }
}
