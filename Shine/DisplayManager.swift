//
//  DisplayManager.swift
//  Shine
//
//  Enumerates external displays, pairs each CGDisplay with its DDC I2C port
//  (matched by EDID vendor/product/serial), and exposes observable controls.
//

import AppKit
import CoreGraphics
import Observation

// MARK: - ExternalDisplay

@MainActor
@Observable
final class ExternalDisplay: Identifiable {
    let displayID: CGDirectDisplayID
    let name: String
    private let port: DDCPort

    private(set) var maxBrightness: UInt16 = 100
    private(set) var maxContrast: UInt16 = 100
    private(set) var maxVolume: UInt16 = 100

    /// Normalized 0...1 values mirrored from / written to the monitor.
    private(set) var brightness: Float = 0.75
    private(set) var contrast: Float = 0.5
    private(set) var volume: Float = 0.25
    private(set) var muted = false

    /// Whether the monitor is powered on. Tracked locally because the Power Mode
    /// VCP is often not readable; toggled by the power button in the menu.
    private(set) var isOn = true

    /// True if the monitor answered at least one DDC read.
    private(set) var respondsToDDC = false

    /// The monitor's active input source (VCP 60), when readable — the input the
    /// Mac is showing on. Used to mark the current input and to switch away to
    /// another (e.g. a game console) and back.
    private(set) var currentInput: UInt16?

    /// Input-source values (VCP 60) this monitor actually exposes, read from its
    /// DDC capabilities string. Empty when the monitor didn't report them — the
    /// menu then falls back to the common inputs.
    let supportedInputs: [UInt16]

    var id: CGDirectDisplayID { displayID }

    init(displayID: CGDirectDisplayID, name: String, port: DDCPort, supportedInputs: [UInt16]) {
        self.displayID = displayID
        self.name = name
        self.port = port
        self.supportedInputs = supportedInputs
        refreshFromMonitor()
    }

    var screen: NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }
    }

    /// Pulls the current brightness/volume/mute state from the monitor.
    func refreshFromMonitor() {
        if let value = port.read(VCP.brightness) {
            maxBrightness = value.max
            brightness = Float(value.current) / Float(value.max)
            respondsToDDC = true
        }
        if let value = port.read(VCP.contrast) {
            maxContrast = value.max
            contrast = Float(value.current) / Float(value.max)
            respondsToDDC = true
        }
        if let value = port.read(VCP.volume) {
            maxVolume = value.max
            volume = Float(value.current) / Float(value.max)
            respondsToDDC = true
        }
        if let value = port.read(VCP.mute) {
            muted = value.current == 1
        }
        refreshInput()
    }

    /// Re-reads just the active input source (VCP 60). A monitor changes input on
    /// its own — auto-scanning to another live input when the current one goes
    /// away, or from its own on-screen menu — so the value we wrote last is not
    /// necessarily the one it is showing. Cheap enough (one DDC read) to run
    /// every time the menu opens, unlike the full refresh.
    func refreshInput() {
        if let value = port.read(VCP.inputSource) {
            currentInput = value.current
            respondsToDDC = true
        }
    }

    /// Switches the monitor's active input source (VCP 60). Handing the monitor
    /// to another device this way keeps the Mac's DDC channel alive, so we can
    /// switch it back later without unplugging anything.
    func setInput(_ value: UInt16) {
        currentInput = value
        port.write(VCP.inputSource, value: value)
    }

    func setBrightness(_ normalized: Float) {
        let clamped = min(max(normalized, 0), 1)
        brightness = clamped
        port.write(VCP.brightness, value: UInt16((Float(maxBrightness) * clamped).rounded()))
    }

    func setContrast(_ normalized: Float) {
        let clamped = min(max(normalized, 0), 1)
        contrast = clamped
        port.write(VCP.contrast, value: UInt16((Float(maxContrast) * clamped).rounded()))
    }

    func setVolume(_ normalized: Float) {
        let clamped = min(max(normalized, 0), 1)
        volume = clamped
        if muted, clamped > 0 { setMuted(false) }
        port.write(VCP.volume, value: UInt16((Float(maxVolume) * clamped).rounded()))
    }

    func setMuted(_ mute: Bool) {
        muted = mute
        // MCCS: 1 = mute, 2 = unmute
        port.write(VCP.mute, value: mute ? 1 : 2)
    }

    /// Cuts or restores the monitor's connection by driving DDC Power Mode.
    /// Off blanks the panel like pressing its power button; on wakes it again.
    func setPower(on: Bool) {
        isOn = on
        port.write(VCP.powerMode, value: on ? VCP.Power.on : VCP.Power.off)
    }

    func togglePower() {
        setPower(on: !isOn)
    }

    /// One key-press step is 1/16 of the range, like the macOS volume keys.
    func stepBrightness(up: Bool) {
        setBrightness(brightness + (up ? 1 : -1) / 16.0)
    }

    func stepVolume(up: Bool) {
        setVolume(volume + (up ? 1 : -1) / 16.0)
    }
}

