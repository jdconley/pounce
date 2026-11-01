import SpriteKit
import UIKit

/// Particle bursts drawn from the `FX` atlas.
enum BurstKind: CaseIterable {
    case stars, fur, yarn, sparkle, confetti
}

/// The table's juice kit (spec §9.1): particle bursts built in code from `fx-*` textures and
/// the reusable verbs (pop, squash, nope, shake, arc). Every action here is relative or ends
/// where it started, so a node's resting transform is never lost.
///
/// Emitters are capped (spec §9.2): birth rate ≤ 80/s, particle lifetime ≤ 0.8 s, and at most
/// 60 particles alive across every burst on the table; a burst past the budget shrinks or is
/// skipped. Reduce Motion halves every burst.
@MainActor
enum Effects {
    static let maxBirthRate: CGFloat = 80
    static let maxLifetime: CGFloat = 0.8
    static let maxParticles = 60

    /// Particles promised to bursts still on screen.
    private(set) static var liveParticles = 0

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    // MARK: bursts

    private struct Recipe {
        let texture: String
        let count: Int
        let size: CGFloat
        let speed: CGFloat
        let speedRange: CGFloat
        let lifetime: CGFloat
        let lifetimeRange: CGFloat
        var gravity: CGFloat = 0
        var spin: CGFloat = 2
        var shrink: CGFloat = -0.6
        var spread: CGFloat = 6
    }

    private static func recipe(_ kind: BurstKind) -> Recipe {
        switch kind {
        case .stars:
            Recipe(texture: ArtName.fxStar, count: 8, size: 18, speed: 150, speedRange: 60, lifetime: 0.5, lifetimeRange: 0.2)
        case .fur:
            Recipe(texture: ArtName.fxFur, count: 14, size: 20, speed: 130, speedRange: 60, lifetime: 0.6, lifetimeRange: 0.2,
                   gravity: -260, spin: 3, shrink: -0.4, spread: 14)
        case .yarn:
            Recipe(texture: ArtName.fxYarn, count: 10, size: 18, speed: 140, speedRange: 50, lifetime: 0.6, lifetimeRange: 0.2,
                   gravity: -200, spin: 4)
        case .sparkle:
            Recipe(texture: ArtName.fxSparkle, count: 10, size: 20, speed: 70, speedRange: 40, lifetime: 0.55, lifetimeRange: 0.2,
                   spin: 1, shrink: -0.9, spread: 18)
        case .confetti:
            Recipe(texture: ArtName.fxConfetti, count: 24, size: 14, speed: 190, speedRange: 80, lifetime: 0.7, lifetimeRange: 0.1,
                   gravity: -300, spin: 6, shrink: -0.2, spread: 10)
        }
    }

    /// A one-shot burst of `kind` at `point` in `parent`, alive only while it draws.
    static func burst(_ kind: BurstKind, at point: CGPoint, in parent: SKNode, director: AnimationDirector) {
        let r = recipe(kind)
        let wanted = reduceMotion ? max(r.count / 2, 1) : r.count
        let count = min(wanted, maxParticles - liveParticles)
        guard count >= 2 else { return }
        liveParticles += count

        let e = SKEmitterNode()
        e.particleTexture = TableArt.texture(r.texture, atlas: ArtName.Atlas.fx)
        e.particleSize = CGSize(width: r.size, height: r.size)
        e.particleBirthRate = maxBirthRate
        e.numParticlesToEmit = count
        let lifetime = min(r.lifetime, maxLifetime - r.lifetimeRange / 2)
        e.particleLifetime = lifetime
        e.particleLifetimeRange = r.lifetimeRange  // lifetime ± range/2 stays ≤ maxLifetime
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = .pi * 2
        e.particleSpeed = r.speed
        e.particleSpeedRange = r.speedRange
        e.yAcceleration = r.gravity
        e.particlePositionRange = CGVector(dx: r.spread, dy: r.spread)
        e.particleScale = 1
        e.particleScaleRange = 0.4
        e.particleScaleSpeed = r.shrink
        e.particleAlpha = 1
        e.particleAlphaSpeed = -1 / (lifetime + r.lifetimeRange / 2)
        e.particleRotationRange = .pi * 2
        e.particleRotationSpeed = r.spin
        e.particleColorBlendFactor = 0
        e.particleBlendMode = .alpha
        e.zPosition = 5
        let emitting = TimeInterval(CGFloat(count) / maxBirthRate)
        director.emit(e, at: point, in: parent, lifetime: emitting + TimeInterval(maxLifetime)) {
            liveParticles -= count
        }
    }

