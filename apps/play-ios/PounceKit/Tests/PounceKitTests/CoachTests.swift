import Foundation
import Testing
@testable import PounceKit

@Suite struct CoachTests {
    private static let phase1 = Rules.phases[0]
    private static let phase2 = Rules.phases[1]
    private static let phase8 = Rules.phases[7]

    private func ctx(
        person: String = "a", epoch: Int = 1, myTurn: Bool = true, step: TurnStep = .draw,
        phase: [Requirement] = phase1, layDownReady: Bool = false, canHit: Bool = false,
        hasYarn: Bool = false, hasCucumber: Bool = false, handCount: Int = 10
    ) -> CoachContext {
        CoachContext(
            person: person, epoch: epoch, myTurn: myTurn, step: step, phase: phase,
            layDownReady: layDownReady, canHit: canHit, hasYarn: hasYarn, hasCucumber: hasCucumber,
            handCount: handCount)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pounce-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: which tip

    @Test func theGoalComesFirstEvenOnSomeoneElsesTurn() {
        #expect(CoachTip.next(for: ctx(myTurn: false), seen: []) == .goal)
        #expect(CoachTip.next(for: ctx(myTurn: false), seen: [.goal]) == nil)
    }

    @Test func drawThenPhaseThenDiscard() {
        #expect(CoachTip.next(for: ctx(), seen: [.goal]) == .draw)
        let play = ctx(step: .play)
        #expect(CoachTip.next(for: play, seen: [.goal, .draw]) == .phase)
        #expect(CoachTip.next(for: play, seen: [.goal, .draw, .phase]) == .discard)
    }

    @Test func aReadyPhaseBeatsEverythingElseInThePlayStep() {
        let ready = ctx(step: .play, layDownReady: true, hasYarn: true, hasCucumber: true)
        #expect(CoachTip.next(for: ready, seen: [.goal]) == .layDown)
    }

    @Test func specialCardsWaitForTheBasics() {
        let play = ctx(step: .play, hasYarn: true, hasCucumber: true)
        #expect(CoachTip.next(for: play, seen: [.goal, .phase]) == .discard)
        #expect(CoachTip.next(for: play, seen: [.goal, .phase, .discard]) == .cucumber)
        #expect(CoachTip.next(for: play, seen: [.goal, .phase, .discard, .cucumber]) == .yarn)
    }

    @Test func runsAndCoatsGetTheirOwnTipOnceThePhaseAsksForThem() {
        let basics: Set<CoachTip> = [.goal, .phase, .discard]
        #expect(CoachTip.next(for: ctx(step: .play, phase: Self.phase1), seen: basics) == nil)
        #expect(CoachTip.next(for: ctx(step: .play, phase: Self.phase2), seen: basics) == .run)
        #expect(CoachTip.next(for: ctx(step: .play, phase: Self.phase8), seen: basics) == .coat)
    }

    @Test func thePhaseTipCoversTheKindsItExplains() {
        #expect(CoachTip.phase.covers(ctx(phase: Self.phase2)) == [.phase, .run])
        #expect(CoachTip.phase.covers(ctx(phase: Self.phase1)) == [.phase])
        #expect(CoachTip.draw.covers(ctx()) == [.draw])
    }

    @Test func hittingAndGoingOutNeedALaidPhase() {
        let basics: Set<CoachTip> = [.goal, .discard]
        #expect(CoachTip.next(for: ctx(step: .play, canHit: true), seen: basics.union([.phase])) == nil)
        let laid = ctx(step: .play, phase: [], canHit: true, handCount: 2)
        #expect(CoachTip.next(for: laid, seen: basics) == .hit)
        #expect(CoachTip.next(for: laid, seen: basics.union([.hit])) == .goOut)
        #expect(CoachTip.next(for: ctx(step: .play, phase: [], handCount: 5), seen: basics) == nil)
    }

    @Test func nothingButTheGoalOnSomeoneElsesTurn() {
        let waiting = ctx(myTurn: false, step: .play, layDownReady: true, hasYarn: true, hasCucumber: true)
        #expect(CoachTip.next(for: waiting, seen: [.goal]) == nil)
    }

    // MARK: learned by doing

    @Test func drawingTeachesTheDrawTip() {
        #expect(CoachTip.learned(from: ctx(), to: ctx(step: .play)) == [.draw])
    }

    @Test func endingTheTurnTeachesTheDiscardTip() {
        let before = ctx(step: .play)
        #expect(CoachTip.learned(from: before, to: ctx(epoch: 2, myTurn: false)) == [.discard])
        #expect(CoachTip.learned(from: before, to: ctx(epoch: 5, step: .draw)) == [.discard])
    }

    @Test func layingDownTeachesThePhase() {
        let before = ctx(step: .play, phase: Self.phase2, layDownReady: true)
        #expect(CoachTip.learned(from: before, to: ctx(step: .play, phase: [], handCount: 3)) == [.layDown, .phase, .run])
    }

    @Test func aCardLeavingTheHandAfterLayingDownIsAHit() {
        let before = ctx(step: .play, phase: [], handCount: 4)
        #expect(CoachTip.learned(from: before, to: ctx(step: .play, phase: [], handCount: 3)) == [.hit])
    }

    @Test func anotherPersonTeachesNothing() {
        #expect(CoachTip.learned(from: ctx(person: "a"), to: ctx(person: "b", step: .play)).isEmpty)
    }

    // MARK: the coach

    @Test func showsOneTipAtATimeAndMarksItSeen() {
        var coach = Coach()
        var seen: Set<CoachTip> = []
        seen.formUnion(coach.update(ctx(myTurn: false), seen: seen))
        #expect(coach.tip == .goal)
        #expect(seen == [.goal])
        // Still up while it applies; nothing new while one shows.
        #expect(coach.update(ctx(), seen: seen).isEmpty)
        #expect(coach.tip == .goal)
        coach.dismiss()
        #expect(coach.tip == nil)
        seen.formUnion(coach.update(ctx(), seen: seen))
        #expect(coach.tip == .draw)
    }

    @Test func newTipsWaitUntilTheyAreAllowed() {
        var coach = Coach()
        #expect(coach.update(ctx(), seen: [], allowNew: false).isEmpty)
        #expect(coach.tip == nil)
        #expect(coach.update(ctx(), seen: []) == [.goal])
    }

    @Test func aTipGoesAwayWhenItNoLongerApplies() {
        var coach = Coach()
        var seen: Set<CoachTip> = [.goal]
        seen.formUnion(coach.update(ctx(), seen: seen))
        #expect(coach.tip == .draw)
        let learned = coach.update(ctx(step: .play), seen: seen, allowNew: false)
        #expect(coach.tip == nil)
        #expect(learned == [.draw])
        // The hand going face down (a curtain) takes the tip away too.
        seen.formUnion(coach.update(ctx(step: .play), seen: seen))
        #expect(coach.tip == .phase)
        coach.update(nil, seen: seen)
        #expect(coach.tip == nil)
    }

    @Test func atMostTwoNewTipsInOneStep() {
        var coach = Coach()
        var seen: Set<CoachTip> = [.goal]
        let play = ctx(step: .play, hasYarn: true, hasCucumber: true)
        for _ in 0..<2 {
            seen.formUnion(coach.update(play, seen: seen))
            #expect(coach.tip != nil)
            coach.dismiss()
        }
        #expect(coach.update(play, seen: seen).isEmpty)
        #expect(coach.tip == nil)
        // The next turn's play step may show more.
        seen.formUnion(coach.update(ctx(epoch: 3, step: .play, hasYarn: true, hasCucumber: true), seen: seen))
        #expect(coach.tip == .cucumber)
    }

    @Test func learningRemembersEachPersonAcrossACurtain() {
        var coach = Coach()
        let seen = Set(CoachTip.allCases).subtracting([.discard])
        coach.update(ctx(person: "a", step: .play), seen: seen, allowNew: false)
        coach.update(nil, seen: seen, allowNew: false)
        coach.update(ctx(person: "b", epoch: 2, myTurn: true), seen: seen, allowNew: false)
        #expect(coach.update(ctx(person: "a", epoch: 3, myTurn: false), seen: seen, allowNew: false) == [.discard])
    }

    @Test func turningTipsOffLastsForThisCoachOnlyAndOnlyForThatPerson() {
        var coach = Coach()
        coach.update(ctx(person: "a"), seen: [])
        #expect(coach.tip == .goal)
        coach.turnOff()
        #expect(coach.tip == nil)
        #expect(coach.update(ctx(person: "a"), seen: []).isEmpty)
        #expect(coach.update(ctx(person: "b", epoch: 2), seen: []) == [.goal])
        coach.turnOn()
        coach.dismiss()
        #expect(coach.update(ctx(person: "a", epoch: 4), seen: []) == [.goal])
    }

    // MARK: TutorialStore

    @Test func seenTipsArePerPersonAndSurviveARelaunch() throws {
        let dir = try tempDir()
        let store = TutorialStore(directory: dir)
        #expect(store.load().isEmpty)
        store.markSeen([.goal, .draw], person: "a")
        store.markSeen([.phase], person: "b")
        store.markSeen([.discard], person: "a")
        let reloaded = TutorialStore(directory: dir).load()
        #expect(reloaded["a"] == [.goal, .draw, .discard])
        #expect(reloaded["b"] == [.phase])
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("tutorial.json").path))
    }

    @Test func resetForgetsEveryone() throws {
        let dir = try tempDir()
        let store = TutorialStore(directory: dir)
        store.markSeen([.goal], person: "a")
        store.reset()
        #expect(TutorialStore(directory: dir).load().isEmpty)
    }

    @Test func unknownTipsInTheFileAreIgnored() throws {
        let dir = try tempDir()
        try Data(#"{"a":["goal","someday"]}"#.utf8).write(to: dir.appendingPathComponent("tutorial.json"))
        #expect(TutorialStore(directory: dir).load()["a"] == [.goal])
    }
}
