/// The local, undoable draft of one turn in the tile game (tile game spec §5.1): a copy of the
/// rug and the rack that every drag changes, and that nothing but the turn button ever sends.
///
/// The app lays the rug out, the player doesn't: the draft is an ordered list of sets, and a
/// piece dropped on a set goes where it belongs in it (`arrange`). A set the player hasn't
/// changed keeps the server's order piece for piece, which the opening rule needs; a set that
/// comes back to exactly the pieces it started with gets its server order back too.
///
/// The rules it keeps, so a draft can never hold something no play could contain:
/// - Every piece that was on the rug at the start of the turn stays on the rug. Only pieces
///   placed this turn go back to the rack.
/// - Until the seat has opened, the sets already on the rug are locked: nothing leaves them,
///   nothing joins them and they don't split.
///
/// Whether the draft is a legal play is asked of `TilesRules.checkPlay`, the same checks the
/// server runs, so `turnButton` is `.play` exactly when the server would take `action`.
public struct TilesDraft: Equatable, Sendable, Codable {
    /// One set on the drafted rug. `id` is stable for the turn (through undo too), so the scene
    /// can follow a set as it changes.
    public struct DraftSet: Equatable, Sendable, Codable, Identifiable {
        public let id: Int
        public internal(set) var tiles: [TileID]
    }

    /// Which end of a row a Yarn with no gap to fill goes on.
    public enum Side: String, Sendable, Codable { case start, end }

    /// Where a move puts its pieces.
    public enum Destination: Equatable, Sendable {
        /// A new set, after the others (or before the set now at `at` in `sets`).
        case newSet(at: Int? = nil)
        /// Into the set with this id, wherever the pieces belong; `toward` settles a Yarn with
        /// no gap to fill.
        case set(Int, toward: Side? = nil)
        /// Back to the rack: only pieces placed this turn.
        case rack
    }

    /// Why a move changed nothing.
    public enum Refusal: Error, Equatable, Sendable {
        /// The seat hasn't opened and the move touches a set that was already on the rug.
        case notOpened
        /// A piece that was on the rug at the start of the turn can't go to a rack.
        case tablePiece
        /// A piece or a set that isn't in the draft, or a split that isn't between two pieces.
        case unknown
        /// The move would leave everything where it is.
        case nothing
    }

    /// How a set of the draft stands (tile game spec §5.5).
    public enum SetState: Equatable, Sendable {
        /// On the rug at the start of the turn, and still the same pieces in the same order.
        case unchanged
        /// A row or a match that this turn made or changed.
        case changed
        /// Not a set yet, and the one thing to say about why.
        case broken(Problem)
    }

    /// Why a set isn't one yet. One glyph each: a "3", two different toys, the same toy twice,
    /// a broken chain.
    public enum Problem: Equatable, Sendable {
        /// Fewer than three pieces.
        case tooShort
        /// Different toys with different numbers: neither a row nor a match.
        case mixedSuits
        /// A match with one toy twice (or a fifth piece, which has to repeat one).
        case suitTwice
        /// A row with a number missing, twice, or running off the end of 1 to 13.
        case gap
    }

    /// What the turn button is (tile game spec §5.5).
    public enum TurnButton: Equatable, Sendable {
        /// Nothing moved and the toy box has pieces.
        case draw
        /// Nothing moved and the toy box is empty.
        case pass
        /// Pieces placed and every check passes.
        case play
        /// Something moved and the draft isn't a legal play.
        case blocked(Block)
    }

    /// Why a changed draft can't be played.
    public enum Block: Equatable, Sendable {
        /// The first set, in the order shown, that isn't a row or a match.
        case brokenSet(Int)
        /// The rug was rearranged but nothing came from the rack.
        case nothingPlaced
        /// Before opening: the new sets are worth this much, short of 30.
        case openingTooLow(Int)
        /// Anything else the rules refuse. The draft's own rules keep these from happening.
        case refused(TilesPlayError)
    }

    /// The rug at the start of the turn, as the snapshot gave it.
    public let base: [[TileID]]
    /// The rack at the start of the turn, in the snapshot's order.
    public let baseRack: [TileID]
    /// The seat had opened before this turn.
    public let opened: Bool
    /// The toy box had pieces at the start of the turn (Draw, not Pass).
    public let poolHasPieces: Bool
    /// The drafted rug, in the order the sets were made.
    public private(set) var sets: [DraftSet]
    /// Tidy (tile game spec §5.7): rows by toy then number, then matches by number, on screen
    /// and in the submission. A view setting: not part of undo.
    public var tidy = false

    private var history: [[DraftSet]] = []
    private var nextID: Int

