//
//  AIHelperApp.swift
//  AIHelper — macOS AI writing assistant
//


import SwiftUI
import AppKit

@main
struct AIHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
