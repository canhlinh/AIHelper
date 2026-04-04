//
//  SuggestionViewModel.swift
//  AIHelper — macOS AI writing assistant
//

import Foundation
import Combine

enum SuggestionState {
    case idle
    case loading
    case streaming(thinking: String, content: String)
    case done(thinking: String, content: String)
    case error(message: String)

    var resultText: String? {
        switch self {
        case .streaming(_, let c), .done(_, let c): return c
        default: return nil
        }
    }

    var thinkingText: String? {
        switch self {
        case .streaming(let t, _), .done(let t, _): return t
        default: return nil
        }
    }

    var isDone: Bool {
        if case .done = self { return true }
        return false
    }

    var isWorking: Bool {
        switch self {
        case .loading, .streaming: return true
        default: return false
        }
    }
}

@MainActor
class SuggestionViewModel: ObservableObject {
    @Published var state: SuggestionState = .idle
    @Published var activeAction: AIAction? = nil
    @Published var followUpQuery: String = ""
    var pasteBackHandler: ((String) -> Void)?

    private var streamTask: Task<Void, Never>?

    func run(action: AIAction, text: String, query: String? = nil) {
        let combinedText = query != nil ? "Context: \(text)\n\nUser Query: \(query!)" : text
        guard !combinedText.isEmpty else { return }
        streamTask?.cancel()
        activeAction = action
        state = .loading

        streamTask = Task {
            var thinking = ""
            var content  = ""

            // Bridge the actor-isolated callbacks into an AsyncStream
            let stream = AsyncStream<Result<(String, AIService.TokenType), Error>> { continuation in
                Task {
                    await AIService.shared.stream(
                        action: action,
                        text: combinedText,
                        onToken: { token, type in
                            continuation.yield(.success((token, type)))
                        },
                        onComplete: { error in
                            if let error {
                                continuation.yield(.failure(error))
                            }
                            continuation.finish()
                        }
                    )
                }
            }

            for await result in stream {
                guard !Task.isCancelled else { break }
                switch result {
                case .success(let (token, type)):
                    if type == .thinking {
                        thinking += token
                    } else {
                        content += token
                    }
                    state = .streaming(thinking: thinking, content: content)
                case .failure(let error):
                    state = .error(message: error.localizedDescription)
                    return
                }
            }

            guard !Task.isCancelled else { return }
            if case .streaming = state {
                state = .done(thinking: thinking, content: content)
            }
        }
    }

    func reset() {
        streamTask?.cancel()
        streamTask = nil
        state = .idle
        activeAction = nil
    }

    func pasteBack(text: String) {
        pasteBackHandler?(text)
    }
}
