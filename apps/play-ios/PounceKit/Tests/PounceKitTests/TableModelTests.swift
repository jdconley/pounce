import CoreGraphics
import Testing
@testable import PounceKit

/// Builds a playing room with `seatCount` human seats, `mine` of which are this device's.
func makeRoom(
    seatCount: Int = 4,
    mine: Set<Seat> = [0],
    turn: Seat = 0,
    step: TurnStep = .draw,
    round: Int = 1,
    discardTop: CardID? = 5,
    phase: [Int]? = nil,
    laid: [[Group]?]? = nil,
    pendingSkip: [Bool]? = nil,
    hands: [Seat: [CardID]] = [:],
    status: RoomStatus = .playing,
    gameStatus: GameStatus = .playing,
    forfeited: [Bool]? = nil
) -> RoomView {
    let seats = (0..<seatCount).map { i in
        SeatView(kind: .human, person: Person(id: "p\(i)", name: "P\(i)", cat: i % 8), yours: mine.contains(i), presence: .awake)
    }
    let game = GameView(
        round: round, dealer: 0, turn: turn, step: step, status: gameStatus, deckCount: 50,
        discardTop: discardTop, discardCount: discardTop == nil ? 0 : 1,
        phase: phase ?? Array(repeating: 0, count: seatCount),
        scores: Array(repeating: 0, count: seatCount),
        laid: laid ?? Array(repeating: nil, count: seatCount),
        handCounts: Array(repeating: 10, count: seatCount), hands: hands,
        pendingSkip: pendingSkip ?? Array(repeating: false, count: seatCount), winners: [], forfeited: forfeited)
    return RoomView(code: "BCDFG", status: status, youAreHost: true, seats: seats, game: game)
}

@Suite struct TableModelTests {
    @Test func drawSourcesExcludeCucumberTop() {
        #expect(TableModel(room: makeRoom(discardTop: 104)).drawSources(for: 0) == [.deck])
        #expect(TableModel(room: makeRoom(discardTop: 5)).drawSources(for: 0) == [.deck, .discard])
        #expect(TableModel(room: makeRoom(discardTop: nil)).drawSources(for: 0) == [.deck])
        #expect(TableModel(room: makeRoom(step: .play)).drawSources(for: 0).isEmpty)
        #expect(TableModel(room: makeRoom(turn: 1)).drawSources(for: 0).isEmpty)
    }

    @Test func traysFollowPhaseOrder() {
        let model = TableModel(room: makeRoom(phase: [1, 0, 0, 0]))
        #expect(model.trays(for: 0) == [Requirement(kind: .set, size: 3), Requirement(kind: .run, size: 4)])
        let laid: [[Group]?] = [[.set(cards: [0, 1, 2], value: 1)], nil, nil, nil]
        #expect(TableModel(room: makeRoom(phase: [1, 0, 0, 0], laid: laid)).trays(for: 0).isEmpty)
        #expect(TableModel(room: makeRoom(phase: [10, 0, 0, 0])).trays(for: 0).isEmpty)
    }

    @Test func hitTargetsOnlyAfterLaying() {
        let set7: Group = .set(cards: [6, 18, 30], value: 7)
        let run: Group = .run(cards: [0, 1, 2, 3], start: 1, end: 4)
        // Not laid yet: nothing glows.
        let before = TableModel(room: makeRoom(step: .play, laid: [nil, [set7], nil, nil]))
        #expect(before.hitTargets(card: 42, seat: 0).isEmpty)
        // Laid, seat 0 hits seat 1's set of 7s (id 42 = 7) and its own run end (id 4 = 5).
        let laid: [[Group]?] = [[run], [set7], nil, nil]
        let model = TableModel(room: makeRoom(step: .play, laid: laid))
        #expect(model.hitTargets(card: 42, seat: 0) == [HitTarget(seat: 1, group: 0)])
        #expect(model.hitTargets(card: 4, seat: 0) == [HitTarget(seat: 0, group: 0)])
        #expect(model.hitTargets(card: 104, seat: 0).isEmpty)
        // Not in the play step: none.
        #expect(TableModel(room: makeRoom(step: .draw, laid: laid)).hitTargets(card: 42, seat: 0).isEmpty)
    }

