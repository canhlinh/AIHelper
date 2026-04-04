//
//  ShortcutSettingsView.swift
//  AIHelper — macOS AI writing assistant
//

import SwiftUI
import AppKit
import Combine

// MARK: - View

struct ShortcutSettingsView: View {
    @StateObject private var recorder = ShortcutRecorder()

    // AI settings
    @State private var provider: AIProvider    = UserDefaults.standard.aiProvider
    @State private var baseURL: String         = UserDefaults.standard.aiBaseURL
    @State private var model: String           = UserDefaults.standard.aiModel
    @State private var apiKey: String          = KeychainService.shared.getAPIKey()
    @State private var showAPIKey              = false
    @State private var aiSaved                 = false
    @State private var enableThinking          = UserDefaults.standard.aiEnableThinking
    
    // Fetching models
    @State private var availableModels: [String] = []
    @State private var isFetchingModels        = false
    @State private var fetchError: String?     = nil

    var onDismiss: (() -> Void)? = nil
    var onSave: (HotkeyShortcut) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── AI Provider ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Label("AI Provider", systemImage: "cpu")
                    .font(.headline)

                // Provider picker
                Picker("", selection: $provider) {
                    ForEach(AIProvider.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: provider) { newProvider in
                    // Reset URL and model to defaults for the chosen provider
                    baseURL = newProvider.defaultBaseURL
                    model   = newProvider.defaultModel
                    // Clear stale model list
                    availableModels = []
                }

                // Base URL
                HStack {
                    Text("Base URL")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    TextField("http://localhost:11434/v1", text: $baseURL)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: baseURL) { _ in
                            availableModels = []
                        }
                }

                // Model
                HStack {
                    Text("Model")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    TextField(provider.defaultModel, text: $model)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                    
                    if isFetchingModels {
                        ProgressView().controlSize(.small).scaleEffect(0.5)
                    } else {
                        Menu {
                            if availableModels.isEmpty {
                                Button("No models loaded") {}.disabled(true)
                            } else {
                                ForEach(availableModels, id: \.self) { m in
                                    Button(m) { model = m }
                                }
                            }
                            Divider()
                            Button("Refresh Models") {
                                fetchAvailableModels()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundStyle(.blue)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }

                // API Key — only for OpenAI
                if provider.requiresAPIKey {
                    HStack {
                        Text("API Key")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Group {
                            if showAPIKey {
                                TextField("sk-...", text: $apiKey)
                            } else {
                                SecureField("sk-...", text: $apiKey)
                            }
                        }
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        Button { showAPIKey.toggle() } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else if provider == .ollama {
                    HStack {
                        Text("Thinking")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Toggle("Enable experimental reasoning mode", isOn: $enableThinking)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                        Spacer()
                    }
                }

                HStack {
                    Text(provider == .ollama ? "Make sure Ollama is running locally." : "Your API key is stored securely in Keychain on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if aiSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                    Button("Save") {
                        UserDefaults.standard.aiProvider  = provider
                        UserDefaults.standard.aiBaseURL   = baseURL
                        UserDefaults.standard.aiModel     = model
                        UserDefaults.standard.aiEnableThinking = enableThinking
                        KeychainService.shared.setAPIKey(apiKey)
                        withAnimation { aiSaved = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { aiSaved = false }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            // ── Shortcut Section ─────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Label("Global Shortcut", systemImage: "keyboard")
                    .font(.headline)

                ShortcutFieldView(recorder: recorder)

                Text("Click the field and press your desired key combination (must include ⌘, ⌃, or ⌥).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Buttons ───────────────────────────────────────────────
            HStack {
                Button("Reset Shortcut") {
                    ShortcutStore.shared.shortcut = .default
                    recorder.current = .default
                    recorder.isRecording = false
                }
                Spacer()
                Button("Cancel") {
                    onDismiss?()
                }
                Button("Save Shortcut") {
                    onSave(recorder.current)
                }
                .buttonStyle(.borderedProminent)
                .disabled(recorder.isRecording)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { recorder.current = ShortcutStore.shared.shortcut }
    }

    private func fetchAvailableModels() {
        isFetchingModels = true
        fetchError = nil
        
        Task {
            do {
                let models = try await AIService.shared.fetchModels(
                    provider: provider,
                    baseURL: baseURL,
                    apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await MainActor.run {
                    self.availableModels = models
                    self.isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    self.fetchError = error.localizedDescription
                    self.isFetchingModels = false
                }
            }
        }
    }
}

// MARK: - Recorder field

private struct ShortcutFieldView: View {
    @ObservedObject var recorder: ShortcutRecorder

    var body: some View {
        HStack {
            Text(recorder.isRecording ? "Press a key combo…" : recorder.current.displayString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(recorder.isRecording ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if recorder.isRecording {
                Button("Cancel") { recorder.isRecording = false }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(recorder.isRecording ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: recorder.isRecording ? 2 : 1)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        )
        .onTapGesture { recorder.isRecording = true }
        .background(KeyCaptureView(recorder: recorder))
    }
}

// MARK: - NSViewRepresentable key capture

private struct KeyCaptureView: NSViewRepresentable {
    @ObservedObject var recorder: ShortcutRecorder

    func makeNSView(context: Context) -> KeyCaptureNSView {
        KeyCaptureNSView(recorder: recorder)
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.recorder = recorder
        if recorder.isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

class KeyCaptureNSView: NSView {
    var recorder: ShortcutRecorder

    init(recorder: ShortcutRecorder) {
        self.recorder = recorder
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard recorder.isRecording else { super.keyDown(with: event); return }

        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        // Require at least one modifier
        guard !mods.isEmpty else { return }
        // Ignore pure modifier presses
        guard event.keyCode != 54, event.keyCode != 55,  // Cmd
              event.keyCode != 56, event.keyCode != 60,  // Shift
              event.keyCode != 58, event.keyCode != 61,  // Option
              event.keyCode != 59, event.keyCode != 62   // Control
        else { return }

        var cgFlags = CGEventFlags()
        if mods.contains(.command)  { cgFlags.insert(.maskCommand) }
        if mods.contains(.shift)    { cgFlags.insert(.maskShift) }
        if mods.contains(.option)   { cgFlags.insert(.maskAlternate) }
        if mods.contains(.control)  { cgFlags.insert(.maskControl) }

        recorder.current = HotkeyShortcut(keyCode: event.keyCode, modifierFlags: cgFlags.rawValue)
        recorder.isRecording = false
    }

    override func flagsChanged(with event: NSEvent) {
        // Do nothing — wait for a full keyDown
    }
}

// MARK: - Recorder state

class ShortcutRecorder: ObservableObject {
    @Published var current: HotkeyShortcut = .default
    @Published var isRecording = false
}
