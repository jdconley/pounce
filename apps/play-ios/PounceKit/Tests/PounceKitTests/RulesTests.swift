import Foundation
import Testing
@testable import PounceKit

/// One entry of `apps/play-api/fixtures/groups.json`; extra keys are ignored.
struct GroupVector: Decodable, Sendable, CustomTestStringConvertible {
    struct Req: Decodable, Sendable {
        let kind: GroupKind
        let size: Int
    }

    let name: String
    let reqRaw: Req
    let cards: [CardID]
    let runStart: Int?
    let valid: Bool

    var req: Requirement { Requirement(kind: reqRaw.kind, size: reqRaw.size) }
    var testDescription: String { name }

    private enum CodingKeys: String, CodingKey {
        case name, cards, runStart, valid
        case reqRaw = "req"
    }

    static func load() throws -> [GroupVector] {
        let data = try Data(contentsOf: Fixtures.url("groups.json"))
        return try JSONDecoder().decode([GroupVector].self, from: data)
    }
}

@Suite struct RulesTests {
    @Test func cardDecoding() {
        #expect(Card(id: 0) == .number(value: 1, coat: .tabby))
        #expect(Card(id: 30) == .number(value: 7, coat: .tuxedo))
        #expect(Card(id: 95) == .number(value: 12, coat: .gray))
        #expect(Card(id: 96) == .yarn)
        #expect(Card(id: 104) == .cucumber)
        #expect(Card.deckSize == 108)
    }

    @Test func points() {
        #expect([0, 9, 11, 96, 104].map(Card.points) == [5, 10, 10, 25, 15])
    }

    @Test func phasesMatchServer() {
        #expect(Rules.phases[1] == [Requirement(kind: .set, size: 3), Requirement(kind: .run, size: 4)])
        #expect(Rules.phases[7] == [Requirement(kind: .coat, size: 7)])
        #expect(Rules.phases.count == 10)
    }

    @Test(arguments: try! GroupVector.load())
    func groupVectors(_ v: GroupVector) {
        #expect((Rules.buildGroup(v.req, cards: v.cards, runStart: v.runStart) != nil) == v.valid, "\(v.name)")
    }

