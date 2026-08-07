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
        menuContent
    }

    private var menuContent: some View {
        @Bindable var appState = appState

        return VStack(alignment: .leading, spacing: 12) {
            if appState.updateAvailable {
                updateBanner
            }

            if !appState.accessibilityGranted {
                permissionBanner
            }

            if !appState.displayManager.ddcSupported {
                Label("DDC is not available on this Mac.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.primary)
                    .padding(12)
            } else if appState.displayManager.displays.isEmpty {
                Label("No external display detected.", systemImage: "display.trianglebadge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                if appState.brightnessLinked && appState.displayManager.displays.count > 1 {
                    linkedBrightnessSlider
                        .padding(12)
                }
                ForEach(appState.displayManager.displays) { display in
                    DisplaySection(display: display, showBrightness: !appState.brightnessLinked || appState.displayManager.displays.count <= 1)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                settingToggle("Brightness keys control monitor under pointer", isOn: $appState.brightnessKeysEnabled)
                settingToggle("Volume keys control monitor speakers", isOn: $appState.volumeKeysEnabled)
                Divider()
                settingToggle("Show percentage next to sliders", isOn: $appState.showSliderPercentages)
                settingToggle("Snap sliders to 25% / 50% / 75% / 100%", isOn: $appState.snapToQuarters)
                settingToggle("Launch Shine at login", isOn: $appState.launchAtLogin)
            }
            .padding(12)

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
            .glassButtons()
            .padding(8)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 5)
        .frame( maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.primary)
    }

    /// A settings row: the label takes the free width so every switch lands on
    /// the same trailing edge, regardless of how long its text is.
    private func settingToggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
    }

    /// Hides the menu bar icon after explaining how to bring it back.
    private func confirmHideMenuBarIcon() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Hide the menu bar icon?")
        alert.informativeText = String(localized: "Shine keeps running and the keyboard keys keep working. To show the icon again, open Shine from Launchpad or Finder.")
        alert.addButton(withTitle: String(localized: "Hide Icon"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            appState.menuBarIconVisible = false
        }
    }

    private var linkedBrightnessSlider: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Slider(value: Binding(
                    get: { appState.displayManager.averageBrightness },
                    set: { appState.displayManager.setBrightnessAll(appState.snapped($0)) }
                ))
                .tint(.blue)
                if appState.showSliderPercentages {
                    PercentLabel(value: appState.displayManager.averageBrightness)
                }
                Button {
                    appState.brightnessLinked = false
                } label: {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                }
                .glassIconButton()
                .help("Unlink brightness — control each display individually")
            }
        }
    }

    private var updateBanner: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 6) {
            Label("Shine \(appState.availableVersion ?? "") is available", systemImage: "arrow.down.circle.fill")
                .font(.headline)
            Text("A new version can be downloaded from GitHub.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Download") {
                    if let url = appState.updateURL { NSWorkspace.shared.open(url) }
                }
                .controlSize(.small)
                Button("Dismiss") {
                    appState.availableVersion = nil
                    appState.updateURL = nil
                }
                .controlSize(.small)
            }
        }
        .glassButtons()
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accessibility permission needed", systemImage: "hand.raised.fill")
                .font(.headline)
            Text("Shine needs Accessibility access to capture the keyboard brightness and volume keys.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("After an update, remove Shine from the list and re-add it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open System Settings…") {
                KeyboardManager.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
        .glassButtons()
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    /// Capsule-shaped Liquid Glass on every button in the subtree. Small round
    /// controls are almost entirely rim, which is where the effect reads — the
    /// popover's background stays plain material, as the system's own do.
    @ViewBuilder
    func glassButtons() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self
        }
    }

    /// Same idea for a bare icon button, keeping the borderless look on macOS
    /// versions that have no glass style to fall back to.
    @ViewBuilder
    func glassIconButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.plain)
        }
    }
}

private struct DisplaySection: View {
    let display: ExternalDisplay
    var showBrightness: Bool = true
    @Environment(AppState.self) private var appState

    /// Inputs to show in the switch menu: the monitor's own inputs when it
    /// reported them, otherwise the common set (minus the rare DisplayPort 2).
    private var inputOptions: [(value: UInt16, name: String)] {
        guard !display.supportedInputs.isEmpty else {
            return VCP.Input.all.filter { $0.value != 0x10 }
        }
        return display.supportedInputs.map { value in
            (value, VCP.Input.name(for: value) ?? String(format: "Input 0x%02X", value))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(display.name)
                    .font(.headline)
                if !display.respondsToDDC {
                    Text("No DDC reply")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("The monitor did not answer DDC reads. Controls may still work; enable DDC/CI in the monitor's on-screen menu if they don't.")
                }
                Spacer()
                Menu {
                    ForEach(inputOptions, id: \.value) { input in
                        Button {
                            display.setInput(input.value)
                        } label: {
                            if display.currentInput == input.value {
                                Label(input.name, systemImage: "checkmark")
                            } else {
                                Text(input.name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.2.swap")
                        .frame(width: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("Switch the monitor's input source (e.g. hand it to a console)")

                Button {
                    display.togglePower()
                } label: {
                    Image(systemName: "power")
                        .frame(width: 16)
                }
                .glassIconButton()
                .foregroundStyle(display.isOn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .help(display.isOn
                      ? LocalizedStringKey("Turn this monitor off (cut the connection)")
                      : LocalizedStringKey("Turn this monitor back on"))
            }

            Group {
                if showBrightness {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Slider(value: Binding(
                            get: { display.brightness },
                            set: { display.setBrightness(appState.snapped($0)) }
                        ))
                        .tint(.blue)
                        if appState.showSliderPercentages {
                            PercentLabel(value: display.brightness)
                        }
                        if appState.displayManager.displays.count > 1 {
                            Button {
                                appState.brightnessLinked = true
                            } label: {
                                Image(systemName: "link")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Link brightness — control all displays with one slider")
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Slider(value: Binding(
                        get: { display.contrast },
                        set: { display.setContrast(appState.snapped($0)) }
                    ))
                    .tint(.blue)
                    if appState.showSliderPercentages {
                        PercentLabel(value: display.contrast)
                    }
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
                        set: { display.setVolume(appState.snapped($0)) }
                    ))
                    .tint(.blue)
                    if appState.showSliderPercentages {
                        PercentLabel(value: display.muted ? 0 : display.volume)
                    }
                }
            }
            .disabled(!display.isOn)
            .opacity(display.isOn ? 1 : 0.4)
        }
        .padding(12)
    }
}

/// A fixed-width, right-aligned percentage label shown beside a slider.
private struct PercentLabel: View {
    let value: Float

    var body: some View {
        // `.percent` expects a fraction and places the % sign per the
        // current locale (e.g. "50%" in English, "%50" in Turkish).
        Text(Double(value).formatted(.percent.precision(.fractionLength(0))))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 40, alignment: .trailing)
    }
}
