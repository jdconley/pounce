#if DEBUG
import PounceKit
import SpriteKit

/// A table the DEBUG autoplay can play: a press, its moves and its release at scene points,
/// through the same code a finger runs.
@MainActor
protocol Autoplaying: SKScene {
    /// The next drag, in scene points: out (a stash or hand piece onto the table) or back.
    func autoplayPath(out: Bool) -> (CGPoint, CGPoint)?
    func pressBegan(at point: CGPoint)
    func pressMoved(to point: CGPoint)
    func pressEnded(at point: CGPoint)
}

/// DEBUG `-autoplay`: a table plays its own drags, a frame at a time, out and back, over and over.
/// No UI test drives it, so nothing reads the accessibility tree or injects events while it plays:
/// frame times measured under it (`MainThreadWatchdog`, `FrameRateTests`) are the app's own
/// (`docs/main-thread.md`).
@MainActor
final class Autoplay: NSObject {
    static let enabled = CommandLine.arguments.contains("-autoplay")
    /// Frames each drag takes, and the frames of rest between two.
    static let dragFrames = 36
    static let restFrames = 48
    /// Seconds before the first drag: a UI test takes its baseline reading first (its reads of the
    /// screen cost the app frames, so none land on a drag).
    static let firstDragAfter: CFTimeInterval = 3

    private weak var scene: (any Autoplaying)?
    private var link: CADisplayLink?
    private var frame = 0
    private var from = CGPoint.zero
    private var to = CGPoint.zero
    private var out = true
    private var started: CFTimeInterval?

    /// Starts autoplay on `scene` under `-autoplay`; nil otherwise. It steps from its own display
    /// link: an idle table pauses its view, so the scene's `update` can't drive it.
    static func start(_ scene: any Autoplaying) -> Autoplay? {
        guard enabled else { return nil }
        let play = Autoplay()
        play.scene = scene
        let link = CADisplayLink(target: play, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        play.link = link
        return play
    }

    @objc private func tick() {
        guard let scene, scene.view != nil else {
            link?.invalidate()
            return
        }
        let now = CACurrentMediaTime()
        if started == nil { started = now }
        guard let started, now - started >= Self.firstDragAfter else { return }
        frame += 1
        if frame == Self.restFrames {
            guard let path = scene.autoplayPath(out: out) else {
                frame = 0
                return
            }
            (from, to) = path
            scene.pressBegan(at: from)
        } else if frame > Self.restFrames, frame < Self.restFrames + Self.dragFrames {
            let t = CGFloat(frame - Self.restFrames) / CGFloat(Self.dragFrames)
            let eased = t * t * (3 - 2 * t)
            scene.pressMoved(to: CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased))
        } else if frame == Self.restFrames + Self.dragFrames {
            scene.pressEnded(at: to)
            out.toggle()
            frame = 0
        }
    }
}

extension TilesScene: Autoplaying {
    /// The stash's first piece to the last piece of the rug's first set, or that piece back to
    /// the middle of the stash. With just the stash (Cards, off turn), its first piece along to
    /// its last piece's place, and the last back to the first's.
    func autoplayPath(out: Bool) -> (CGPoint, CGPoint)? {
        guard let layout else { return nil }
        if layout.arrangement == .controller {
            guard rackShown.count > 1, let first = rackShown.first.flatMap({ pieces[$0] }), let last = rackShown.last.flatMap({ pieces[$0] })
            else { return nil }
            let a = CGPoint(x: first.position.x - rackScroll, y: first.position.y)
            let b = CGPoint(x: last.position.x - rackScroll, y: last.position.y)
            return out ? (a, b) : (b, a)
        }
        guard let flow, let last = flow.sets.first?.pieces.last else { return nil }
        let onRug = CGPoint(x: layout.rug.minX + last.x, y: layout.rug.maxY + scroll - last.y)
        if out {
            guard let tile = rackShown.first, let node = pieces[tile] else { return nil }
            return (CGPoint(x: node.position.x - rackScroll, y: node.position.y), onRug)
        }
        return (onRug, CGPoint(x: layout.rack.midX, y: layout.rack.midY))
    }
}

extension TableScene: Autoplaying {
    /// The hand's first card into the middle of the laid zone (a hit, or back to the hand), then
    /// the last card dragged along the hand. On Cards, the first card up to the action row.
    func autoplayPath(out: Bool) -> (CGPoint, CGPoint)? {
        guard let layout, !hand.cards.isEmpty else { return nil }
        let index = out ? 0 : hand.cards.count - 1
        guard let frame = hand.frame(at: index) else { return nil }
        let start = convert(CGPoint(x: frame.midX, y: frame.midY), from: hand)
        // Just my cards (`-demo controller`): up to the action row, where it lands on nothing and
        // goes back.
        let away = layout.arrangement == .controller
            ? CGPoint(x: layout.actionRow.midX, y: layout.actionRow.midY)
            : CGPoint(x: layout.laidZone.midX, y: layout.laidZone.midY)
        if out { return (start, away) }
        return (start, convert(CGPoint(x: (hand.frame(at: 0) ?? frame).midX, y: frame.midY), from: hand))
    }
}
#endif
