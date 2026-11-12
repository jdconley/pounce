import Foundation
import Testing
@testable import PounceKit

@Suite struct AppVersionTests {
    @Test(arguments: [
        ("1.0", [1]), ("1.1", [1, 1]), ("1.10", [1, 10]), ("2", [2]), ("1.2.3", [1, 2, 3]), ("1.2.3.4", [1, 2, 3, 4]),
        (" 1.2 ", [1, 2]), ("v1.2", [1, 2]), ("V1.2", [1, 2]), ("1.2-beta", [1, 2]), ("1.2 (57)", [1, 2]),
        ("1.2+build", [1, 2]), ("01.02", [1, 2]), ("0.0", [0]), ("1.2.0", [1, 2]), ("1.0.0.0", [1]),
    ])
    func reads(text: String, parts: [Int]) {
        #expect(AppVersion(text)?.parts == parts)
    }

    @Test(arguments: [
        "", " ", "latest", "beta-1.2", ".1", "1.", "1..2", "1.2.x", "1.x", "-1.2", "1.2.3.4.5", "1.1234567",
        "99999999999999999999", "١.٢", "one",
    ])
    func refuses(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func nilIsNoVersion() {
        #expect(AppVersion(nil) == nil)
    }

    @Test func keepsWhatWasWrittenForShowing() {
        #expect(AppVersion("v1.2.0-beta")?.description == "1.2.0")
        #expect(AppVersion("01.2")?.description == "1.2")
    }

    @Test(arguments: [
        ("1.0", "1.1", -1), ("1.1", "1.0", 1), ("1.1", "1.1", 0), ("1.1", "1.1.0", 0), ("1.1.0", "1.1", 0),
        ("1.9", "1.10", -1), ("1.10", "1.9", 1), ("1.10", "1.2", 1), ("2", "1.99.99", 1), ("1.0.1", "1.0", 1),
        ("1", "1.0.0.1", -1),
    ])
    func compares(a: String, b: String, sign: Int) throws {
        let (x, y) = (try #require(AppVersion(a)), try #require(AppVersion(b)))
        #expect((x < y ? -1 : x > y ? 1 : 0) == sign)
        #expect((x == y) == (sign == 0))
        if sign == 0 { #expect(x.hashValue == y.hashValue) }
    }

    @Test func olderOnlyWhenBothRead() {
        #expect(AppVersion.isOlder("1.0", than: "1.1"))
        #expect(!AppVersion.isOlder("1.1", than: "1.1"))
        #expect(!AppVersion.isOlder("1.2", than: "1.1"))
        #expect(!AppVersion.isOlder("soon", than: "1.1"))
        #expect(!AppVersion.isOlder("1.0", than: ""))
        #expect(!AppVersion.isOlder("1.0", than: nil))
        #expect(!AppVersion.isOlder(nil, than: "1.1"))
    }
}

@Suite struct AppIdentityTests {
    @Test func theHeaderIsWhatTheServerParses() {
        let app = AppIdentity(platform: "ios", version: "1.1", build: "57")
        #expect(AppIdentity.header == "X-Pounce-App")
        #expect(app.headerValue == "platform=ios; version=1.1; build=57; protocol=1")
        #expect(ClientHeaders.headers(for: app) == ["X-Pounce-App": "platform=ios; version=1.1; build=57; protocol=1"])
    }

    @Test func itSaysTheProtocolThisBuildSpeaks() {
        #expect(AppIdentity(platform: "ios", version: "1.1").protocolVersion == PounceKit.protocolVersion)
        #expect(AppIdentity(platform: "ios", version: "1.1").headerValue == "platform=ios; version=1.1; protocol=1")
    }

    @Test func readsABundle() {
        let app = AppIdentity(platform: "ios", info: ["CFBundleShortVersionString": "1.1", "CFBundleVersion": "57"])
        #expect(app == AppIdentity(platform: "ios", version: "1.1", build: "57"))
    }

    @Test func aBuildThatIsNotANumberIsLeftOut() {
        for build in ["1.2.3", "", "abc", "1234567890"] {
            let app = AppIdentity(platform: "ios", info: ["CFBundleShortVersionString": "1.1", "CFBundleVersion": build])
            #expect(app?.build == nil)
            #expect(app?.headerValue == "platform=ios; version=1.1; protocol=1")
        }
    }

    @Test func noReadableVersionMeansNoHeaderAtAll() {
        #expect(AppIdentity(platform: "ios", info: nil) == nil)
        #expect(AppIdentity(platform: "ios", info: [:]) == nil)
        #expect(AppIdentity(platform: "ios", info: ["CFBundleShortVersionString": "dev"]) == nil)
        #expect(ClientHeaders.headers(for: nil).isEmpty)
    }

    /// The package's tests and the `pounce-e2e` tool run on a Mac: like version 1.0, they say nothing.
    @Test func offIOSNothingIsSaid() {
        #if os(macOS)
        #expect(AppIdentity.current == nil)
        #expect(ClientHeaders.standard.isEmpty)
        #expect(APIConfig(baseURL: URL(string: "http://localhost:8787")!).headers.isEmpty)
        #endif
    }
}
