import Foundation
import Testing
@testable import PounceKit

/// The invite sheet's link (trophy room design §4): PR 5's link pounce, kept for an hour so
/// opening the sheet again doesn't spend the 3-an-hour limit; never on a kitten's device.
@Suite struct InviteLinkTests {
    private let url = URL(string: "https://play.conleychaos.com/p/AAAAAAAAAAAAAAAAAAAAAA")!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aKittenGetsTheRoomCodeAndEveryoneElseALink() {
        #expect(InviteLink.mode(AgeLimits(band: .kitten)) == .code)
        #expect(InviteLink.mode(AgeLimits(band: nil)) == .code)
        #expect(InviteLink.mode(AgeLimits(band: .teen)) == .link)
        #expect(InviteLink.mode(AgeLimits(band: .adult)) == .link)
    }

    @Test func aKeptLinkIsReusedWithinTheHour() {
        let kept = InviteLink(url: url, at: t0, pairs: ["pr_mia"])
        #expect(kept.reusable(now: t0.addingTimeInterval(59 * 60), pairs: ["pr_mia"]))
        #expect(!kept.reusable(now: t0.addingTimeInterval(61 * 60), pairs: ["pr_mia"]))
    }

    @Test func aNewConnectionRetiresTheKeptLink() {
        let kept = InviteLink(url: url, at: t0, pairs: ["pr_mia"])
        #expect(!kept.reusable(now: t0.addingTimeInterval(60), pairs: ["pr_mia", "pr_kim"]))
        // One that left doesn't: the link wasn't used for that.
        #expect(kept.reusable(now: t0.addingTimeInterval(60), pairs: []))
    }

    @Test func whileTheBellRestsAnUnexpiredLinkNobodyUsedStillServes() {
        let kept = InviteLink(url: url, at: t0, pairs: ["pr_mia"])
        #expect(kept.usableWhileResting(now: t0.addingTimeInterval(6 * 24 * 3600), pairs: ["pr_mia"]))
        #expect(!kept.usableWhileResting(now: t0.addingTimeInterval(7 * 24 * 3600 + 60), pairs: ["pr_mia"]))
        #expect(!kept.usableWhileResting(now: t0.addingTimeInterval(60), pairs: ["pr_mia", "pr_kim"]),
                "a new connection probably used it")
    }

    @Test func itsTokenIsTheLinksLastPart() {
        #expect(InviteLink(url: url, at: t0, pairs: []).token == "AAAAAAAAAAAAAAAAAAAAAA")
        #expect(InviteLink(url: URL(string: "https://play.conleychaos.com/x")!, at: t0, pairs: []).token == nil)
    }

    @Test func aKittensRoomCodeIsKeptForAnHour() {
        let code = InviteCode(code: "TB4XN", at: t0)
        #expect(code.reusable(now: t0.addingTimeInterval(59 * 60)))
        #expect(!code.reusable(now: t0.addingTimeInterval(61 * 60)))
    }
}

@Suite struct TVLinkTests {
    private let token = "dXEFk25T_lIQ7aDyHSVP2w"

    @Test func aTVLinkParses() throws {
        #expect(DeepLink.parse(try #require(URL(string: "https://play.conleychaos.com/tv/\(token)"))) == .tv(token: token))
        #expect(DeepLink.tvURL(token: token).absoluteString == "https://play.conleychaos.com/tv/\(token)")
    }

    @Test func theDevSchemeIsDebugOnly() throws {
        let url = try #require(URL(string: "pounce-dev://tv/\(token)"))
        #expect(DeepLink.parse(url) == nil)
        #expect(DeepLink.parse(url, allowDevScheme: true) == .tv(token: token))
    }

    @Test func aWrongTokenOrHostIsNoLink() throws {
        for text in [
            "https://play.conleychaos.com/tv/\(token.dropLast())",
            "https://play.conleychaos.com/tv/\(token)x",
            "https://play.conleychaos.com/tv/dXEFk25T+lIQ7aDyHSVP2w",
            "https://play.conleychaos.com/tv/",
            "https://play.conleychaos.com/tv/\(token)?x=1",
            "https://example.com/tv/\(token)",
            "http://play.conleychaos.com/tv/\(token)",
        ] {
            #expect(DeepLink.parse(try #require(URL(string: text)), allowDevScheme: true) == nil, "\(text)")
        }
    }

    @Test func aPastedTVLinkIsFound() {
        #expect(DeepLink.pasted("scan this: https://play.conleychaos.com/tv/\(token)") == .tv(token: token))
    }
}
