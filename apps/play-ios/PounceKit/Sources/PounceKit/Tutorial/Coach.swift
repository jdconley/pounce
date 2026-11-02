/// What the coach knows about the hand shown face up right now: whose it is and what they can do.
/// The table makes one only while a hand of this phone is face up.
public struct CoachContext: Equatable, Sendable {
    /// The person whose hand it is (`Person.id`).
    public var person: String
    /// The store's turn epoch: a new turn, round or status is a new epoch.
    public var epoch: Int
    /// It is this person's turn in a game being played.
    public var myTurn: Bool
    public var step: TurnStep
    /// The phase still to lay down; empty once laid.
    public var phase: [Requirement]
    /// The trays hold a valid phase.
    public var layDownReady: Bool
    /// A card in the hand fits a laid group.
    public var canHit: Bool
    public var hasYarn: Bool
    public var hasCucumber: Bool
    public var handCount: Int

    public init(
        person: String, epoch: Int, myTurn: Bool, step: TurnStep, phase: [Requirement], layDownReady: Bool,
        canHit: Bool, hasYarn: Bool, hasCucumber: Bool, handCount: Int
    ) {
        self.person = person
        self.epoch = epoch
        self.myTurn = myTurn
        self.step = step
        self.phase = phase
        self.layDownReady = layDownReady
        self.canHit = canHit
        self.hasYarn = hasYarn
        self.hasCucumber = hasCucumber
        self.handCount = handCount
    }

    public var laid: Bool { phase.isEmpty }

    var playing: Bool { myTurn && step == .play }
}

/// One coaching tip for a first game. Declared in priority order: when several apply, the
/// first one not seen yet shows.
public enum CoachTip: String, CaseIterable, Codable, Sendable {
    case goal, draw, layDown, phase, run, coat, discard, hit, goOut, cucumber, yarn

    /// The tip fits the table as it is now.
    public func applies(_ c: CoachContext) -> Bool {
        switch self {
        case .goal: true
        case .draw: c.myTurn && c.step == .draw
        case .layDown: c.playing && c.layDownReady
        case .phase: c.playing && !c.laid
        case .run: c.playing && c.phase.contains { $0.kind == .run }
        case .coat: c.playing && c.phase.contains { $0.kind == .coat }
        case .discard: c.playing
        case .hit: c.playing && c.laid && c.canHit
        case .goOut: c.playing && c.laid && c.handCount <= 2
        case .cucumber: c.playing && c.hasCucumber
        case .yarn: c.playing && c.hasYarn
        }
    }

    /// What showing this tip explains: the phase tip also explains the kinds of group it names.
    public func covers(_ c: CoachContext) -> Set<CoachTip> {
        guard self == .phase else { return [self] }
        var tips: Set<CoachTip> = [.phase]
        if c.phase.contains(where: { $0.kind == .run }) { tips.insert(.run) }
        if c.phase.contains(where: { $0.kind == .coat }) { tips.insert(.coat) }
        return tips
    }

    /// The first tip that applies and hasn't been seen.
    public static func next(for c: CoachContext, seen: Set<CoachTip>) -> CoachTip? {
        allCases.first { !seen.contains($0) && $0.applies(c) }
    }

    /// Tips a person showed they don't need by doing the thing, going from `old` to `new`
    /// (both theirs).
    public static func learned(from old: CoachContext, to new: CoachContext) -> Set<CoachTip> {
        guard old.person == new.person else { return [] }
        var tips: Set<CoachTip> = []
        if old.myTurn, old.step == .draw, new.myTurn, new.step == .play, new.epoch == old.epoch {
            tips.insert(.draw)
        }
        if old.playing, !new.myTurn || new.epoch != old.epoch {
            tips.insert(.discard)
        }
        if !old.laid, new.laid {
            tips.formUnion([.layDown, .phase])
            tips.formUnion(CoachTip.phase.covers(old).subtracting([.phase]))
        } else if old.playing, new.playing, old.laid, new.laid, new.epoch == old.epoch, new.handCount < old.handCount {
            tips.insert(.hit)
        }
        return tips
    }
}

/// Decides the coaching tip on one table, one at a time, for whoever's hand is face up. Each
/// tip shows once per person (the caller keeps what each person has seen), goes away when
/// dismissed or when it stops applying, and a person can turn tips off for the rest of this
/// game. At most `perStep` new tips show in one step of a turn, so a first turn isn't a lecture.
public struct Coach: Equatable, Sendable {
    public static let perStep = 2

    /// The tip showing now, and whose it is.
    public private(set) var tip: CoachTip?
    public private(set) var person: String?
    /// People who turned tips off for this game.
    public private(set) var off: Set<String> = []
    /// The last context seen for each person, to notice what they did between looks.
    private var last: [String: CoachContext] = [:]
    private var step: StepKey?
    private var shownThisStep = 0

    private struct StepKey: Equatable, Sendable {
        let person: String
        let epoch: Int
        let step: TurnStep
    }

    public init() {}

    /// Feeds the table as it is now (nil: no hand face up) and returns the tips to mark seen for
    /// `context.person`: ones they learned by doing and the one put up now. `seen` is what that
    /// person has seen so far. New tips only go up when `allowNew` (the caller waits for the
    /// table to settle); a tip that stopped applying always comes down at once.
    @discardableResult
    public mutating func update(_ context: CoachContext?, seen: Set<CoachTip>, allowNew: Bool = true) -> Set<CoachTip> {
        guard let context else {
            tip = nil
            person = nil
            return []
        }
        var marked: Set<CoachTip> = []
        if let before = last[context.person] { marked = CoachTip.learned(from: before, to: context) }
        last[context.person] = context
        if let tip, person != context.person || !tip.applies(context) {
            self.tip = nil
            person = nil
        }
        let key = StepKey(person: context.person, epoch: context.epoch, step: context.step)
        if key != step {
            step = key
            shownThisStep = 0
        }
        guard tip == nil, allowNew, !off.contains(context.person), shownThisStep < Self.perStep,
              let next = CoachTip.next(for: context, seen: seen.union(marked)) else { return marked }
        tip = next
        person = context.person
        shownThisStep += 1
        return marked.union(next.covers(context))
    }

    /// The person tapped "Got it".
    public mutating func dismiss() {
        tip = nil
        person = nil
    }

    /// No more tips for the person whose tip is up, for the rest of this game.
    public mutating func turnOff() {
        if let person { off.insert(person) }
        dismiss()
    }

    /// Tips are back on for everyone (the rules sheet's replay).
    public mutating func turnOn() {
        off.removeAll()
        shownThisStep = 0
    }
}
