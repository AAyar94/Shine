//
//  OSD.swift
//  Shine
//
//  A system-style HUD shown on the target display when the brightness / volume
//  keys adjust an external monitor. Modeled on the macOS Tahoe system OSD: a
//  compact card in the top-right corner showing the monitor's name, an icon and
//  a level bar. On macOS 26+ it uses real Liquid Glass via NSGlassEffectView —
//  which keeps its content legible as the glass adapts — and the frosted HUD
//  material on earlier macOS. We draw our own because Tahoe's system OSD no
//  longer renders third-party slider values.
//

import AppKit
import SwiftUI

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
    }

    /// Size of the card, echoing the macOS Tahoe system OSD proportions.
    private static let size = NSSize(width: 300, height: 78)
    private static let cornerRadius: CGFloat = 20

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private init() {}

    func show(_ kind: Kind, level: Float, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }

        let panel = self.panel ?? makePanel()
        panel.contentView = makeContentView(kind: kind, level: level,
                                             name: screen.localizedName)

        // Top-right corner, just below the menu bar, like the Tahoe system OSD.
        let area = screen.visibleFrame
        let margin: CGFloat = 16
        let origin = NSPoint(x: area.maxX - Self.size.width - margin,
                             y: area.maxY - Self.size.height - 12)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
        // Recompute the drop shadow to follow the rounded card, not the window rect.
        panel.invalidateShadow()
        panel.orderFrontRegardless()
        panel.alphaValue = 1

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    /// Real behind-window blur (works on every macOS, unlike the buggy Tahoe
    /// NSGlassEffectView) with the SwiftUI content — which adds the glass sheen
    /// and edge highlight — layered on top.
    private func makeContentView(kind: Kind, level: Float, name: String) -> NSView {
        let bounds = NSRect(origin: .zero, size: Self.size)

        let effect = NSVisualEffectView(frame: bounds)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        // Round via a mask image — clipping an NSVisualEffectView with
        // layer.cornerRadius leaves dark corner artifacts.
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        let hosting = NSHostingView(rootView: OSDContent(kind: kind, level: level, name: name))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        effect.addSubview(hosting)
        return effect
    }

    /// A resizable rounded-rectangle mask used to clip the visual-effect view
    /// cleanly (no dark corners).
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
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

struct OSDContent: View {
    let kind: OSD.Kind
    let level: Float
    let name: String
    /// Foreground color: adaptive `.primary` on Liquid Glass, `.white` on the
    /// always-dark frosted material.
    var tint: Color = .white

    private var fraction: CGFloat { CGFloat(min(max(level, 0), 1)) }

    /// Small "min" icon at the left end of the slider.
    private var minIcon: String {
        kind == .brightness ? "sun.min.fill" : "speaker.fill"
    }

    /// Large "max" icon at the right end (muted speaker when volume is off).
    private var maxIcon: String {
        switch kind {
        case .brightness: "sun.max.fill"
        case .volume: level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint.opacity(0.9))
                .lineLimit(1)

            HStack(spacing: 9) {
                Image(systemName: minIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint.opacity(0.9))
                    .frame(width: 16)

                DottedSlider(fraction: fraction, tint: tint)
                    .frame(height: 8)

                Image(systemName: maxIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 22)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 300, height: 78, alignment: .leading)
        // Sheen + specular highlight + bright rim sell the glass look on top of
        // the real blur behind the window.
        .background(
            LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.02)],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(glassShape)
                .allowsHitTesting(false)
        )
        .overlay(
            // Very soft light reflection near the top.
            glassShape
                .fill(LinearGradient(colors: [.white.opacity(0.07), .clear],
                                     startPoint: .top, endPoint: .center))
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        )
        .overlay(
            // Faint uniform rim.
            glassShape
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        )
    }

    private var glassShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }
}

/// The macOS-style level track: a dotted rail with a solid rounded fill over the
/// portion up to the current value.
private struct DottedSlider: View {
    let fraction: CGFloat
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let dotCount = max(2, Int(width / 11))
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<dotCount, id: \.self) { index in
                        Circle()
                            .fill(tint.opacity(0.35))
                            .frame(width: 3, height: 3)
                        if index < dotCount - 1 { Spacer(minLength: 0) }
                    }
                }
                Capsule()
                    .fill(tint)
                    .frame(width: max(6, width * fraction), height: 6)
            }
            .frame(height: geo.size.height, alignment: .center)
        }
    }
}
