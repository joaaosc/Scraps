import Metal
import SwiftUI

/// A brief GPU-rendered rim on creation and appearance changes. It never
/// filters the native editor and stops scheduling frames when the effect ends.
public struct StickyMetalAccent: View {
    public let trigger: String
    public let tint: Color
    @State private var active = false
    @State private var started = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    private static let hasMetal = MTLCreateSystemDefaultDevice() != nil

    public init(trigger: String, tint: Color = .accentColor) {
        self.trigger = trigger
        self.tint = tint
    }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { context in
            let enabled = active && Self.hasMetal
            let progress = min(1, max(0, context.date.timeIntervalSince(started) / 0.85))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(tint.opacity(0.55), lineWidth: 2)
                .visualEffect { content, geometry in
                    content.colorEffect(ShaderLibrary.bundle(.module).scrapsRim(
                        .float(Float(progress)), .float2(Float(geometry.size.width), Float(geometry.size.height))
                    ), isEnabled: enabled)
                }
                .opacity(active ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: trigger) {
            active = false
            guard Self.hasMetal, !reduceMotion, !reduceTransparency, contrast != .increased,
                  !ProcessInfo.processInfo.isLowPowerModeEnabled, scenePhase == .active else { return }
            started = Date(); active = true
            do { try await Task.sleep(for: .milliseconds(850)) } catch { return }
            active = false
        }
        .onChange(of: reduceMotion) { _, value in if value { active = false } }
        .onChange(of: reduceTransparency) { _, value in if value { active = false } }
        .onChange(of: contrast) { _, value in if value == .increased { active = false } }
        .onChange(of: scenePhase) { _, value in if value != .active { active = false } }
    }
}
