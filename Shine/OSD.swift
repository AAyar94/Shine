//
//  OSD.swift
//  Shine
//
//  A lightweight system-style HUD shown on the target display when the
//  brightness / volume keys adjust an external monitor.
//

import AppKit
import SwiftUI

/// Private OSD.framework interface for driving the real macOS system HUD.
@objc private protocol OSDManagerProtocol {
    func showImage(_ image: Int, onDisplayID: CGDirectDisplayID, priority: UInt32,
                   msecUntilFade: UInt32, filledChiclets: UInt32, totalChiclets: UInt32, locked: Bool)
}

@MainActor
final class OSD {
    static let shared = OSD()

    enum Kind {
        case brightness
        case volume

        var symbolName: String {
            switch self {
            case .brightness: "sun.max.fill"
            case .volume: "speaker.wave.3.fill"
            }
        }

        /// Image constants from the private OSD framework (kOSDGraphic…).
        func systemImage(muted: Bool) -> Int {
            switch self {
            case .brightness: 1            // kOSDGraphicBacklight
            case .volume: muted ? 4 : 3    // kOSDGraphicAudioSpeaker(Muted)
            }
        }
    }

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// The shared OSDManager, resolved once. Nil if the private framework is
    /// unavailable — callers then fall back to Shine's own overlay.
    private static let systemManager: OSDManagerProtocol? = {
        _ = dlopen("/System/Library/PrivateFrameworks/OSD.framework/Versions/A/OSD", RTLD_LAZY)
        guard let cls = NSClassFromString("OSDManager"),
              let shared = (cls as AnyObject).perform(NSSelectorFromString("sharedManager"))?
                  .takeUnretainedValue()
        else { return nil }
        return unsafeBitCast(shared, to: OSDManagerProtocol.self)
    }()

    private init() {}

    func show(_ kind: Kind, level: Float, on screen: NSScreen?) {
        if AppState.shared.useSystemOSD, showSystem(kind, level: level, on: screen) {
            return
        }
        guard let screen = screen ?? NSScreen.main else { return }

        let content = OSDContent(kind: kind, level: level)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 64)

        let panel = self.panel ?? makePanel()
        panel.contentView = hosting

        let frame = screen.frame
        let origin = NSPoint(x: frame.midX - hosting.frame.width / 2,
                             y: frame.minY + 120)
        panel.setFrame(NSRect(origin: origin, size: hosting.frame.size), display: true)
        panel.orderFrontRegardless()
        panel.alphaValue = 1

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    /// Drives the real macOS HUD via OSDManager. Returns false (so the caller
    /// can fall back) when the private framework isn't available.
    private func showSystem(_ kind: Kind, level: Float, on screen: NSScreen?) -> Bool {
        guard let manager = Self.systemManager else { return false }
        let target = screen ?? NSScreen.main
        let displayID = target.flatMap {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        } ?? CGMainDisplayID()

        let clamped = min(max(level, 0), 1)
        let muted = kind == .volume && clamped == 0
        manager.showImage(kind.systemImage(muted: muted),
                          onDisplayID: displayID,
                          priority: 0x1F4,
                          msecUntilFade: 1500,
                          filledChiclets: UInt32((clamped * 16).rounded()),
                          totalChiclets: 16,
                          locked: false)
        return true
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel
        return panel
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

private struct OSDContent: View {
    let kind: OSD.Kind
    let level: Float

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: level == 0 && kind == .volume ? "speaker.slash.fill" : kind.symbolName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28)

            // 16 segments, mirroring the classic macOS key-press HUD.
            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Float(index) < level * 16 ? Color.white : Color.white.opacity(0.25))
                        .frame(height: 7)
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 220, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
    }
}