    public init(table: [[TileID]], rack: [TileID], opened: Bool, poolHasPieces: Bool = true) {
        base = table
        baseRack = rack
        self.opened = opened
        self.poolHasPieces = poolHasPieces
        sets = table.enumerated().map { DraftSet(id: $0.offset, tiles: $0.element) }
        nextID = table.count
    }

    // MARK: reading the draft

    /// The pieces still on the rack, in the snapshot's order (`RackOrder` holds the order shown).
    public var rack: [TileID] {
        let down = onRug
        return baseRack.filter { !down.contains($0) }
    }

    /// Rack pieces placed this turn: the ones that carry the paw dot and may go back.
    public var placed: [TileID] {
        let was = baseTiles
        return sets.flatMap(\.tiles).filter { !was.contains($0) }
    }

    public func isPlaced(_ tile: TileID) -> Bool { !baseTiles.contains(tile) && onRug.contains(tile) }

    /// Nothing has moved: the rug is the snapshot's, set for set.
    public var isUntouched: Bool { sets.map(\.tiles) == base }

    public var canUndo: Bool { !history.isEmpty }

    public func set(_ id: Int) -> DraftSet? { sets.first { $0.id == id } }

    /// The set holding `tile`, if it is on the rug.
    public func setID(holding tile: TileID) -> Int? { sets.first { $0.tiles.contains(tile) }?.id }

    /// Before opening, a set that was already on the rug: it takes no pieces, gives none up and
    /// doesn't open in the loupe.
    public func isLocked(_ id: Int) -> Bool {
        guard !opened, let set = set(id) else { return false }
        return baseSets.contains(set.tiles)
    }

    /// The sets in the order shown and submitted: as made, or tidied.
    public var shownSets: [DraftSet] {
        guard tidy else { return sets }
        return sets.enumerated().sorted { a, b in
            let ka = Self.tidyKey(a.element.tiles), kb = Self.tidyKey(b.element.tiles)
            return ka == kb ? a.offset < b.offset : ka.lexicographicallyPrecedes(kb)
        }.map(\.element)
    }

    /// Rows by toy then first number, then matches by number, then whatever isn't a set yet.
    static func tidyKey(_ tiles: [TileID]) -> [Int] {
        switch TilesRules.readSet(tiles) {
        case .run(let suit, let start, _, _): [0, suit.index, start, tiles.count]
        case .group(let value, _): [1, value, tiles.count, 0]
        case nil: [2, 0, 0, 0]
        }
    }

    public func state(of id: Int) -> SetState {
        guard let set = set(id) else { return .broken(.tooShort) }
        return state(of: set.tiles)
    }

    func state(of tiles: [TileID]) -> SetState {
        if baseSets.contains(tiles) { return .unchanged }
        if TilesRules.readSet(tiles) != nil { return .changed }
        return .broken(Self.problem(tiles))
    }

    /// The one thing to say about tiles that aren't a set.
    static func problem(_ tiles: [TileID]) -> Problem {
        if tiles.count < TilesRules.minSet { return .tooShort }
        let naturals = tiles.compactMap { id -> (value: Int, suit: TileSuit)? in
            guard case .number(let value, let suit)? = Tile.decode(id) else { return nil }
            return (value, suit)
        }
        guard let first = naturals.first else { return .tooShort }
        // One number throughout: a match, so a toy is there twice (a fifth piece has to repeat one).
        if naturals.allSatisfy({ $0.value == first.value }) { return .suitTwice }
        // One toy throughout: a row with a number missing, doubled or off the end.
        if naturals.allSatisfy({ $0.suit == first.suit }) { return .gap }
        return .mixedSuits
    }

    /// What the new sets are worth so far: only valid sets that weren't on the rug count, so the
    /// opening meter never promises more than the server will accept.
    public var newPoints: Int {
        sets.reduce(0) { sum, set in
            guard !baseSets.contains(set.tiles), let reading = TilesRules.readSet(set.tiles) else { return sum }
            return sum + reading.points
        }
    }

    /// The opening meter (tile game spec §5.5): the running total toward 30. Nil once opened.
    public var openingMeter: (points: Int, goal: Int)? {
        opened ? nil : (newPoints, TilesRules.openingPoints)
    }

    /// The rug as it would be submitted.
    public var submission: [[TileID]] { shownSets.map(\.tiles) }

    /// The server's own check of `submission`.
    public var check: Result<TilesPlay, TilesPlayError> {
        TilesRules.checkPlay(before: base, rack: baseRack, opened: opened, submitted: submission)
    }

    public var turnButton: TurnButton {
        if isUntouched { return poolHasPieces ? .draw : .pass }
        // A set that isn't one comes first, whatever else is wrong: it is the thing to go and fix.
        if let broken = shownSets.first(where: { TilesRules.readSet($0.tiles) == nil }) {
            return .blocked(.brokenSet(broken.id))
        }
        switch check {
        case .success: return .play
        case .failure(.nothingPlayed): return .blocked(.nothingPlaced)
        case .failure(.openingTooLow): return .blocked(.openingTooLow(newPoints))
        case .failure(let error): return .blocked(.refused(error))
        }
    }

