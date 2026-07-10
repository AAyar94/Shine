//
//  ShineApp.swift
//  Shine
//
//  Created by Adem Ayar on 10.07.2026.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let displayManager = DisplayManager()
    @ObservationIgnored let keyboard = KeyboardManager()

    var accessibilityGranted = false

    /// The menu bar icon can be hidden; relaunching the app shows it again.
    var menuBarIconVisible: Bool = UserDefaults.standard.object(forKey: "menuBarIconVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(menuBarIconVisible, forKey: "menuBarIconVisible") }
    }

    var brightnessKeysEnabled: Bool = UserDefaults.standard.object(forKey: "brightnessKeys") as? Bool ?? true {
        didSet { UserDefaults.standard.set(brightnessKeysEnabled, forKey: "brightnessKeys") }
    }
    var volumeKeysEnabled: Bool = UserDefaults.standard.object(forKey: "volumeKeys") as? Bool ?? true {
        didSet { UserDefaults.standard.set(volumeKeysEnabled, forKey: "volumeKeys") }
    }

    @ObservationIgnored private var permissionPoller: Timer?

    private init() {}

    func start() {
        keyboard.handler = { [weak self] code, isPressed, isRepeat in
            self?.handleMediaKey(code: code, isPressed: isPressed, isRepeat: isRepeat) ?? false
        }

        // Shows the system dialog on first launch, then keep polling so the
        // tap starts as soon as the user grants access in System Settings.
        accessibilityGranted = KeyboardManager.isAccessibilityTrusted(promptIfNeeded: true)
        if accessibilityGranted {
            keyboard.start()
        } else {
            permissionPoller = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in
                    let state = AppState.shared
                    if KeyboardManager.isAccessibilityTrusted(promptIfNeeded: false) {
                        state.accessibilityGranted = true
                        state.keyboard.start()
                        state.permissionPoller?.invalidate()
                        state.permissionPoller = nil
                    }
                }
            }
        }
    }
}

/// Restores the menu bar icon when the user opens the app while it is
/// already running (e.g. from Launchpad or Finder after hiding the icon).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        AppState.shared.menuBarIconVisible = true
        return true
    }
}

@main
struct ShineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppState.shared.start()
    }

    var body: some Scene {
        MenuBarExtra("Shine", systemImage: "sun.max.fill",
                     isInserted: Bindable(AppState.shared).menuBarIconVisible) {
            MenuView()
                .environment(AppState.shared)
        }
        .menuBarExtraStyle(.window)
    }
}
