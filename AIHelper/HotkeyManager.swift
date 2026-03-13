//
//  HotkeyManager.swift
//  AIHelper — macOS AI writing assistant
//

import Cocoa
import Carbon

/// Fully nonisolated — the CGEvent tap callback is a C function pointer
/// that runs outside any actor context and must access properties synchronously.
nonisolated class HotkeyManager: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let callback: @Sendable () -> Void
    private var permissionTimer: Timer?

    // Cached shortcut values — updated on main thread via reload()
    private var targetKeyCode: CGKeyCode
    private var targetFlags: CGEventFlags

    init(callback: @escaping @Sendable () -> Void) {
        let shortcut = ShortcutStore.shared.shortcut
        self.targetKeyCode = CGKeyCode(shortcut.keyCode)
        self.targetFlags = shortcut.cgFlags
        self.callback = callback
    }

    /// Call after saving a new shortcut — refreshes cached values and ensures tap is live.
    func reload() {
        let shortcut = ShortcutStore.shared.shortcut
        targetKeyCode = CGKeyCode(shortcut.keyCode)
        targetFlags = shortcut.cgFlags

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            start()
        }
    }

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            // Output removed for production"[HotkeyManager] Accessibility permission not granted. Will retry...")
            schedulePermissionCheck()
            return
        }

        permissionTimer?.invalidate()
        permissionTimer = nil
        tearDownTap()

        // Listen for keyDown + tapDisabled events so we can re-enable if macOS kills the tap
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                 | CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
                 | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)

        // Use passUnretained — AppDelegate holds HotkeyManager alive for the app's lifetime
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            // Output removed for production"[HotkeyManager] Failed to create event tap. Retrying...")
            schedulePermissionCheck()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // Output removed for production"[HotkeyManager] Event tap registered successfully.")
    }

    private func tearDownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    private func schedulePermissionCheck() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if AXIsProcessTrusted() {
                // Output removed for production"[HotkeyManager] Permission granted. Starting hotkey...")
                self.start()
            }
        }
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS can disable the tap on timeout — re-enable it immediately
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Output removed for production"[HotkeyManager] Tap disabled (\(type.rawValue)), re-enabling...")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])

        // Output removed for production"[HotkeyManager] keyDown keyCode=\(keyCode) flags=\(flags.rawValue) | target keyCode=\(targetKeyCode) flags=\(targetFlags.rawValue)")

        if keyCode == targetKeyCode && flags == targetFlags {
            // Output removed for production"[HotkeyManager] ✅ Shortcut matched! Firing callback.")
            DispatchQueue.main.async { [weak self] in
                self?.callback()
            }
            return nil // consume the event
        }
        return Unmanaged.passRetained(event)
    }

    deinit {
        permissionTimer?.invalidate()
        tearDownTap()
    }
}
