//
//  PopupController.swift
//  AIHelper — macOS AI writing assistant
//

import Cocoa
import SwiftUI

class PopupController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<PopupPanelView>?
    private var escMonitor: Any?
    private var topLeft: NSPoint = .zero
    private let popupWidth: CGFloat = 700
    private let minHeight: CGFloat  = 280
    private let maxHeight: CGFloat  = 700

    /// Called when the hotkey fires. Copies selection then shows popup.
    func trigger() {
        // Output removed for production"[PopupController] trigger() called")
        // 1. Save the current pasteboard contents so we can restore them
        let pasteboard = NSPasteboard.general
        let savedContents = pasteboard.string(forType: .string)

        // 2. Send Cmd+C to copy the current selection
        pasteboard.clearContents()
        sendCmdC()

        // 3. Wait a moment for the copy to land, then read and show
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            let copied = pasteboard.string(forType: .string) ?? ""
            // Output removed for production"[PopupController] copied text: '\(copied.prefix(60))'")
            // Restore pasteboard if nothing useful was copied
            if copied.isEmpty, let saved = savedContents {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
            self?.showPopup(text: copied)
        }
    }

    private func sendCmdC() {
        let src = CGEventSource(stateID: .hidSystemState)
        // keyCode 8 = 'c'
        let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func showPopup(text: String) {
        // Output removed for production"[PopupController] showPopup() called, text length=\(text.count)")
        dismissPopup()

        let sourceApp = NSWorkspace.shared.frontmostApplication
        let mouseLocation = NSEvent.mouseLocation

        let newPanel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: popupWidth, height: 100),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        newPanel.becomesKeyOnlyIfNeeded = false
        newPanel.level = .floating
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isMovableByWindowBackground = false
        newPanel.delegate = self

        let rootView = PopupPanelView(
            selectedText: text,
            sourceApp: sourceApp,
            onDismiss: { [weak self] in self?.dismissPopup() },
            onPasteBack: { [weak self] result in
                self?.pasteBack(text: result, to: sourceApp)
            }
        )
        let hosting = NSHostingView(rootView: rootView)
        // .preferredContentSize lets SwiftUI drive the window size automatically
        // without us calling setContentSize, avoiding layout recursion
        hosting.sizingOptions = .preferredContentSize
        newPanel.contentView = hosting

        // Compute anchor: top-left corner stays fixed as height grows
        var anchor = NSPoint(x: mouseLocation.x + 8, y: mouseLocation.y - 8)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            anchor.x = max(screen.visibleFrame.minX + 8, min(anchor.x, screen.visibleFrame.maxX - popupWidth - 8))
            anchor.y = min(anchor.y, screen.visibleFrame.maxY - 8)
        }
        topLeft = anchor

        // Set initial frame — SwiftUI will resize from here via .preferredContentSize
        let initialHeight = min(max(hosting.fittingSize.height, minHeight), maxHeight)
        newPanel.setFrame(NSRect(x: topLeft.x, y: topLeft.y - initialHeight,
                                 width: popupWidth, height: initialHeight),
                          display: false)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResignKey),
            name: NSWindow.didResignKeyNotification,
            object: newPanel
        )

        // Output removed for production"[PopupController] showing panel at frame=\(newPanel.frame)")
        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        panel = newPanel
        hostingView = hosting

        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { self?.dismissPopup() }
            }
        }
    }

    // MARK: - NSWindowDelegate — keep top-left anchor fixed on resize

    func windowDidResize(_ notification: Notification) {
        guard let panel = panel else { return }
        let h = min(max(panel.frame.height, minHeight), maxHeight)
        let newOrigin = NSPoint(x: topLeft.x, y: topLeft.y - h)
        if panel.frame.origin != newOrigin {
            panel.setFrameOrigin(newOrigin)
        }
    }

    /// Put `text` on the pasteboard, switch back to the source app, then send ⌘V.
    private func pasteBack(text: String, to app: NSRunningApplication?) {
        // 1. Write to pasteboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // 2. Hide popup immediately so source app can regain focus
        panel?.orderOut(nil)

        // 3. Re-activate source app, then send Cmd+V once it's front
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            app?.activate(options: .activateIgnoringOtherApps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.sendCmdV()
                // Clean up after paste
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.dismissPopup()
                }
            }
        }
    }

    private func sendCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        // keyCode 9 = 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    @objc private func handleResignKey() {
        dismissPopup()
    }

    private func dismissPopup() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: panel)
        if let monitor = escMonitor { NSEvent.removeMonitor(monitor) }
        escMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }
}

// MARK: - Custom panel that accepts keyboard input

/// Borderless panels refuse key-window status by default.
/// This subclass overrides that so TextField / TextEditor can receive focus.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
