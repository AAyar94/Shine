//
//  ShineApp.swift
//  Shine
//
//  Created by Adem Ayar on 10.07.2026.
//

import SwiftUI
import Observation
import ServiceManagement
import OSLog

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
    var brightnessLinked: Bool = UserDefaults.standard.object(forKey: "brightnessLinked") as? Bool ?? true {
        didSet { UserDefaults.standard.set(brightnessLinked, forKey: "brightnessLinked") }
    }

    /// Shows a percentage label next to each slider.
    var showSliderPercentages: Bool = UserDefaults.standard.object(forKey: "showSliderPercentages") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showSliderPercentages, forKey: "showSliderPercentages") }
    }

    /// Magnetically snaps slider values to the nearest quarter mark
    /// (25%, 50%, 75%, 100%, and 0%) when the value lands close to it.
    var snapToQuarters: Bool = UserDefaults.standard.object(forKey: "snapToQuarters") as? Bool ?? false {
        didSet { UserDefaults.standard.set(snapToQuarters, forKey: "snapToQuarters") }
    }

    /// Applies quarter-mark snapping when `snapToQuarters` is enabled, otherwise
    /// returns the value unchanged. Used to wrap slider set closures.
    func snapped(_ value: Float) -> Float {
        guard snapToQuarters else { return value }
        let marks: [Float] = [0, 0.25, 0.5, 0.75, 1.0]
        let threshold: Float = 0.05
        for mark in marks where abs(value - mark) <= threshold { return mark }
        return value
    }

    /// Whether macOS launches Shine automatically when the user logs in.
    /// Backed by the system login-item registration rather than UserDefaults,
    /// so it stays in sync with what the user does in System Settings > General
    /// > Login Items.
    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard !isSyncingLaunchAtLogin, oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Logger(subsystem: "Shine", category: "LaunchAtLogin")
                    .error("Failed to \(self.launchAtLogin ? "enable" : "disable") launch at login: \(error.localizedDescription)")
                // Roll the toggle back so the UI reflects the real state,
                // without re-entering the registration path.
                isSyncingLaunchAtLogin = true
                launchAtLogin = oldValue
                isSyncingLaunchAtLogin = false
            }
        }
    }
    @ObservationIgnored private var isSyncingLaunchAtLogin = false

    @ObservationIgnored private var permissionPoller: Timer?

    /// Set when a newer release is found on GitHub.
    var availableVersion: String?
    var updateURL: URL?
    var updateAvailable: Bool { availableVersion != nil }

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
        }

        // The tap may fail to create even when AXIsProcessTrusted returns true
        // (stale entry after an app update). Keep polling until the tap is live.
        startPermissionPoller()

        Task { await checkForUpdates() }
    }

    /// Polls until the event tap is successfully running.
    private func startPermissionPoller() {
        permissionPoller?.invalidate()
        permissionPoller = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                let state = AppState.shared
                if state.keyboard.isRunning {
                    state.accessibilityGranted = true
                    state.permissionPoller?.invalidate()
                    state.permissionPoller = nil
                    return
                }
                // Either not trusted yet, or stale — re-check.
                let trusted = KeyboardManager.isAccessibilityTrusted(promptIfNeeded: false)
                state.accessibilityGranted = trusted
                if trusted {
                    state.keyboard.start()
                }
            }
        }
    }

    private func checkForUpdates() async {
        if let result = await UpdateChecker.check() {
            availableVersion = result.latestVersion
            updateURL = result.releaseURL
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