    /// The turn to send: the play when the draft is one, a draw or a pass when nothing moved,
    /// nil while the draft is blocked.
    public var action: TilesAction? {
        switch turnButton {
        case .draw: .draw
        case .pass: .pass
        case .play: .play(table: submission)
        case .blocked: nil
        }
    }

    /// The sets a server refusal points at (tile game spec §5.5): the ones that aren't sets for
    /// `bad_set`, the changed ones for `table_touched`. Empty for anything else.
    public func sets(refusedBy error: TilesPlayError) -> [Int] {
        switch error {
        case .badSet: shownSets.filter { TilesRules.readSet($0.tiles) == nil }.map(\.id)
        case .tableTouched: shownSets.filter { !baseSets.contains($0.tiles) }.map(\.id)
        default: []
        }
    }

    // MARK: changing the draft

    /// Moves `tiles` (from the rack, the rug or both) to `destination` as one undo step.
    /// Pieces already there stay; a set left empty goes away.
    @discardableResult
    public mutating func move(_ tiles: [TileID], to destination: Destination) -> Result<Void, Refusal> {
        let moving = tiles.reduce(into: [TileID]()) { if !$0.contains($1) { $0.append($1) } }
        let down = onRug
        let mine = Set(baseRack)
        guard !moving.isEmpty, moving.allSatisfy({ down.contains($0) || mine.contains($0) }) else { return .failure(.unknown) }
        let was = baseTiles
        for tile in moving where down.contains(tile) {
            if let from = setID(holding: tile), isLocked(from) { return .failure(.notOpened) }
        }

        var next = sets
        var target: Int?
        var toward: Side?
        switch destination {
        case .rack:
            if moving.contains(where: was.contains) { return .failure(.tablePiece) }
        case .set(let id, let side):
            guard set(id) != nil else { return .failure(.unknown) }
            if isLocked(id) { return .failure(.notOpened) }
            target = id
            toward = side
        case .newSet:
            break
        }

        // Out of where they are.
        let lifted = Set(moving)
        let targetIndex = target.flatMap { id in next.firstIndex { $0.id == id } }
        for i in next.indices where next[i].id != target {
            next[i].tiles.removeAll(where: lifted.contains)
        }

        // Into where they go.
        var makeID = nextID
        switch destination {
        case .rack:
            break
        case .set:
            guard let i = targetIndex else { return .failure(.unknown) }
            let staying = next[i].tiles.filter { !lifted.contains($0) }
            next[i].tiles = Self.arrange(staying, adding: moving, toward: toward)
        case .newSet(let at):
            // Before the set now at `at`, counted before any set this move empties goes away.
            let made = DraftSet(id: makeID, tiles: Self.arrange([], adding: moving, toward: nil))
            makeID += 1
            if let at, sets.indices.contains(at), let before = next.firstIndex(where: { $0.id == sets[at].id }) {
                next.insert(made, at: before)
            } else {
                next.append(made)
            }
        }
        next.removeAll { $0.tiles.isEmpty }
        for i in next.indices { next[i].tiles = restored(next[i].tiles) }
        // A lone set moved whole into a new one is the same set: nothing happened.
        guard next.map(\.tiles) != sets.map(\.tiles) else { return .failure(.nothing) }
        commit(next, nextID: makeID)
        return .success(())
    }

    /// Breaks a set in two before the piece at `index` (the loupe's tap on a gap).
    @discardableResult
    public mutating func split(_ id: Int, before index: Int) -> Result<Void, Refusal> {
        guard let i = sets.firstIndex(where: { $0.id == id }), index > 0, index < sets[i].tiles.count else {
            return .failure(.unknown)
        }
        if isLocked(id) { return .failure(.notOpened) }
        var next = sets
        let tiles = next[i].tiles
        next[i].tiles = restored(Array(tiles[..<index]))
        next.insert(DraftSet(id: nextID, tiles: restored(Array(tiles[index...]))), at: i + 1)
        commit(next, nextID: nextID + 1)
        return .success(())
    }

    /// Moves every piece of one set onto another (the loupe's handle).
    @discardableResult
    public mutating func join(_ id: Int, onto other: Int, toward: Side? = nil) -> Result<Void, Refusal> {
        guard id != other, let from = set(id) else { return .failure(.unknown) }
        return move(from.tiles, to: .set(other, toward: toward))
    }

    /// Takes pieces placed this turn back to the rack.
    @discardableResult
    public mutating func takeBack(_ tiles: [TileID]) -> Result<Void, Refusal> {
        move(tiles, to: .rack)
    }

