//
//  KeyboardManager.swift
//  Shine
//
//  Intercepts the keyboard brightness / volume media keys with a CGEventTap
//  (requires the Accessibility permission) and redirects them to DDC.
//

import AppKit
import ApplicationServices

// NX media key codes delivered in NSEvent.systemDefined subtype 8.
private enum MediaKey: Int {
    case soundUp = 0        // NX_KEYTYPE_SOUND_UP
    case soundDown = 1      // NX_KEYTYPE_SOUND_DOWN
    case brightnessUp = 2   // NX_KEYTYPE_BRIGHTNESS_UP
    case brightnessDown = 3 // NX_KEYTYPE_BRIGHTNESS_DOWN
    case mute = 7           // NX_KEYTYPE_MUTE
}

@MainActor
final class KeyboardManager {
    /// Called for a media key. Return true to swallow the event (we handled
    /// it via DDC), false to let the system process it normally.
    var handler: ((_ key: Int, _ isPressed: Bool, _ isRepeat: Bool) -> Bool)?

    private var eventTap: CFMachPort?

    // MARK: Accessibility permission

    static func isAccessibilityTrusted(promptIfNeeded: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Event tap

    var isRunning: Bool { eventTap != nil }

    /// Installs the tap on the main run loop. Requires Accessibility.
    func start() {
        guard eventTap == nil else { return }

        let systemDefinedMask = CGEventMask(1 << 14) // NX_SYSDEFINED
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: systemDefinedMask,
            callback: { _, type, event, refcon in
                let manager = Unmanaged<KeyboardManager>.fromOpaque(refcon!).takeUnretainedValue()
                // The tap lives on the main run loop, so this is the main thread.
                return MainActor.assumeIsolated {
                    manager.process(type: type, event: event)
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Shine: failed to create event tap (accessibility not granted?)")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that stall or when secure input kicks in; recover.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == 14, // NX_SYSDEFINED
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let isPressed = ((keyFlags & 0xFF00) >> 8) == 0x0A
        let isRepeat = (keyFlags & 0x1) == 0x1

        guard MediaKey(rawValue: keyCode) != nil else {
            return Unmanaged.passUnretained(event)
        }

        let swallow = handler?(keyCode, isPressed, isRepeat) ?? false
        return swallow ? nil : Unmanaged.passUnretained(event)
    }
}

// MARK: - Key routing

extension AppState {
    /// Decides whether a media key targets an external DDC display.
    /// Returns true when the event was handled (and must be swallowed).
    func handleMediaKey(code: Int, isPressed: Bool, isRepeat: Bool) -> Bool {
        guard let key = MediaKey(rawValue: code) else { return false }

        switch key {
        case .brightnessUp, .brightnessDown:
            guard brightnessKeysEnabled,
                  let target = displayManager.display(under: currentMouseLocation()) else { return false }
            if isPressed {
                target.stepBrightness(up: key == .brightnessUp)
                OSD.shared.show(.brightness, level: target.brightness, on: target.screen)
            }
            return true // swallow key-up too so the system never sees the key

        case .soundUp, .soundDown:
            let targets = displayManager.volumeKeyTargets
            guard volumeKeysEnabled, let lead = targets.first else { return false }
            if isPressed {
                for target in targets {
                    target.stepVolume(up: key == .soundUp)
                }
                OSD.shared.show(.volume, level: lead.muted ? 0 : lead.volume, on: lead.screen)
            }
            return true

        case .mute:
            let targets = displayManager.volumeKeyTargets
            guard volumeKeysEnabled, let lead = targets.first else { return false }
            if isPressed, !isRepeat {
                let newMuted = !lead.muted
                for target in targets {
                    target.setMuted(newMuted)
                }
                OSD.shared.show(.volume, level: newMuted ? 0 : lead.volume, on: lead.screen)
            }
            return true
        }
    }

    private func currentMouseLocation() -> CGPoint {
        // CGEvent gives the location in CG global (top-left origin) coordinates.
        CGEvent(source: nil)?.location ?? .zero
    }
}
