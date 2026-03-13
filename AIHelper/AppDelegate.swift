//
//  AppDelegate.swift
//  AIHelper — macOS AI writing assistant
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var hotkeyManager: HotkeyManager?
    var popupController: PopupController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a background agent (no dock icon)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Paragraph")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openShortcutSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AIHelper", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu

        // Popup controller
        popupController = PopupController()

        // Global hotkey (reads from ShortcutStore)
        hotkeyManager = HotkeyManager { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.popupController?.trigger()
            }
        }
        hotkeyManager?.start()
    }

    @objc func openShortcutSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Build the window first so we can reference it inside the view's callbacks
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AIHelper – Settings"
        window.isReleasedWhenClosed = false

        let view = ShortcutSettingsView(
            onDismiss: { [weak window] in window?.close() },
            onSave: { [weak self, weak window] newShortcut in
                ShortcutStore.shared.shortcut = newShortcut
                self?.hotkeyManager?.reload()
                window?.close()
            }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
