import CoreGraphics
import Foundation
import Testing
@testable import PounceKit

@Suite struct WidgetClientTests {
    private func stored() -> MemoryCredentialStore {
        let s = MemoryCredentialStore()
        s.save(DeviceCredential(deviceId: "dev1", token: "tok1"))
        return s
    }

    @Test func testNoMintClientNeverMints() async throws {
        let server = StubServer { _ in Reply(200, #"{"deviceId":"dev2","token":"tok2"}"#) }
        let api = APIClient(config: server.config(), credentials: MemoryCredentialStore(), session: server.session(), mints: false)
        await #expect(throws: APIError.unauthorized) { try await api.streaks(person: "me") }
        #expect(server.seen.isEmpty, "no POST /v1/devices from a widget")
    }

    @Test func testNoMintClientKeepsCredentialOn401() async throws {
        let server = StubServer { _ in Reply(401) }
        let store = stored()
        let api = APIClient(config: server.config(), credentials: store, session: server.session(), mints: false)
        await #expect(throws: APIError.unauthorized) { try await api.streaks(person: "me") }
        #expect(store.load() == DeviceCredential(deviceId: "dev1", token: "tok1"), "the app's credential stays")
        #expect(server.seen.map(\.path) == ["/v1/me/streaks"], "no re-mint, no retry")
    }

    @Test func noMintClientUsesTheStoredCredential() async throws {
        let server = StubServer { _ in Reply(200, #"{"pairs":[]}"#) }
        let api = APIClient(config: server.config(), credentials: stored(), session: server.session(), mints: false)
        #expect(try await api.streaks(person: "me").pairs.isEmpty)
        #expect(server.seen.first?.authorization == "Bearer tok1")
    }

    @Test func setWidgetPushTokenPutsTheToken() async throws {
        let server = StubServer { _ in Reply(204, "") }
        let api = APIClient(config: server.config(), credentials: stored(), session: server.session(), mints: false)
        let hex = String(repeating: "cd", count: 32)
        #expect(try await api.setWidgetPushToken(hex) == "dev1")
        let put = try #require(server.seen.last)
        #expect(put.method == "PUT")
        #expect(put.path == "/v1/devices/me/widget-push")
        let json = try #require(try JSONSerialization.jsonObject(with: put.body) as? [String: String])
        #expect(json == ["token": hex])
    }
}

@Suite struct WidgetPushTokenTests {
    private let token = String(repeating: "ab", count: 32)

    @Test func uploadsOnceForTeensAndAdults() {
        for band in [AgeBand.teen, .adult] {
            #expect(WidgetPushToken.needsUpload(token: token, deviceId: "dev1", last: nil, band: band))
            let last = WidgetPushToken.Uploaded(deviceId: "dev1", token: token)
            #expect(!WidgetPushToken.needsUpload(token: token, deviceId: "dev1", last: last, band: band))
            #expect(!WidgetPushToken.needsUpload(token: token, deviceId: nil, last: last, band: band))
            #expect(WidgetPushToken.needsUpload(token: token, deviceId: "dev2", last: last, band: band), "a new device")
            #expect(WidgetPushToken.needsUpload(token: "ef" + token.dropFirst(2), deviceId: "dev1", last: last, band: band))
        }
        #expect(!WidgetPushToken.needsUpload(token: nil, deviceId: "dev1", last: nil, band: .adult))
        #expect(!WidgetPushToken.needsUpload(token: "", deviceId: "dev1", last: nil, band: .adult))
    }

    @Test func testKittenNeverUploads() {
        #expect(!WidgetPushToken.uploads(band: .kitten))
        #expect(!WidgetPushToken.needsUpload(token: token, deviceId: "dev1", last: nil, band: .kitten))
    }

    @Test func testUnknownBandNeverUploads() {
        #expect(!WidgetPushToken.uploads(band: nil))
        #expect(!WidgetPushToken.needsUpload(token: token, deviceId: "dev1", last: nil, band: nil))
    }

    @Test func storeKeepsTheLastUpload() {
        let store = WidgetSnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("wp-\(UUID().uuidString)"))
        #expect(store.uploadedToken == nil)
        store.uploadedToken = .init(deviceId: "dev1", token: token)
        #expect(store.uploadedToken == .init(deviceId: "dev1", token: token))
        store.uploadedToken = nil
        #expect(store.uploadedToken == nil)
    }
}

/// Serialized: a send in flight is remembered process-wide by pair (the double-tap guard).
@MainActor @Suite(.serialized) struct WidgetPounceTests {
    let la = widgetCalendar()
    let now = at(2026, 11, 5, 21)

    private func snapshot(_ p: PounceState = .none) -> WidgetSnapshot {
        var mia = streakView("pr_mia", count: 9)
        mia.pounce = p
        return widgetSnapshot([mia, streakView("pr_kiki", count: 2)], now: at(2026, 11, 5, 20, 55))
    }

    @Test func readySendsYouPickOnce() async {
        let fake = FakePounces()
        let (next, result) = await WidgetPounce.send(snapshot: snapshot(), pair: "pr_mia", service: fake, now: now, calendar: la)
        #expect(result == .sent("pc_1"))
        #expect(fake.calls.withLock { $0 } == ["send pr_mia pick"])
        #expect(next.pairs[0].pounce.sent)
        #expect(next.pounced["pr_mia"] == now)
        #expect(UsWidgetState.make(next, pair: "pr_mia", at: now, calendar: la).pounce == .sent(quiet: false))
        #expect(next.pairs[1] == snapshot().pairs[1])
        // A second tap while the check shows sends nothing.
        let (_, again) = await WidgetPounce.send(snapshot: next, pair: "pr_mia", service: fake, now: now, calendar: la)
        #expect(again == nil)
        #expect(fake.calls.withLock { $0 }.count == 1)
    }

    @Test func aDoubleTapSendsOnce() async {
        // Two performs read the same ready snapshot before either saved.
        let fake = FakePounces()
        let s = snapshot()
        async let a = WidgetPounce.send(snapshot: s, pair: "pr_mia", service: fake, now: now, calendar: la)
        async let b = WidgetPounce.send(snapshot: s, pair: "pr_mia", service: fake, now: now, calendar: la)
        let results = await [a.1, b.1]
        #expect(fake.calls.withLock { $0 }.count == 1)
        #expect(results.compactMap { $0 } == [.sent("pc_1")], "the other tap does nothing (and writes nothing)")
    }

    @Test func theIntentMergesOnlyThisPairsBell() async {
        let fake = FakePounces()
        let (sent, _) = await WidgetPounce.send(snapshot: snapshot(), pair: "pr_mia", service: fake, now: now, calendar: la)
        var current = snapshot()
        current.pairs[1].count = 99  // the app wrote meanwhile
        current.band = .teen
        let merged = current.mergingPounce("pr_mia", from: sent, now: now)
        #expect(merged.pairs[0].pounce.sent)
        #expect(merged.pounced["pr_mia"] == now)
        #expect(merged.pairs[1].count == 99 && merged.band == .teen)
        #expect(merged.pairsAt == now)
    }

    @Test func onlyFromReady() async {
        for state in [PounceState(sent: true), PounceState(resting: true), PounceState(answer: .later)] {
            let fake = FakePounces()
            let (next, result) = await WidgetPounce.send(snapshot: snapshot(state), pair: "pr_mia", service: fake, now: now, calendar: la)
            #expect(result == nil)
            #expect(fake.calls.withLock { $0 }.isEmpty)
            #expect(next == snapshot(state))
        }
    }

    @Test func restingFrom429() async {
        let fake = FakePounces(send: .failure(.rateLimited))
        let (next, result) = await WidgetPounce.send(snapshot: snapshot(), pair: "pr_mia", service: fake, now: now, calendar: la)
        #expect(result == .resting)
        #expect(UsWidgetState.make(next, pair: "pr_mia", at: now, calendar: la).pounce == .resting)
    }

    @Test func failureLeavesTheSnapshot() async {
        let fake = FakePounces(send: .failure(.transport("offline")))
        let (next, result) = await WidgetPounce.send(snapshot: snapshot(), pair: "pr_mia", service: fake, now: now, calendar: la)
        #expect(result == .failed)
        #expect(next == snapshot())
    }

    @Test func demoMarksSentWithNoNetwork() async {
        let (next, result) = await WidgetPounce.send(snapshot: snapshot(), pair: "pr_mia", service: nil, now: now, calendar: la)
        #expect(result != nil)
        #expect(next.pairs[0].pounce.sent)
    }

    @Test func unknownPairDoesNothing() async {
        let fake = FakePounces()
        let (_, result) = await WidgetPounce.send(snapshot: snapshot(), pair: "pr_gone", service: fake, now: now, calendar: la)
        #expect(result == nil)
        #expect(fake.calls.withLock { $0 }.isEmpty)
    }
}

@Suite struct MonoArtTests {
    /// A 3x1 image: opaque black, opaque white, clear.
    private func strip() -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        var pixels: [UInt8] = [0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 0]
        let ctx = CGContext(
            data: &pixels, width: 3, height: 1, bitsPerComponent: 8, bytesPerRow: 12, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    @Test func alphaFollowsInk() throws {
        let mono = try #require(MonoArt.template(strip()))
        let px = try #require(MonoArt.pixels(mono))
        #expect(px.count == 12)
        #expect(px[3] == 255, "ink stays solid")
        #expect(px[7] <= 51, "white is nearly clear")
        #expect(px[7] > 0, "but still a shape")
        #expect(px[11] == 0, "clear stays clear")
        // White, premultiplied: every channel equals alpha.
        for i in stride(from: 0, to: 12, by: 4) {
            #expect(px[i] == px[i + 3] && px[i + 1] == px[i + 3] && px[i + 2] == px[i + 3])
        }
    }
}
