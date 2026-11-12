#if DEBUG
import UIKit

/// DEBUG launch argument `-show-touches`: a ring under every finger, for the How to play videos
/// (`apps/play-ios/HowTo/`), so a recording shows where each tap and drag happens. The ring pops
/// in on touch down, follows a drag with a fading trail, and swells away on lift. It is drawn in a
/// window of its own above the app that takes no touches; a recognizer on each app window
/// watches touches without claiming or delaying any.
///
/// `-timecode` (with `-show-touches`) also draws the wall clock along the top edge of every frame:
/// 24 squares, 4 points each, the unix time in hundredths of a second (mod 2^24) in binary, most
/// significant first, white for 1, between a white start square and a black end square. A screen
/// recording's own timestamps drift when the Mac is busy; `HowTo/compose.py` reads this strip
/// instead, then crops it off.
@MainActor
enum TouchMarks {
    private static var overlay: UIWindow?
    private static var observer: NSObjectProtocol?

    static func installIfAsked(arguments: [String] = CommandLine.arguments) {
        guard arguments.contains("-show-touches"), observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main
        ) { note in
            guard let window = note.object as? UIWindow else { return }
            MainActor.assumeIsolated { attach(to: window) }
        }
    }

    private static func attach(to window: UIWindow) {
        guard window !== overlay, let scene = window.windowScene else { return }
        if window.gestureRecognizers?.contains(where: { $0 is TouchWatcher }) != true {
            window.addGestureRecognizer(TouchWatcher())
        }
        if overlay == nil {
            let marks = UIWindow(windowScene: scene)
            marks.windowLevel = .alert + 10
            marks.isUserInteractionEnabled = false
            marks.backgroundColor = .clear
            let root = UIViewController()
            root.view.backgroundColor = .clear
            root.view.isUserInteractionEnabled = false
            marks.rootViewController = root
            overlay = marks  // before it shows: showing it posts the notification that lands here
            marks.isHidden = false
            if CommandLine.arguments.contains("-timecode") { TimeCode.start(in: marks) }
        }
    }

    // MARK: drawing

    private static var rings: [ObjectIdentifier: CAShapeLayer] = [:]
    private static var trailed: [ObjectIdentifier: CGPoint] = [:]
    static let radius: CGFloat = 26
    private static let yellow = UIColor(red: 1, green: 0.824, blue: 0.122, alpha: 1)
    private static let ink = UIColor(red: 0.106, green: 0.043, blue: 0.227, alpha: 1)

    fileprivate static func began(_ touch: UITouch) {
        guard let overlay else { return }
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)).cgPath
        ring.fillColor = yellow.withAlphaComponent(0.5).cgColor
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 6
        ring.shadowColor = ink.cgColor
        ring.shadowOpacity = 0.9
        ring.shadowRadius = 0
        ring.shadowOffset = CGSize(width: 0, height: 2)
        ring.shadowPath = UIBezierPath(ovalIn: CGRect(x: -radius - 3, y: -radius - 3, width: radius * 2 + 6, height: radius * 2 + 6)).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.position = touch.location(in: overlay)
        overlay.layer.addSublayer(ring)
        CATransaction.commit()
        let pop = CABasicAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.4
        pop.toValue = 1
        pop.duration = 0.14
        ring.add(pop, forKey: "pop")
        rings[ObjectIdentifier(touch)] = ring
        trailed[ObjectIdentifier(touch)] = ring.position
    }

    fileprivate static func moved(_ touch: UITouch) {
        guard let overlay, let ring = rings[ObjectIdentifier(touch)] else { return }
        let point = touch.location(in: overlay)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.position = point
        CATransaction.commit()
        // A dot every few points along a drag, each fading out.
        guard let last = trailed[ObjectIdentifier(touch)], hypot(point.x - last.x, point.y - last.y) > 14 else { return }
        trailed[ObjectIdentifier(touch)] = point
        let dot = CAShapeLayer()
        dot.path = UIBezierPath(ovalIn: CGRect(x: -7, y: -7, width: 14, height: 14)).cgPath
        dot.fillColor = UIColor.white.withAlphaComponent(0.85).cgColor
        dot.strokeColor = ink.cgColor
        dot.lineWidth = 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.position = point
        dot.opacity = 0
        overlay.layer.insertSublayer(dot, below: ring)
        CATransaction.commit()
        fade(dot, from: 1, duration: 0.5)
    }

    fileprivate static func ended(_ touch: UITouch) {
        guard let ring = rings.removeValue(forKey: ObjectIdentifier(touch)) else { return }
        trailed[ObjectIdentifier(touch)] = nil
        let swell = CABasicAnimation(keyPath: "transform.scale")
        swell.fromValue = 1
        swell.toValue = 1.6
        swell.duration = 0.35
        swell.fillMode = .forwards
        swell.isRemovedOnCompletion = false
        ring.add(swell, forKey: "swell")
        ring.opacity = 0
        fade(ring, from: 1, duration: 0.35)
    }

    private static func fade(_ layer: CALayer, from: Float, duration: TimeInterval) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = 0
        fade.duration = duration
        layer.add(fade, forKey: "fade")
        CATransaction.commit()
    }
}

/// The `-timecode` strip: redrawn on every frame.
@MainActor
private enum TimeCode {
    static let bits = 24
    static let side: CGFloat = 4
    static let left: CGFloat = 60
    private static var squares: [CALayer] = []
    private static var link: CADisplayLink?
    private static let target = Ticker()

    static func start(in window: UIWindow) {
        for i in 0..<(bits + 2) {
            let square = CALayer()
            square.frame = CGRect(x: left + CGFloat(i) * side, y: 0, width: side, height: side)
            square.backgroundColor = (i == 0 ? UIColor.white : UIColor.black).cgColor
            window.layer.addSublayer(square)
            squares.append(square)
        }
        link = CADisplayLink(target: target, selector: #selector(Ticker.tick))
        link?.add(to: .main, forMode: .common)
    }

    static func tick() {
        let value = UInt64(Date().timeIntervalSince1970 * 100) & ((1 << UInt64(bits)) - 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in 0..<bits {
            let on = (value >> UInt64(bits - 1 - i)) & 1 == 1
            squares[i + 1].backgroundColor = (on ? UIColor.white : UIColor.black).cgColor
        }
        CATransaction.commit()
    }

    private final class Ticker: NSObject {
        @objc func tick() { MainActor.assumeIsolated { TimeCode.tick() } }
    }
}

/// Sees every touch in its window and never recognizes, so nothing is cancelled or delayed.
private final class TouchWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        touches.forEach(TouchMarks.began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        touches.forEach(TouchMarks.moved)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        touches.forEach(TouchMarks.ended)
        if numberOfTouches <= touches.count { state = .failed }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        touches.forEach(TouchMarks.ended)
        if numberOfTouches <= touches.count { state = .failed }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif
