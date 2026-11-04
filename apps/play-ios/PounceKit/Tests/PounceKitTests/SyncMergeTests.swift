import Foundation
import Testing
@testable import PounceKit

@Suite struct SyncMergeTests {
    private func entry(_ v: JSONValue, _ at: Int64) -> SyncEntry { SyncEntry(v: v, at: at) }

    @Test func testNewerRemoteIsApplied() {
        let local: SyncSection = ["soundOn": entry(.bool(true), 10)]
        let remote: SyncSection = ["soundOn": entry(.bool(false), 20)]
        let result = SyncMerge.reconcile(local: local, remote: remote)
        #expect(result.apply == remote)
        #expect(result.push.isEmpty)
    }

    @Test func testNewerLocalIsPushedNotOverwritten() {
        let local: SyncSection = ["soundOn": entry(.bool(true), 30)]
        let remote: SyncSection = ["soundOn": entry(.bool(false), 20)]
        let result = SyncMerge.reconcile(local: local, remote: remote)
        #expect(result.push == local)
        #expect(result.apply.isEmpty)
    }

    @Test func testTieKeepsLocal() {
        let local: SyncSection = ["soundOn": entry(.bool(true), 20)]
        let remote: SyncSection = ["soundOn": entry(.bool(false), 20)]
        let result = SyncMerge.reconcile(local: local, remote: remote)
        #expect(result.push.isEmpty)
        #expect(result.apply.isEmpty)
    }

    @Test func testLocalOnlyKeyIsPushed() {
        let local: SyncSection = ["BCDFG": entry(.number(5), 1)]
        let result = SyncMerge.reconcile(local: local, remote: [:])
        #expect(result.push == local)
        #expect(result.apply.isEmpty)
    }

    @Test func testRemoteOnlyKeyIsApplied() {
        let remote: SyncSection = ["BCDFG": entry(.null, 1)]
        let result = SyncMerge.reconcile(local: [:], remote: remote)
        #expect(result.apply == remote)
        #expect(result.push.isEmpty)
    }

    @Test func testChunksSplitAt64Keys() {
        var archive: SyncSection = [:]
        for i in 0..<130 { archive[String(format: "K%04d", i)] = entry(.number(Double(i)), Int64(i)) }
        let patch = StatePatch(settings: ["soundOn": entry(.bool(true), 1)], archive: archive)
        let chunks = SyncMerge.chunks(patch)
        #expect(chunks.count == 3)
        for chunk in chunks {
            #expect((chunk.archive?.count ?? 0) <= 64)
            #expect((chunk.settings?.count ?? 0) <= 64)
        }
        let keys = chunks.flatMap { ($0.archive ?? [:]).keys }
        #expect(keys.count == 130)
        #expect(Set(keys).count == 130)
        #expect(chunks.compactMap(\.settings).flatMap(\.keys) == ["soundOn"])
    }

    @Test func testChunksStayUnderBytes() throws {
        var tutorial: SyncSection = [:]
        let long = String(repeating: "x", count: 200)
        for i in 0..<60 { tutorial["t\(i)"] = entry(.string(long), Int64(i)) }
        let chunks = SyncMerge.chunks(StatePatch(tutorial: tutorial), maxBytes: 4000)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(try JSONEncoder().encode(chunk).count <= 4000)
        }
        #expect(chunks.flatMap { ($0.tutorial ?? [:]).keys }.count == 60)
    }

    @Test func testEmptyPatchHasNoChunks() {
        #expect(SyncMerge.chunks(StatePatch()).isEmpty)
    }

    @Test func testPatchEncodesOnlyPresentSections() throws {
        let data = try JSONEncoder().encode(StatePatch(settings: ["soundOn": entry(.bool(false), 7)]))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["settings"])
        let sound = try #require((object["settings"] as? [String: Any])?["soundOn"] as? [String: Any])
        #expect(sound["v"] as? Bool == false)
        #expect(sound["at"] as? Int == 7)
    }

    @Test func testDecodesServerState() throws {
        let json = """
        {"settings":{"soundOn":{"v":false,"at":1730000000000}},
         "tutorial":{"firstDraw":{"v":true,"at":2}},
         "archive":{"BCDFG":{"v":1730000000001,"at":3},"GHJKL":{"v":null,"at":4}},
         "people":[{"personId":"6f1c0e0e-0000-4000-8000-000000000001","playerId":"p_AAAAAAAAAAAAAAAAAAAAAA","name":"Mia","cat":2}],
         "profile":{"name":"JD","cat":4,"at":99}}
        """
        let state = try JSONDecoder().decode(MeState.self, from: Data(json.utf8))
        #expect(state.settings["soundOn"] == SyncEntry(v: .bool(false), at: 1_730_000_000_000))
        #expect(state.archive["BCDFG"]?.v == .number(1_730_000_000_001))
        #expect(state.archive["GHJKL"]?.v == .null)
        #expect(state.tutorial["firstDraw"]?.v == .bool(true))
        #expect(state.people == [HouseholdPerson(
            personId: "6f1c0e0e-0000-4000-8000-000000000001", playerId: "p_AAAAAAAAAAAAAAAAAAAAAA", name: "Mia", cat: 2)])
        #expect(state.profile == RemoteProfile(name: "JD", cat: 4, at: 99))
    }

    @Test func testDecodesServerStateWithoutProfile() throws {
        let json = #"{"settings":{},"tutorial":{},"archive":{},"people":[],"profile":null}"#
        let state = try JSONDecoder().decode(MeState.self, from: Data(json.utf8))
        #expect(state.profile == nil)
        let older = #"{"settings":{},"tutorial":{},"archive":{},"people":[]}"#
        #expect(try JSONDecoder().decode(MeState.self, from: Data(older.utf8)).profile == nil)
    }
}