    // MARK: verbs

    /// Pop: scale 0 → 1.15 → 1.0 in 0.22 s, ease-out-back.
    static func pop() -> SKAction {
        .sequence([
            .scale(to: 0, duration: 0),
            .scale(to: 1.15, duration: 0.14).eased(.easeOut),
            .scale(to: 1, duration: 0.08).eased(.easeInEaseOut),
        ])
    }

    /// Squash: 1.0 → (1.15, 0.85) → 1.0 in 0.14 s, relative to the node's current scale.
    static func squash() -> SKAction {
        .sequence([
            .scaleX(by: 1.15, y: 0.85, duration: 0.07).eased(.easeOut),
            .scaleX(by: 1 / 1.15, y: 1 / 0.85, duration: 0.07).eased(.easeIn),
        ])
    }

    /// Nope: three quick ±6° wiggles that end at the starting angle. Reduce Motion: a dim blink.
    static func nope() -> SKAction {
        if reduceMotion {
            return .sequence([.fadeAlpha(by: -0.5, duration: 0.08), .fadeAlpha(by: 0.5, duration: 0.08)])
        }
        let d = CGFloat.pi / 30
        var steps: [SKAction] = [.rotate(byAngle: d, duration: 0.04)]
        for _ in 0..<2 {
            steps.append(.rotate(byAngle: -2 * d, duration: 0.06))
            steps.append(.rotate(byAngle: 2 * d, duration: 0.06))
        }
        steps.append(.rotate(byAngle: -2 * d, duration: 0.06))
        steps.append(.rotate(byAngle: d, duration: 0.04))
        return .sequence(steps)
    }

    /// Screen shake of `node` around where it is now: `amplitude` points, decaying, back home
    /// at the end. Reduce Motion: nothing (a wait of the same length keeps timelines aligned).
    static func shake(_ node: SKNode, amplitude: CGFloat, duration: TimeInterval) -> SKAction {
        guard !reduceMotion, duration > 0 else { return .wait(forDuration: max(duration, 0)) }
        let home = node.position
        let steps = max(Int(duration / 0.025), 4)
        let dt = duration / Double(steps + 1)
        var moves: [SKAction] = []
        for i in 0..<steps {
            let k = amplitude * (1 - CGFloat(i) / CGFloat(steps))
            let sign: CGFloat = i.isMultiple(of: 2) ? 1 : -1
            let dy = CGFloat.random(in: -0.5...0.5) * k
            moves.append(.move(to: CGPoint(x: home.x + sign * k, y: home.y + dy), duration: dt))
        }
        moves.append(.move(to: home, duration: dt))
        return .sequence(moves)
    }

    /// A move along a parabola from `start` to `end`, peaking `lift` points above the higher
    /// end, eased in and out.
    static func arc(from start: CGPoint, to end: CGPoint, lift: CGFloat, duration: TimeInterval) -> SKAction {
        let path = CGMutablePath()
        path.move(to: start)
        let control = CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + lift * 2)
        path.addQuadCurve(to: end, control: control)
        return SKAction.follow(path, asOffset: false, orientToPath: false, duration: duration).eased(.easeInEaseOut)
    }

    /// A card flight: arc + spin + scale, or under Reduce Motion a 0.15 s fade out and back in
    /// at the target. Ends exactly at `end`, `rotation` and `scale`.
    static func fly(
        from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.3, lift: CGFloat = 40,
        spins: CGFloat = 0, rotation: CGFloat = 0, scale: CGFloat = 1
    ) -> SKAction {
        if reduceMotion {
            return .sequence([
                .fadeOut(withDuration: 0.075),
                .group([.move(to: end, duration: 0), .rotate(toAngle: rotation, duration: 0), .scale(to: scale, duration: 0)]),
                .fadeIn(withDuration: 0.075),
            ])
        }
        var parts: [SKAction] = [arc(from: start, to: end, lift: lift, duration: duration), .scale(to: scale, duration: duration)]
        if spins != 0 {
            parts.append(.sequence([
                .rotate(byAngle: spins * 2 * .pi, duration: duration * 0.85),
                .rotate(toAngle: rotation, duration: duration * 0.15, shortestUnitArc: true),
            ]))
        } else {
            parts.append(.rotate(toAngle: rotation, duration: duration, shortestUnitArc: true))
        }
        return .group(parts)
    }
}
