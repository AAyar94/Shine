//
//  MenuView.swift
//  Shine
//
//  The menu bar popover: permission banner, per-display brightness and
//  volume sliders, and key-capture toggles.
//

import SwiftUI

struct MenuView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 14) {
            if !appState.accessibilityGranted {
                permissionBanner
            }

            if !appState.displayManager.ddcSupported {
                Label("DDC is not available on this Mac.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if appState.displayManager.displays.isEmpty {
                Label("No external display detected.", systemImage: "display.trianglebadge.exclamationmark")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.displayManager.displays) { display in
                    DisplaySection(display: display)
                }
            }

            Divider()

            Toggle("Brightness keys control monitor under pointer", isOn: $appState.brightnessKeysEnabled)
                .toggleStyle(.checkbox)
            Toggle("Volume keys control monitor speakers", isOn: $appState.volumeKeysEnabled)
                .toggleStyle(.checkbox)

            Divider()

            HStack {
                Button("Refresh Displays") {
                    appState.displayManager.rescan()
                }
                Button("Hide Icon") {
                    confirmHideMenuBarIcon()
                }
                Spacer()
                Button("Quit Shine") {
                    NSApp.terminate(nil)
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
    }

    /// Hides the menu bar icon after explaining how to bring it back.
    private func confirmHideMenuBarIcon() {
        let alert = NSAlert()
        alert.messageText = "Hide the menu bar icon?"
        alert.informativeText = "Shine keeps running and the keyboard keys keep working. To show the icon again, open Shine from Launchpad or Finder."
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            appState.menuBarIconVisible = false
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accessibility permission needed", systemImage: "hand.raised.fill")
                .font(.headline)
            Text("Shine needs Accessibility access to capture the keyboard brightness and volume keys.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open System Settings…") {
                KeyboardManager.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.15)))
    }
}

private struct DisplaySection: View {
    let display: ExternalDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(display.name)
                    .font(.headline)
                Spacer()
                if !display.respondsToDDC {
                    Text("No DDC reply")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("The monitor did not answer DDC reads. Controls may still work; enable DDC/CI in the monitor's on-screen menu if they don't.")
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Slider(value: Binding(
                    get: { display.brightness },
                    set: { display.setBrightness($0) }
                ))
            }

            HStack(spacing: 8) {
                Button {
                    display.setMuted(!display.muted)
                } label: {
                    Image(systemName: display.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { display.muted ? 0 : display.volume },
                    set: { display.setVolume($0) }
                ))
            }
        }
    }
}
