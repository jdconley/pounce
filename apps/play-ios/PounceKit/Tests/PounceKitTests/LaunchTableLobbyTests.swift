import Foundation
import CoreGraphics
import Testing
@testable import PounceKit

/// A lobby with the given seat kinds; `mine` are this device's (human) seats.
private func lobby(_ kinds: [SeatKind], mine: Set<Seat> = [0]) -> TableModel {
    let seats = kinds.enumerated().map { i, kind in
        SeatView(
            kind: kind, person: kind == .human ? Person(id: "p\(i)", name: "P\(i)", cat: i) : nil,
            yours: kind == .human && mine.contains(i), presence: kind == .human ? .awake : nil)
    }
    return TableModel(room: RoomView(code: "BCDFG", status: .lobby, youAreHost: true, seats: seats, game: nil))
}

@Suite struct MoveNoteTests {
    @Test func everyServerRefusalOfAMoveHasItsOwnWords() {
        let codes: [ErrorCode: MoveNote] = [
            .notYourTurn: .notYourTurn, .badStep: .drawFirst, .badGroups: .notALevel, .alreadyLaid: .alreadyLaid,
            .notLaid: .layDownFirst, .badTarget: .noFit, .emptyDiscard: .emptyDiscard,
            .cucumberFromDiscard: .cucumberOnDiscard, .roundNotOver: .roundOver, .forfeited: .forfeited,
            .notSent: .notSent,
        ]
        for (code, note) in codes { #expect(MoveNote.server(code) == note, "\(code.rawValue)") }
        // A code this build has never heard of still gets words.
        #expect(MoveNote.server(ErrorCode(rawValue: "from_the_future")) == .unknown)
    }

    @Test func whyAPileCantBeDrawnFrom() {
        #expect(TableModel(room: makeRoom()).whyNoDraw(.discard, seat: 0) == nil)
        #expect(TableModel(room: makeRoom(discardTop: 104)).whyNoDraw(.discard, seat: 0) == .cucumberOnDiscard)
        #expect(TableModel(room: makeRoom(discardTop: 104)).whyNoDraw(.deck, seat: 0) == nil)
        #expect(TableModel(room: makeRoom(discardTop: nil)).whyNoDraw(.discard, seat: 0) == .emptyDiscard)
        #expect(TableModel(room: makeRoom(step: .play)).whyNoDraw(.deck, seat: 0) == .alreadyDrew)
        #expect(TableModel(room: makeRoom(turn: 1)).whyNoDraw(.deck, seat: 0) == .notYourTurn)
        #expect(TableModel(room: makeRoom(gameStatus: .roundOver)).whyNoDraw(.deck, seat: 0) == .roundOver)
        let out = makeRoom(forfeited: [true, false, false, false])
        #expect(TableModel(room: out).whyNoDraw(.deck, seat: 0) == .forfeited)
    }

    @Test func whyACardCantBePlayed() {
        #expect(TableModel(room: makeRoom()).whyNoPlay(0) == .drawFirst)
        #expect(TableModel(room: makeRoom(step: .play)).whyNoPlay(0) == nil)
        #expect(TableModel(room: makeRoom(turn: 2, step: .play)).whyNoPlay(0) == .notYourTurn)
    }

    @Test func whyACardCantJoinAGroup() {
        let set7: Group = .set(cards: [6, 18, 30], value: 7)
        let run: Group = .run(cards: [0, 1, 2, 3], start: 1, end: 4)
        let target = HitTarget(seat: 1, group: 0)
        let notLaid = TableModel(room: makeRoom(step: .play, laid: [nil, [set7], nil, nil]))
        #expect(notLaid.whyNoHit(card: 42, seat: 0, target: target) == .layDownFirst)
        let laid = TableModel(room: makeRoom(step: .play, laid: [[run], [set7], nil, nil]))
        #expect(laid.whyNoHit(card: 42, seat: 0, target: target) == nil)
        #expect(laid.whyNoHit(card: 43, seat: 0, target: target) == .noFit)
        let early = TableModel(room: makeRoom(step: .draw, laid: [[run], [set7], nil, nil]))
        #expect(early.whyNoHit(card: 42, seat: 0, target: target) == .drawFirst)
    }

    @Test func whyACardCantGoOnACatOrThePile() {
        let model = TableModel(room: makeRoom(step: .play, pendingSkip: [false, true, false, false]))
        #expect(model.whyNoAim(card: 5, seat: 0, at: 2) == .cucumberOnly)
        #expect(model.whyNoAim(card: 104, seat: 0, at: 2) == nil)
        #expect(model.whyNoAim(card: 104, seat: 0, at: 1) == .catSkipped)
        #expect(model.whyNoDiscard(card: 104, seat: 0) == .pickACat)
        #expect(model.whyNoDiscard(card: 5, seat: 0) == nil)
        // Everyone else already skipped: the Cucumber goes out plain.
        let none = TableModel(room: makeRoom(seatCount: 2, step: .play, pendingSkip: [false, true]))
        #expect(none.whyNoDiscard(card: 104, seat: 0) == nil)
    }
}

@Suite struct DiscardHoldTests {
    private let hold = DiscardHold(card: 5, target: nil, seat: 0, epoch: 3, serial: 1)

