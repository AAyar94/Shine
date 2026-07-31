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
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                menuContent
            }
        } else {
            menuContent
        }
    }

    private var menuContent: some View {
        @Bindable var appState = appState

        return VStack(alignment: .leading, spacing: 12) {
            if appState.updateAvailable {
                updateBanner.controlCenterGlassCard()
            }

            if !appState.accessibilityGranted {
                permissionBanner.controlCenterGlassCard()
            }

            if !appState.displayManager.ddcSupported {
                Label("DDC is not available on this Mac.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                    .padding(12)
                    .controlCenterGlassCard()
            } else if appState.displayManager.displays.isEmpty {
                Label("No external display detected.", systemImage: "display.trianglebadge.exclamationmark")
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(12)
                    .controlCenterGlassCard()
            } else {
                if appState.brightnessLinked && appState.displayManager.displays.count > 1 {
                    linkedBrightnessSlider
                        .padding(12)
                        .controlCenterGlassCard()
                }
                ForEach(appState.displayManager.displays) { display in
                    DisplaySection(display: display, showBrightness: !appState.brightnessLinked || appState.displayManager.displays.count <= 1)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Brightness keys control monitor under pointer", isOn: $appState.brightnessKeysEnabled)
                    .toggleStyle(GlassCheckboxToggleStyle())
                Toggle("Volume keys control monitor speakers", isOn: $appState.volumeKeysEnabled)
                    .toggleStyle(GlassCheckboxToggleStyle())
                Divider()
                Toggle("Show percentage next to sliders", isOn: $appState.showSliderPercentages)
                    .toggleStyle(GlassCheckboxToggleStyle())
                Toggle("Snap sliders to 25% / 50% / 75% / 100%", isOn: $appState.snapToQuarters)
                    .toggleStyle(GlassCheckboxToggleStyle())
                Toggle("Launch Shine at login", isOn: $appState.launchAtLogin)
                    .toggleStyle(GlassCheckboxToggleStyle())
            }
            .padding(12)
            .controlCenterGlassCard()

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
            .padding(8)
            .controlCenterGlassCard()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 5)
        .frame( maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
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
                    .foregroundStyle(.white.opacity(0.82))
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
                        .foregroundStyle(.white.opacity(0.82))
                }
                .buttonStyle(.plain)
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
                .foregroundStyle(.white.opacity(0.82))
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accessibility permission needed", systemImage: "hand.raised.fill")
                .font(.headline)
            Text("Shine needs Accessibility access to capture the keyboard brightness and volume keys.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
            Text("After an update, remove Shine from the list and re-add it.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
            Button("Open System Settings…") {
                KeyboardManager.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    /// A discrete interactive Liquid Glass surface, matching the grouped
    /// controls in Control Center instead of one flat sheet behind the menu.
    @ViewBuilder
    func controlCenterGlassCard() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                .clear.interactive(),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        } else {
            self.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }
}

/// Keeps checkbox outlines and checkmarks legible on a transparent glass card.
private struct GlassCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(configuration.isOn ? .white.opacity(0.20) : .clear)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.white.opacity(configuration.isOn ? 1 : 0.72), lineWidth: 1.25)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 16, height: 16)
                configuration.label
            }
        }
        .buttonStyle(.plain)
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
                        .foregroundStyle(.white.opacity(0.82))
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
                .foregroundStyle(.white.opacity(0.82))
                .help("Switch the monitor's input source (e.g. hand it to a console)")

                Button {
                    display.togglePower()
                } label: {
                    Image(systemName: "power")
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(display.isOn ? 0.82 : 0.45))
                .help(display.isOn
                      ? LocalizedStringKey("Turn this monitor off (cut the connection)")
                      : LocalizedStringKey("Turn this monitor back on"))
            }

            Group {
                if showBrightness {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.white.opacity(0.82))
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
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                            .buttonStyle(.plain)
                            .help("Link brightness — control all displays with one slider")
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.white.opacity(0.82))
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
                    .foregroundStyle(.white.opacity(0.82))
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
        .controlCenterGlassCard()
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
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: 40, alignment: .trailing)
    }
}