    /// Where a card dropped toward one end of a group lands, and what goes on the wire.
    @Test func hitPlanFollowsTheEndTheCardWasDroppedOn() throws {
        let run: Group = .run(cards: [3, 4, 5, 6], start: 4, end: 7)  // 4-5-6-7
        let set7: Group = .set(cards: [6 + 12, 30, 54], value: 7)
        let laid: [[Group]?] = [[set7], [run], nil, nil]
        let model = TableModel(room: makeRoom(step: .play, laid: laid))
        let target = HitTarget(seat: 1, group: 0)

        // A Yarn at the start: W-4-5-6-7 from 3, sent with side start.
        let low = try #require(model.hitPlan(card: 96, seat: 0, target: target, toward: .start))
        #expect(low.group == .run(cards: [96, 3, 4, 5, 6], start: 3, end: 7))
        #expect(low.index == 0)
        #expect(low.side == .start)
        #expect(low.stands == 3)
        #expect(low.action == .hit(card: 96, target: target, side: .start))

        // At the end it extends upward; that is the server's default, so no side is sent
        // (a server without `side` still takes it).
        let high = try #require(model.hitPlan(card: 96, seat: 0, target: target, toward: .end))
        #expect(high.group == .run(cards: [3, 4, 5, 6, 96], start: 4, end: 8))
        #expect(high.index == 4)
        #expect(high.stands == 8)
        #expect(high.action == .hit(card: 96, target: target))

        // A natural goes where its value fits, whichever end it was dropped on.
        let eight = try #require(model.hitPlan(card: 7, seat: 0, target: target, toward: .start))
        #expect(eight.index == 4)
        #expect(eight.side == .end)
        #expect(eight.stands == nil)
        #expect(eight.action == .hit(card: 7, target: target))

        // A Yarn on a run that tops out at 12 dropped at the end slides to the start.
        let top: Group = .run(cards: [8, 9, 10, 11], start: 9, end: 12)
        let model2 = TableModel(room: makeRoom(step: .play, laid: [[set7], [top], nil, nil]))
        let slid = try #require(model2.hitPlan(card: 96, seat: 0, target: target, toward: .end))
        #expect(slid.side == .start)
        #expect(slid.stands == 8)
        #expect(slid.action == .hit(card: 96, target: target))  // the server's default there

        // Sets: the Yarn stands for the set's number; no side.
        let onSet = try #require(model.hitPlan(card: 96, seat: 0, target: HitTarget(seat: 0, group: 0), toward: .start))
        #expect(onSet.side == nil)
        #expect(onSet.stands == 7)
        #expect(onSet.action == .hit(card: 96, target: HitTarget(seat: 0, group: 0)))

        // Illegal or out of turn: no plan.
        #expect(model.hitPlan(card: 104, seat: 0, target: target, toward: .start) == nil)
        #expect(model.hitPlan(card: 0, seat: 0, target: target, toward: .start) == nil)
        #expect(model.hitPlan(card: 96, seat: 0, target: HitTarget(seat: 2, group: 0), toward: .start) == nil)
        #expect(TableModel(room: makeRoom(step: .draw, laid: laid)).hitPlan(card: 96, seat: 0, target: target, toward: .start) == nil)
    }

    @Test func cucumberWithNoTargetsDiscardsPlain() {
        let model = TableModel(room: makeRoom(step: .play, pendingSkip: [false, true, true, true]))
        #expect(model.skipTargets(for: 0).isEmpty)
        #expect(model.discardAction(card: 104, target: 1) == .discard(card: 104, skipTarget: nil))
        #expect(model.discardAction(card: 104, target: nil) == .discard(card: 104, skipTarget: nil))
    }

    @Test func cucumberTargetsSkipPending() {
        let model = TableModel(room: makeRoom(step: .play, pendingSkip: [false, true, false, false]))
        #expect(model.skipTargets(for: 0) == [2, 3])
        #expect(model.discardAction(card: 104, target: 2) == .discard(card: 104, skipTarget: 2))
        #expect(model.discardAction(card: 104, target: 1) == .discard(card: 104, skipTarget: nil))
        #expect(model.discardAction(card: 7, target: 2) == .discard(card: 7, skipTarget: nil))
    }

    @Test func canStartNeedsNoOpenSeats() {
        func lobby(_ kinds: [SeatKind], mine: Bool = true) -> TableModel {
            let seats = kinds.enumerated().map { i, k in
                SeatView(kind: k, person: k == .human ? Person(id: "p\(i)", name: "P", cat: 0) : nil,
                         yours: mine && i == 0, presence: k == .human ? .awake : nil)
            }
            return TableModel(room: RoomView(code: "BCDFG", status: .lobby, youAreHost: true, seats: seats))
        }
        #expect(!lobby([.human, .open, .closed, .closed, .closed, .closed]).canStart)
        #expect(lobby([.human, .open, .closed, .closed, .closed, .closed]).blockingSeats == [1])
        #expect(lobby([.human, .open, .closed, .closed, .closed, .closed]).firstOpenSeat == 1)
        #expect(lobby([.human, .bot, .closed, .closed, .closed, .closed]).canStart)
        #expect(!lobby([.human, .closed, .closed, .closed, .closed, .closed]).canStart)
        #expect(!lobby([.human, .bot, .closed, .closed, .closed, .closed], mine: false).canStart)
        #expect(lobby([.human, .human, .bot, .closed, .closed, .closed]).canStart)
        #expect(TableModel(room: makeRoom()).blockingSeats.isEmpty)
        #expect(!TableModel(room: makeRoom()).canStart)
    }

    @Test func barSeatsAreEverySeatWithoutABottomSeat() {
        let model = TableModel(room: makeRoom(seatCount: 6, mine: []))
        #expect(model.barSeats(bottom: nil) == [0, 1, 2, 3, 4, 5])
        #expect(model.barSeats(bottom: 4) == [5, 0, 1, 2, 3])
        let layout = TableLayout(size: CGSize(width: 390, height: 844), safeTop: 59, safeBottom: 34, opponents: 6)
        #expect(layout.opponentSlots.count == 6)
    }

    @Test func opponentsInTurnOrder() {
        let model = TableModel(room: makeRoom(seatCount: 4))
        #expect(model.opponents(bottom: 2) == [3, 0, 1])
        #expect(model.opponents(bottom: 0) == [1, 2, 3])
    }

    @Test func mySeatsAndTurn() {
        let model = TableModel(room: makeRoom(mine: [0, 1], turn: 1))
        #expect(model.mySeats == [0, 1])
        #expect(model.isMultiSeat)
        #expect(model.currentSeat == 1)
        #expect(model.isMyTurn)
        #expect(!TableModel(room: makeRoom(mine: [0], turn: 1)).isMyTurn)
        #expect(!TableModel(room: makeRoom(mine: [0], gameStatus: .roundOver)).isMyTurn)
        #expect(!TableModel(room: makeRoom(mine: [0], status: .over)).isMyTurn)
        #expect(!TableModel(room: makeRoom(mine: [0], gameStatus: .roundOver)).canPlay(0))
    }
}