    @Test func standsWhileItsTurnDoes() {
        let model = TableModel(room: makeRoom(step: .play, hands: [0: [5, 6, 7]]))
        #expect(hold.stands(model, epoch: 3))
    }

    @Test func aNewTurnOrEpochDropsIt() {
        #expect(!hold.stands(TableModel(room: makeRoom(step: .play, hands: [0: [5, 6]])), epoch: 4))
        #expect(!hold.stands(TableModel(room: makeRoom(turn: 1, step: .draw, hands: [0: [5, 6]])), epoch: 3))
        #expect(!hold.stands(TableModel(room: makeRoom(step: .play, hands: [0: [5]], gameStatus: .roundOver)), epoch: 3))
    }

    @Test func aCardNoLongerInHandDropsIt() {
        #expect(!hold.stands(TableModel(room: makeRoom(step: .play, hands: [0: [6, 7]])), epoch: 3))
    }

    @Test func aCucumbersCatMustStillBeThere() {
        let aimed = DiscardHold(card: 104, target: 2, seat: 0, epoch: 3, serial: 2)
        #expect(aimed.stands(TableModel(room: makeRoom(step: .play, hands: [0: [104]])), epoch: 3))
        let gone = makeRoom(step: .play, hands: [0: [104]], forfeited: [false, false, true, false])
        #expect(!aimed.stands(TableModel(room: gone), epoch: 3))
    }

    @Test func theWindowIsShortButUsable() {
        #expect(DiscardHold.window >= 2 && DiscardHold.window <= 5)
    }
}

@Suite struct LobbyPlanTests {
    @Test func aNewTableWaitsForItsOpenSeat() {
        let table = lobby([.human, .open, .closed, .closed, .closed, .closed])
        #expect(table.playerCount == 1)
        #expect(table.startBlock == .openSeats(open: 1, players: 1))
        #expect(table.startClosingOpenSeats == nil)  // one cat can't play alone
        #expect(table.seatToAdd == 1)
    }

    @Test func startCanCloseTheEmptySeatsOnceTwoCatsSit() {
        let table = lobby([.human, .bot, .open, .closed, .open, .closed])
        #expect(table.startBlock == .openSeats(open: 2, players: 2))
        #expect(table.startClosingOpenSeats == [
            .configure(seat: 2, kind: .closed), .configure(seat: 4, kind: .closed), .start,
        ])
        #expect(!table.canStart)
    }

    @Test func nothingBlocksAFullEnoughTable() {
        let table = lobby([.human, .bot, .closed, .closed, .closed, .closed])
        #expect(table.startBlock == nil)
        #expect(table.canStart)
        #expect(table.startClosingOpenSeats == nil)
        #expect(table.seatToAdd == 2)
    }

    @Test func aloneWithEverySeatClosedNeedsAPlayer() {
        let table = lobby([.human, .closed, .closed, .closed, .closed, .closed])
        #expect(table.startBlock == .notEnoughPlayers(players: 1))
        #expect(table.seatToAdd == 1)
    }

    @Test func aPhoneWithNoSeatCantStart() {
        let table = lobby([.human, .open, .closed, .closed, .closed, .closed], mine: [])
        #expect(table.startBlock == .notSeated)
        #expect(table.practiceMessages == nil)
    }

    @Test func aFullTableHasNoSeatToAdd() {
        #expect(lobby([.human, .bot, .bot, .bot, .bot, .bot]).seatToAdd == nil)
    }

    @Test func practiceSeatsAHouseCatClosesTheRestAndStarts() {
        let fresh = lobby([.human, .open, .closed, .closed, .closed, .closed])
        #expect(fresh.practiceMessages == [.configure(seat: 1, kind: .bot), .start])
        let wide = lobby([.human, .open, .open, .closed, .closed, .closed])
        #expect(wide.practiceMessages == [.configure(seat: 1, kind: .bot), .configure(seat: 2, kind: .closed), .start])
        let shut = lobby([.human, .closed, .closed, .closed, .closed, .closed])
        #expect(shut.practiceMessages == [.configure(seat: 1, kind: .bot), .start])
    }

    @Test func practiceIsOnlyForATableWithNobodyElse() {
        #expect(lobby([.human, .bot, .open, .closed, .closed, .closed]).practiceMessages == nil)
        #expect(lobby([.human, .human, .open, .closed, .closed, .closed]).practiceMessages == nil)
        // Two people on this one phone may still practice together against the House Cat.
        let two = lobby([.human, .human, .open, .closed, .closed, .closed], mine: [0, 1])
        #expect(two.practiceMessages == [.configure(seat: 2, kind: .bot), .start])
        #expect(TableModel(room: makeRoom()).practiceMessages == nil)  // not in the lobby
    }
}

@Suite struct NameFitTests {
    /// 10 pt per letter at 20 pt type, in proportion.
    private let measure: (String, CGFloat) -> CGFloat = { text, size in CGFloat(text.count) * size / 2 }

    @Test func aShortNameKeepsThePreferredSize() {
        let fit = NameFit.fit("Leo", width: 100, sizes: [20, 18, 16], measure: measure)
        #expect(fit == NameFit.Result(text: "Leo", size: 20, whole: true))
    }

    @Test func aLongNameShrinksBeforeItIsCut() {
        // 9 letters: 90 at 20 pt, 81 at 18, 72 at 16.
        let fit = NameFit.fit("Josephine", width: 75, sizes: [20, 18, 16], measure: measure)
        #expect(fit == NameFit.Result(text: "Josephine", size: 16, whole: true))
    }

    @Test func aNumberedHouseCatKeepsItsNumber() {
        // "House Cat 2" is 88 wide at 16 pt; "House 2" is 56.
        let fit = NameFit.fit("House Cat 2", width: 60, sizes: [16], measure: measure)
        #expect(fit.text == "House 2")
        #expect(!fit.whole)
    }

    @Test func wordsGoBeforeLetters() {
        #expect(NameFit.fit("Mary Jane", width: 60, sizes: [16], measure: measure).text == "Mary J.")
        #expect(NameFit.fit("Mary Jane", width: 40, sizes: [16], measure: measure).text == "Mary")
        #expect(NameFit.fit("House Cat", width: 64, sizes: [16], measure: measure).text == "House C.")
    }

    @Test func oneLongWordGetsAnEllipsis() {
        let fit = NameFit.fit("Bartholomew", width: 48, sizes: [16], measure: measure)
        #expect(fit.text == "Barth…")
        #expect(measure(fit.text, 16) <= 48)
    }

    @Test func neverBelowTheSmallestSize() {
        let sizes = NameFit.sizes(preferred: 22, minimum: 16)
        #expect(sizes.first == 22 && sizes.last == 16)
        #expect(NameFit.fit("Maximilian the Great", width: 30, sizes: sizes, measure: measure).size == 16)
        #expect(NameFit.sizes(preferred: 16, minimum: 16) == [16])
    }
}

@Suite struct TableTextScaleTests {
    @Test func theSettingGrowsTheWordsUpToACap() {
        #expect(TableTextScale.scale(scaledHundred: 100) == 1)
        #expect(TableTextScale.scale(scaledHundred: 88) == 1)  // a smaller setting never shrinks the table's words
        #expect(TableTextScale.scale(scaledHundred: 124) == 1.24)
        #expect(TableTextScale.scale(scaledHundred: 310) == TableTextScale.most)
        #expect(TableTextScale.nameSize(scale: 1) == 16)
        #expect(TableTextScale.nameSize(scale: 1.4) == 22)
        #expect(TableTextScale.nameFloor >= 16)
    }

    @Test func chipsGrowOnlyWhereTheBarHasRoom() {
        // Five cats on the smallest phone: no room, the chips stay as they are.
        let crowded = TableLayout(size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0, opponents: 5)
        #expect(TableTextScale.chips(scale: 1.4, spacing: crowded.opponentSpacing, diameter: crowded.opponentDiameter) < 1.25)
        // One cat: all the room there is.
        let roomy = TableLayout(size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0, opponents: 1)
        #expect(TableTextScale.chips(scale: 1.4, spacing: roomy.opponentSpacing, diameter: roomy.opponentDiameter) == 1.4)
        #expect(TableTextScale.chips(scale: 1, spacing: 60, diameter: 48) == 1)
    }
}

@Suite struct MenuButtonLayoutTests {
    /// Phones with a short safe top tuck the paw into the bar's corner; with a notch or island
    /// it sits in the status bar's ear.
    private static let phones: [(CGSize, CGFloat, CGFloat)] = [
        (CGSize(width: 320, height: 568), 20, 0),
        (CGSize(width: 375, height: 667), 20, 0),
        (CGSize(width: 393, height: 852), 59, 34),
        (CGSize(width: 440, height: 956), 62, 34),
    ]

    @Test func thePawNeverLiesOverACat() {
        for (size, top, bottom) in Self.phones {
            for n in 1...6 {
                let l = TableLayout(size: size, safeTop: top, safeBottom: bottom, opponents: n)
                let d = l.opponentDiameter
                let paw = CGRect(
                    x: l.menuButton.x - l.menuSide / 2, y: l.menuButton.y - l.menuSide / 2, width: l.menuSide, height: l.menuSide)
                for (i, slot) in l.opponentSlots.enumerated() {
                    let cat = CGRect(x: slot.x - d / 2, y: slot.y + l.catLift - d / 2, width: d, height: d)
                    // The drawn paw and the drawn cat never share more than a sliver.
                    let shared = paw.intersection(cat)
                    #expect(shared.isNull || shared.width * shared.height <= 12, "\(size) \(n) cats, slot \(i): \(shared)")
                }
            }
        }
    }

    @Test func aTuckedPawsTouchTargetIsClearOfEveryCat() {
        for (size, top, bottom) in Self.phones where top < 44 {
            for n in 3...6 {
                let l = TableLayout(size: size, safeTop: top, safeBottom: bottom, opponents: n)
                for i in l.opponentSlots.indices {
                    #expect(!l.menuButtonFrame.intersects(l.opponentFrame(i)), "\(size) \(n) cats, slot \(i)")
                }
                #expect(l.opponentDiameter >= 32, "\(size) \(n) cats: \(l.opponentDiameter)")
            }
        }
    }

    @Test func aTapOnACatsFaceIsTheCatsEvenBesideThePaw() {
        for (size, top, bottom) in Self.phones {
            for n in 1...6 {
                let l = TableLayout(size: size, safeTop: top, safeBottom: bottom, opponents: n)
                let last = n - 1
                let face = CGPoint(x: l.opponentSlots[last].x, y: l.opponentSlots[last].y + l.catLift)
                #expect(!l.menuWins(at: face, overCat: last), "\(size) \(n) cats")
                #expect(l.menuWins(at: l.menuButton, overCat: last), "\(size) \(n) cats")
                // The cat's top right corner, the nearest point to the paw.
                let r = l.opponentDiameter / 2 * 0.7
                let corner = CGPoint(x: face.x + r, y: face.y + r)
                if !l.menuButtonFrame.contains(corner) { continue }
                #expect(!l.menuWins(at: corner, overCat: last), "\(size) \(n) cats: the paw takes the cat's corner")
            }
        }
    }

    @Test func oneAndTwoCatsStayCentered() {
        let l = TableLayout(size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0, opponents: 2)
        #expect(l.opponentSlots.map(\.x) == [93.75, 281.25])
    }
}

@Suite struct GestureTipTests {
    private func ctx(myTurn: Bool, step: TurnStep = .draw, others: Bool = true, towerOpen: Bool = false) -> CoachContext {
        CoachContext(
            person: "a", epoch: 1, myTurn: myTurn, step: step, phase: Rules.phases[0], layDownReady: false,
            canHit: false, hasYarn: false, hasCucumber: false, handCount: 10, others: others, towerOpen: towerOpen)
    }

    private let basics: Set<CoachTip> = [.goal, .draw, .phase, .discard]

    @Test func gestureTipsWaitForAFirstWholeTurn() {
        #expect(CoachTip.next(for: ctx(myTurn: false), seen: [.goal]) == nil)
        #expect(CoachTip.next(for: ctx(myTurn: false), seen: [.goal, .draw]) == nil)
        #expect(CoachTip.next(for: ctx(myTurn: false), seen: basics) == .cats)
        #expect(CoachTip.next(for: ctx(myTurn: false), seen: basics.union([.cats])) == .swipeHome)
        #expect(CoachTip.next(for: ctx(myTurn: false), seen: basics.union([.cats, .swipeHome])) == nil)
    }

    @Test func gestureTipsKeepOutOfMyOwnTurn() {
        #expect(CoachTip.next(for: ctx(myTurn: true, step: .play), seen: basics) == nil)
        #expect(!CoachTip.cats.applies(ctx(myTurn: true)))
        #expect(!CoachTip.swipeHome.applies(ctx(myTurn: true)))
        #expect(!CoachTip.cats.applies(ctx(myTurn: false, others: false)))
    }

    @Test func theOpenTowerSaysTapAgainForScores() {
        #expect(CoachTip.next(for: ctx(myTurn: false, towerOpen: true), seen: [.goal]) == .scores)
        #expect(!CoachTip.scores.applies(ctx(myTurn: false)))
        // It comes down as soon as the tower folds.
        var coach = Coach()
        coach.update(ctx(myTurn: false, towerOpen: true), seen: [.goal])
        #expect(coach.tip == .scores)
        coach.update(ctx(myTurn: false), seen: [.goal, .scores])
        #expect(coach.tip == nil)
    }

    @Test func eachGestureTipShowsOnce() {
        var coach = Coach()
        var seen = basics
        seen.formUnion(coach.update(ctx(myTurn: false), seen: seen))
        #expect(coach.tip == .cats)
        coach.dismiss()
        seen.formUnion(coach.update(ctx(myTurn: false), seen: seen))
        #expect(coach.tip == .swipeHome)
        coach.dismiss()
        seen.formUnion(coach.update(ctx(myTurn: false), seen: seen))
        #expect(coach.tip == nil)
        #expect(seen.isSuperset(of: [.cats, .swipeHome]))
    }

    @Test func gestureTipsSurviveTheTutorialFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pounce-tests-\(UUID().uuidString)")
        let store = TutorialStore(directory: dir)
        store.markSeen([.scores, .cats, .swipeHome], person: "a")
        #expect(store.load()["a"] == [.scores, .cats, .swipeHome])
    }
}