    /// Steps back one move, as far as the start of the turn. A multi-piece move is one step.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let last = history.popLast() else { return false }
        sets = last
        return true
    }

    /// Back to the snapshot: the rug and the rack as the turn began.
    public mutating func reset() {
        sets = base.enumerated().map { DraftSet(id: $0.offset, tiles: $0.element) }
        history = []
        nextID = base.count
    }

    /// True when the draft was made for this rug, rack and opening: a saved draft for a turn that
    /// has moved on is dropped (tile game spec §5.6).
    public func matches(table: [[TileID]], rack: [TileID], opened: Bool) -> Bool {
        base == table && Set(baseRack) == Set(rack) && baseRack.count == rack.count && self.opened == opened
    }

    private mutating func commit(_ next: [DraftSet], nextID: Int) {
        history.append(sets)
        sets = next
        self.nextID = nextID
    }

    // MARK: where a piece belongs

    /// The order a set takes when `adding` joins `existing`.
    ///
    /// - A match (two or more number pieces of one number): order means nothing, so the new
    ///   pieces go on the end.
    /// - A row (number pieces of one toy): sorted by number. Yarn fills the gaps when there is
    ///   enough of it to fill them all. Yarn left over stays on the end it was on; a new one goes
    ///   `toward` (the high end by default), or the other end when that one is off the 1 to 13.
    /// - Anything else can't be a set whatever the order: the new pieces go on the end, and the
    ///   set shows as broken, so a player can build toward a rearrangement in any order.
    static func arrange(_ existing: [TileID], adding: [TileID], toward: Side?) -> [TileID] {
        let all = existing + adding
        let naturals = all.filter { !Tile.isYarn($0) }
        guard let first = naturals.first, let suit = Tile.suit(first), let value = Tile.value(first) else { return all }
        let plain = toward == .start ? adding + existing : all
        if naturals.count > 1, naturals.allSatisfy({ Tile.value($0) == value }) { return plain }
        guard naturals.allSatisfy({ Tile.suit($0) == suit }) else { return plain }

        let sorted = naturals.enumerated().sorted {
            let a = Tile.value($0.element) ?? 0, b = Tile.value($1.element) ?? 0
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
        let values = sorted.compactMap(Tile.value)
        let low = values.first ?? value, high = values.last ?? value

        // Yarn already at an end of the row stays there; the rest is free to fill gaps.
        let firstNatural = existing.firstIndex { !Tile.isYarn($0) }
        let lastNatural = existing.lastIndex { !Tile.isYarn($0) }
        var leading: [TileID] = [], trailing: [TileID] = [], free: [TileID] = []
        for (i, id) in existing.enumerated() where Tile.isYarn(id) {
            if let firstNatural, i < firstNatural {
                leading.append(id)
            } else if let lastNatural, i > lastNatural {
                trailing.append(id)
            } else {
                free.append(id)
            }
        }
        free += adding.filter(Tile.isYarn)

        let gaps = zip(values, values.dropFirst()).map { $1 - $0 - 1 }
        let need = gaps.reduce(0) { $0 + max($1, 0) }
        let fill = need > 0 && gaps.allSatisfy({ $0 >= 0 }) && need <= free.count + leading.count + trailing.count
        var body: [TileID] = []
        for (i, id) in sorted.enumerated() {
            body.append(id)
            guard fill, i < gaps.count else { continue }
            for _ in 0..<gaps[i] {
                // End Yarn moves into a gap only when the free ones run out.
                if !free.isEmpty { body.append(free.removeFirst()) }
                else if !trailing.isEmpty { body.append(trailing.removeLast()) }
                else if !leading.isEmpty { body.append(leading.removeLast()) }
            }
        }
        for id in free {
            if toward == .start { leading.append(id) } else { trailing.append(id) }
        }
        // Nothing stands below 1 or above 13: Yarn that would goes to the other end if it fits.
        while low - leading.count < 1, !leading.isEmpty, high + trailing.count < Tile.maxValue {
            trailing.append(leading.removeLast())
        }
        while high + trailing.count > Tile.maxValue, !trailing.isEmpty, low - leading.count > 1 {
            leading.append(trailing.removeLast())
        }
        return leading + body + trailing
    }

    /// `tiles`, or the server's order for them when they are exactly a set that was on the rug.
    private func restored(_ tiles: [TileID]) -> [TileID] {
        guard !tiles.isEmpty else { return tiles }
        let key = Set(tiles)
        for old in base where old.count == tiles.count && Set(old) == key { return old }
        return tiles
    }

    private var onRug: Set<TileID> { Set(sets.flatMap(\.tiles)) }
    private var baseTiles: Set<TileID> { Set(base.joined()) }
    private var baseSets: Set<[TileID]> { Set(base) }
}
