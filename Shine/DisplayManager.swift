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
    private(set) var maxVolume: UInt16 = 100

    /// Normalized 0...1 values mirrored from / written to the monitor.
    private(set) var brightness: Float = 0.75
    private(set) var volume: Float = 0.25
    private(set) var muted = false

    /// True if the monitor answered at least one DDC read.
    private(set) var respondsToDDC = false

    var id: CGDirectDisplayID { displayID }

    init(displayID: CGDirectDisplayID, name: String, port: DDCPort) {
        self.displayID = displayID
        self.name = name
        self.port = port
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
        if let value = port.read(VCP.volume) {
            maxVolume = value.max
            volume = Float(value.current) / Float(value.max)
            respondsToDDC = true
        }
        if let value = port.read(VCP.mute) {
            muted = value.current == 1
        }
    }

    func setBrightness(_ normalized: Float) {
        let clamped = min(max(normalized, 0), 1)
        brightness = clamped
        port.write(VCP.brightness, value: UInt16((Float(maxBrightness) * clamped).rounded()))
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

    /// False on machines where the private IOAVService API is unavailable.
    var ddcSupported: Bool { DDCPort.isSupported }

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
            ExternalDisplay(displayID: id, name: Self.name(for: id), port: port)
        }
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
        }?.localizedName ?? "External Display"
    }
}