// MARK: - DisplayManager

@MainActor
@Observable
final class DisplayManager {
    private(set) var displays: [ExternalDisplay] = []

    /// Supported input sources per physical monitor (keyed by EDID), cached so the
    /// slow capabilities read happens once per monitor rather than on every rescan.
    private var inputCache: [String: [UInt16]] = [:]

    /// False on machines where the private IOAVService API is unavailable.
    var ddcSupported: Bool { DDCPort.isSupported }

    /// Sets brightness on all displays that are on (used for linked mode).
    func setBrightnessAll(_ normalized: Float) {
        for display in displays where display.isOn {
            display.setBrightness(normalized)
        }
    }

    /// Steps brightness on all displays that are on (used for linked keyboard keys).
    func stepBrightnessAll(up: Bool) {
        for display in displays where display.isOn {
            display.stepBrightness(up: up)
        }
    }

    /// Re-reads every monitor's active input source, so the checkmark in the
    /// input menu reflects what the monitor is showing now rather than what we
    /// last asked it to show.
    func refreshInputs() {
        for display in displays {
            display.refreshInput()
        }
    }

    /// Average brightness across all displays that are on (used for linked slider).
    var averageBrightness: Float {
        let onDisplays = displays.filter { $0.isOn }
        guard !onDisplays.isEmpty else { return 0 }
        return onDisplays.reduce(0) { $0 + $1.brightness } / Float(onDisplays.count)
    }

    init() {
        rescan()
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            // Ignore the begin notifications; act once the change completed.
            guard !flags.contains(.beginConfigurationFlag) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                AppState.shared.displayManager.rescan()
            }
        }, nil)
    }

    func rescan() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        let externalIDs = ids.prefix(Int(count)).filter {
            CGDisplayIsBuiltin($0) == 0 && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay
        }

        let ports = DDCPort.externalPorts()
        var usedPorts = Set<Int>()
        var matched: [(CGDirectDisplayID, DDCPort)] = []
        var unmatchedIDs: [CGDirectDisplayID] = []

        // First pass: match by EDID vendor + product (+ serial when available).
        for id in externalIDs {
            let vendor = UInt16(truncatingIfNeeded: CGDisplayVendorNumber(id))
            let model = UInt16(truncatingIfNeeded: CGDisplayModelNumber(id))
            let serial = CGDisplaySerialNumber(id)

            let candidates = ports.indices.filter { index in
                guard !usedPorts.contains(index), let edid = ports[index].identity else { return false }
                return edid.vendorID == vendor && edid.productID == model
            }
            let best = candidates.first { serial != 0 && ports[$0].identity?.serial == serial }
                ?? candidates.first
            if let index = best {
                usedPorts.insert(index)
                matched.append((id, ports[index]))
            } else {
                unmatchedIDs.append(id)
            }
        }

        // Second pass: pair leftovers by order (covers ports without readable EDID).
        let remainingPorts = ports.indices.filter { !usedPorts.contains($0) }
        for (id, portIndex) in zip(unmatchedIDs, remainingPorts) {
            matched.append((id, ports[portIndex]))
        }

        displays = matched.map { id, port in
            ExternalDisplay(displayID: id, name: Self.name(for: id), port: port,
                            supportedInputs: supportedInputs(for: port))
        }
    }

    /// Returns the monitor's supported input sources, reading its DDC capabilities
    /// the first time and caching the result by EDID for subsequent rescans.
    private func supportedInputs(for port: DDCPort) -> [UInt16] {
        guard let edid = port.identity else { return [] }
        let key = "\(edid.vendorID)-\(edid.productID)-\(edid.serial)"
        if let cached = inputCache[key] { return cached }
        let inputs = port.readCapabilities().map(DDCPort.inputSourceValues(from:)) ?? []
        inputCache[key] = inputs
        return inputs
    }

    /// The display currently under the mouse pointer (CG global coordinates).
    func display(under point: CGPoint) -> ExternalDisplay? {
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(point, 1, &id, &count)
        guard count > 0 else { return nil }
        return displays.first { $0.displayID == id }
    }

    /// Displays targeted by the volume keys. When we can identify the current
    /// audio output device by name, we return the monitor(s) it matches — which
    /// is empty when the output is not one of our monitors (e.g. the Mac's own
    /// speakers), so the keys fall through to the system and change the device
    /// that is actually playing sound. Only when the output device is unknown
    /// do we fall back to all displays so the audible one still changes.
    var volumeKeyTargets: [ExternalDisplay] {
        guard let audioName = AudioOutput.defaultOutputDeviceName() else {
            return displays
        }
        return displays.filter {
            $0.name.caseInsensitiveCompare(audioName) == .orderedSame
                || audioName.localizedCaseInsensitiveContains($0.name)
                || $0.name.localizedCaseInsensitiveContains(audioName)
        }
    }

    private static func name(for displayID: CGDirectDisplayID) -> String {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }?.localizedName ?? String(localized: "External Display")
    }
}
