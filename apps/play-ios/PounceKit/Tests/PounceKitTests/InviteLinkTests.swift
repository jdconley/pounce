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

    @Test func whileTheBellRestsAnyUnexpiredLinkStillServes() {
        let kept = InviteLink(url: url, at: t0, pairs: [])
        #expect(kept.usableWhileResting(now: t0.addingTimeInterval(23 * 3600)))
        #expect(!kept.usableWhileResting(now: t0.addingTimeInterval(25 * 3600)))
    }
}
