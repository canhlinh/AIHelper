//
//  PopupPanelView.swift
//  AIHelper — macOS AI writing assistant
//

import SwiftUI
import AppKit
import Combine

struct PopupPanelView: View {
    let selectedText: String
    let sourceApp: NSRunningApplication?
    var onDismiss: () -> Void
    var onPasteBack: ((String) -> Void)?

    @StateObject private var vm = SuggestionViewModel()
    @StateObject private var translationVM = SuggestionViewModel()
    @State private var isVisible = false
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider().overlay(Color.white.opacity(0.1))
            contentArea
            Divider().overlay(Color.white.opacity(0.1))
            footerView
        }
        .preferredColorScheme(.dark)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.11, alpha: 0.98)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
        .scaleEffect(isVisible ? 1 : 0.96)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            vm.pasteBackHandler = onPasteBack
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isQueryFocused = true
            }
            // Initially run the default action
            vm.run(action: .fixSpelling, text: selectedText)
        }
    }

    private func submitFollowUp() {
        guard !vm.followUpQuery.isEmpty else { return }
        translationVM.reset()
        vm.run(action: .followUp, text: selectedText, query: vm.followUpQuery)
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)

            TextField("", text: $vm.followUpQuery, prompt: Text("Ask follow-up...").foregroundColor(.white.opacity(0.4)))
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium))
                .focused($isQueryFocused)
                .onSubmit {
                    submitFollowUp()
                }
                .foregroundColor(.white)
                .accentColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                actionBox
                
                // AI Model hint
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                    Text(UserDefaults.standard.aiModel)
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.35))
                .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .frame(minHeight: 300, maxHeight: 500)
    }

    private var actionBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let icon = sourceApp?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .cornerRadius(4)
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.white.opacity(0.4))
                }
                
                Text(vm.activeAction?.rawValue ?? "Fix Spelling and Grammar")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            
            if vm.state.isWorking {
                LoadingDotsView()
            } else if let resultText = vm.state.resultText {
                VStack(alignment: .leading, spacing: 14) {
                    Text(resultText)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    
                    // Quick Translation Actions — ONLY for Spelling Check
                    if vm.activeAction == .fixSpelling {
                        HStack(spacing: 8) {
                            if UserDefaults.standard.aiTranslateVI {
                                QuickActionButton(title: "Tiếng Việt", icon: "character.bubble", color: .red) {
                                    translationVM.run(action: .translateVI, text: resultText)
                                }
                            }
                            if UserDefaults.standard.aiTranslateKO {
                                QuickActionButton(title: "Tiếng Hàn", icon: "character.bubble", color: .blue) {
                                    translationVM.run(action: .translateKO, text: resultText)
                                }
                            }
                        }
                    }
                    
                    // Translation Result Area
                    if translationVM.state.isWorking || translationVM.state.resultText != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Divider().opacity(0.1).padding(.vertical, 4)
                            
                            if translationVM.state.isWorking && (translationVM.state.resultText?.isEmpty ?? true) {
                                LoadingDotsView()
                                    .padding(.vertical, 4)
                            }
                            
                            if let transThinking = translationVM.state.thinkingText, !transThinking.isEmpty {
                                ThinkingView(text: transThinking)
                                    .padding(.bottom, 4)
                            }
                            
                            if let transResult = translationVM.state.resultText, !transResult.isEmpty {
                                Text(transResult)
                                    .font(.system(size: 14, design: .serif))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }
                }
            } else if case .error(let message) = vm.state {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                // Empty state icon
                Image(systemName: "diamond.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            
            if let thinking = vm.state.thinkingText, !thinking.isEmpty {
                ThinkingView(text: thinking)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var footerView: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("AI Helper")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            
            Spacer()
            
            HStack(spacing: 16) {
                // Cancel
                Button(action: onDismiss) {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)

                // Paste Response (Raycast-style)
                if let resultText = vm.state.resultText {
                    Button {
                        vm.pasteBack(text: resultText)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Paste to \(sourceApp?.localizedName ?? "App")")
                                .font(.system(size: 12, weight: .semibold))
                            
                            HStack(spacing: 4) {
                                Image(systemName: "return")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.2)))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.3, green: 0.4, blue: 0.9)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.01))
    }
}

// MARK: - Loading dots

private struct LoadingDotsView: View {
    @State private var dot = 0
    let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == dot ? 0.7 : 0.2))
                    .frame(width: 5, height: 5)
                    .scaleEffect(i == dot ? 1.25 : 1)
                    .animation(.spring(response: 0.28), value: dot)
            }
        }
        .onReceive(timer) { _ in dot = (dot + 1) % 3 }
    }
}

// MARK: - Thinking View

private struct ThinkingView: View {
    let text: String
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12))
                    Text("Thought Process")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundStyle(.blue.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Text(text)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineSpacing(2)
                    .padding(.leading, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .foregroundStyle(color.opacity(0.8))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PopupPanelView(
        selectedText: "The implementation plan has been approved. I am now starting the execution phase.",
        sourceApp: nil,
        onDismiss: {}
    )
    .frame(width: 700)
    .padding(40)
    .background(Color.black)
}