    @Test func buildGroupOutputs() {
        #expect(Rules.buildGroup(.init(kind: .set, size: 3), cards: [6, 30, 96])
            == .set(cards: [6, 30, 96], value: 7))
        // 10-11-12 + yarn defaults to start 9, yarn first.
        #expect(Rules.buildGroup(.init(kind: .run, size: 4), cards: [9, 10, 11, 96])
            == .run(cards: [96, 9, 10, 11], start: 9, end: 12))
        #expect(Rules.buildGroup(.init(kind: .coat, size: 2), cards: [96, 48])
            == .coat(cards: [96, 48], coat: .calico))
        // Invalid ids never crash.
        #expect(Rules.buildGroup(.init(kind: .set, size: 2), cards: [0, 108]) == nil)
        #expect(Rules.buildGroup(.init(kind: .set, size: 2), cards: [0, -1]) == nil)
    }

    @Test func hitRunExtendsBothEnds() {
        let run = Rules.buildGroup(.init(kind: .run, size: 4), cards: [2, 27, 52, 77])! // 3-4-5-6
        #expect(Rules.canHit(run, card: 6)?.cards.last == 6)          // 7
        #expect(Rules.canHit(run, card: 1)?.cards.first == 1)         // 2
        #expect(Rules.canHit(run, card: 104) == nil)                  // cucumber
        #expect(Rules.canHit(run, card: 4) == nil)                    // 5 is inside
    }

    @Test func hitYarnOnRunPrefersEndThenStart() {
        let low = Rules.buildGroup(.init(kind: .run, size: 4), cards: [2, 27, 52, 77])!
        #expect(Rules.canHit(low, card: 96) == .run(cards: [2, 27, 52, 77, 96], start: 3, end: 7))
        let high = Rules.buildGroup(.init(kind: .run, size: 4), cards: [8, 9, 10, 11])! // 9-12
        #expect(Rules.canHit(high, card: 96) == .run(cards: [96, 8, 9, 10, 11], start: 8, end: 12))
        #expect(Rules.canHit(high, card: 1) == nil)
        let full = Rules.buildGroup(.init(kind: .run, size: 12), cards: Array(0..<12))!
        #expect(Rules.canHit(full, card: 96) == nil)
    }

    /// JD's bug: a Yarn dropped at the start of a run went to its end.
    @Test func hitYarnOnRunTakesTheSideAsked() {
        let run = Rules.buildGroup(.init(kind: .run, size: 4), cards: [3, 4, 5, 6])! // 4-5-6-7
        #expect(Rules.canHit(run, card: 96, side: .start) == .run(cards: [96, 3, 4, 5, 6], start: 3, end: 7))
        #expect(Rules.canHit(run, card: 96, side: .end) == .run(cards: [3, 4, 5, 6, 96], start: 4, end: 8))
        #expect(Rules.canHit(run, card: 96) == Rules.canHit(run, card: 96, side: .end))
        // A side that can't take the card refuses it.
        let high = Rules.buildGroup(.init(kind: .run, size: 4), cards: [8, 9, 10, 11])! // 9-12
        #expect(Rules.canHit(high, card: 96, side: .end) == nil)
        let low = Rules.buildGroup(.init(kind: .run, size: 4), cards: [0, 1, 2, 3])! // 1-4
        #expect(Rules.canHit(low, card: 96, side: .start) == nil)
        #expect(Rules.canHit(run, card: 2, side: .end) == nil)    // a 3 only fits below
        #expect(Rules.canHit(run, card: 2, side: .start)?.cards.first == 2)
        // Sets and coats ignore it.
        let sevens = Rules.buildGroup(.init(kind: .set, size: 2), cards: [6, 30])!
        #expect(Rules.canHit(sevens, card: 96, side: .start) == Rules.canHit(sevens, card: 96))
    }

    @Test func hitSetAndCoat() {
        let sevens = Rules.buildGroup(.init(kind: .set, size: 2), cards: [6, 30])!
        #expect(Rules.canHit(sevens, card: 54) == .set(cards: [6, 30, 54], value: 7))
        #expect(Rules.canHit(sevens, card: 96) != nil)
        #expect(Rules.canHit(sevens, card: 7) == nil)
        #expect(Rules.canHit(sevens, card: 104) == nil)
        let tabby = Rules.buildGroup(.init(kind: .coat, size: 2), cards: [0, 5])!
        #expect(Rules.canHit(tabby, card: 11) == .coat(cards: [0, 5, 11], coat: .tabby))
        #expect(Rules.canHit(tabby, card: 96) != nil)
        #expect(Rules.canHit(tabby, card: 95) == nil)
        #expect(Rules.canHit(tabby, card: 104) == nil)
    }

    @Test func matchPhaseNeedsPhaseOrderAndDistinctCards() {
        let set3 = LayGroup(cards: [6, 30, 54])          // three 7s
        let run4 = LayGroup(cards: [2, 27, 52, 77])      // 3-4-5-6
        let built = Rules.matchPhase(1, groups: [set3, run4])
        #expect(built?.count == 2)
        #expect(built?[0].kind == .set)
        #expect(built?[1].kind == .run)
        #expect(Rules.matchPhase(1, groups: [run4, set3]) == nil)
        #expect(Rules.matchPhase(1, groups: [set3, LayGroup(cards: [2, 27, 52, 6])]) == nil)
        #expect(Rules.matchPhase(1, groups: [set3]) == nil)
        #expect(Rules.matchPhase(10, groups: [set3, run4]) == nil)
        #expect(Rules.matchPhase(-1, groups: [set3, run4]) == nil)
    }

    @Test func matchPhasePassesRunStart() {
        let set3 = LayGroup(cards: [6, 30, 54])
        let withYarn = LayGroup(cards: [9, 10, 11, 96], runStart: 9)
        #expect(Rules.matchPhase(1, groups: [set3, withYarn]) != nil)
        let bad = LayGroup(cards: [9, 10, 11, 96], runStart: 10)
        #expect(Rules.matchPhase(1, groups: [set3, bad]) == nil)
    }

    @Test func groupJSONRoundTrips() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let cases: [(json: String, group: Group)] = [
            (#"{"cards":[6,30,54],"kind":"set","value":7}"#, .set(cards: [6, 30, 54], value: 7)),
            (#"{"cards":[2,27,52,77],"end":6,"kind":"run","start":3}"#, .run(cards: [2, 27, 52, 77], start: 3, end: 6)),
            (#"{"cards":[1,2,3],"coat":"calico","kind":"coat"}"#, .coat(cards: [1, 2, 3], coat: .calico)),
        ]
        for c in cases {
            let decoded = try decoder.decode(Group.self, from: Data(c.json.utf8))
            #expect(decoded == c.group)
            let reencoded = try encoder.encode(decoded)
            #expect(String(decoding: reencoded, as: UTF8.self) == c.json)
            #expect(decoded.kind == c.group.kind)
        }
        // Also accepts the spec's key order.
        let run = try decoder.decode(Group.self, from: Data(#"{"kind":"run","cards":[2,27,52,77],"start":3,"end":6}"#.utf8))
        #expect(run == .run(cards: [2, 27, 52, 77], start: 3, end: 6))
        #expect(throws: (any Error).self) {
            try decoder.decode(Group.self, from: Data(#"{"kind":"run","cards":[1]}"#.utf8))
        }
    }

    @Test func layGroupOmitsNilRunStart() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(String(decoding: try encoder.encode(LayGroup(cards: [1, 2])), as: UTF8.self) == #"{"cards":[1,2]}"#)
        #expect(String(decoding: try encoder.encode(LayGroup(cards: [1, 2], runStart: 4)), as: UTF8.self)
            == #"{"cards":[1,2],"runStart":4}"#)
        let back = try JSONDecoder().decode(LayGroup.self, from: Data(#"{"cards":[1,2]}"#.utf8))
        #expect(back == LayGroup(cards: [1, 2]))
    }
}
