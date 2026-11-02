import SwiftUI

// Motion modifiers. Each respects Reduce Motion by swapping movement for a short fade, and runs
// at the app's pace (`Pace`).

private struct JuiceValues {
    var scale: Double = 1
    var rotation: Double = 0
    var offsetX: Double = 0
    var opacity: Double = 1
}

private struct PopModifier<T: Equatable & Sendable>: ViewModifier {
    let trigger: T
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let k = reduceMotion ? 0.0 : 1.0
        content.keyframeAnimator(initialValue: JuiceValues(), trigger: trigger) { view, v in
            view.scaleEffect(v.scale).opacity(v.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(1 + 0.3 * k, duration: Pace.seconds(0.10))
                SpringKeyframe(1, duration: Pace.seconds(0.35), spring: .bouncy)
            }
            KeyframeTrack(\.opacity) {
                CubicKeyframe(1 - 0.5 * (1 - k), duration: Pace.seconds(0.10))
                CubicKeyframe(1, duration: Pace.seconds(0.25))
            }
        }
    }
}

private struct WiggleModifier<T: Equatable & Sendable>: ViewModifier {
    let trigger: T
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let k = reduceMotion ? 0.0 : 1.0
        content.keyframeAnimator(initialValue: JuiceValues(), trigger: trigger) { view, v in
            view.rotationEffect(.degrees(v.rotation)).opacity(v.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.rotation) {
                CubicKeyframe(10 * k, duration: Pace.seconds(0.07))
                CubicKeyframe(-8 * k, duration: Pace.seconds(0.10))
                CubicKeyframe(5 * k, duration: Pace.seconds(0.09))
                CubicKeyframe(-3 * k, duration: Pace.seconds(0.08))
                CubicKeyframe(0, duration: Pace.seconds(0.07))
            }
            KeyframeTrack(\.opacity) {
                CubicKeyframe(1 - 0.5 * (1 - k), duration: Pace.seconds(0.15))
                CubicKeyframe(1, duration: Pace.seconds(0.26))
            }
        }
    }
}

private struct ShakeModifier<T: Equatable & Sendable>: ViewModifier {
    let trigger: T
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let k = reduceMotion ? 0.0 : 1.0
        content.keyframeAnimator(initialValue: JuiceValues(), trigger: trigger) { view, v in
            view.offset(x: v.offsetX).opacity(v.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.offsetX) {
                CubicKeyframe(-12 * k, duration: Pace.seconds(0.05))
                CubicKeyframe(10 * k, duration: Pace.seconds(0.08))
                CubicKeyframe(-8 * k, duration: Pace.seconds(0.08))
                CubicKeyframe(5 * k, duration: Pace.seconds(0.07))
                CubicKeyframe(0, duration: Pace.seconds(0.06))
            }
            KeyframeTrack(\.opacity) {
                CubicKeyframe(1 - 0.5 * (1 - k), duration: Pace.seconds(0.15))
                CubicKeyframe(1, duration: Pace.seconds(0.19))
            }
        }
    }
}

private struct BounceLoopModifier: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: reduceMotion ? 0 : (up ? -8 : 0))
            .scaleEffect(reduceMotion ? 1 : (up ? 1.04 : 1))
            .opacity(reduceMotion && up ? 0.7 : 1)
            .onAppear { update() }
            .onChange(of: active) { update() }
            .onChange(of: reduceMotion) { update() }
    }

    private func update() {
        if active {
            withAnimation(.easeInOut(duration: reduceMotion ? 0.9 : 0.45).repeatForever(autoreverses: true).paced) {
                up = true
            }
        } else {
            withAnimation(.easeOut(duration: Pace.seconds(0.2)).paced) { up = false }
        }
    }
}

extension View {
    /// Quick overshoot scale each time `trigger` changes.
    func pop<T: Equatable & Sendable>(trigger: T) -> some View { modifier(PopModifier(trigger: trigger)) }

    /// Rotating waggle each time `trigger` changes.
    func wiggle<T: Equatable & Sendable>(trigger: T) -> some View { modifier(WiggleModifier(trigger: trigger)) }

    /// Horizontal "nope" shake each time `trigger` changes.
    func shake<T: Equatable & Sendable>(trigger: T) -> some View { modifier(ShakeModifier(trigger: trigger)) }

    /// Endless happy bounce while `active`.
    func bounceLoop(active: Bool) -> some View { modifier(BounceLoopModifier(active: active)) }
}
