import Foundation
import Testing
@testable import PounceKit

/// "Paste invite" (first-run funnel, part 2): the invite pages copy the link before the install,
/// and the app opens what it finds in the pasteboard exactly as a tapped link.
@Suite struct PasteInviteTests {
    @Test func theLinkAnInvitePageCopiesOpensItsTable() {
        #expect(DeepLink.pasted("https://play.conleychaos.com/j/BXDLV") == .join(code: "BXDLV"))
        #expect(DeepLink.pasted("https://play.conleychaos.com/p/dXEFk25T_lIQ7aDyHSVP2w") == .pounce(token: "dXEFk25T_lIQ7aDyHSVP2w"))
        #expect(DeepLink.pasted("https://play.conleychaos.com/j/BXDLV?move=BCDFGH") == .move(code: "BXDLV", moveCode: "BCDFGH"))
    }

    @Test func aWholeInviteMessageWorksAndPunctuationAroundTheLinkIsIgnored() {
        let message = "Come play Tuna Tiles at The Midnight Laser Dots. Code BXDLV\nhttps://play.conleychaos.com/j/BXDLV"
        #expect(DeepLink.pasted(message) == .join(code: "BXDLV"))
        #expect(DeepLink.pasted("(https://play.conleychaos.com/j/BXDLV).") == .join(code: "BXDLV"))
        #expect(DeepLink.pasted("\u{201C}https://play.conleychaos.com/p/dXEFk25T_lIQ7aDyHSVP2w\u{201D}") == .pounce(token: "dXEFk25T_lIQ7aDyHSVP2w"))
        #expect(DeepLink.pasted("  https://play.conleychaos.com/j/BXDLV  \n") == .join(code: "BXDLV"))
    }

    @Test func aRoomCodeOnItsOwnJoinsInAnyCase() {
        #expect(DeepLink.pasted("BXDLV") == .join(code: "BXDLV"))
        #expect(DeepLink.pasted(" bxdlv\n") == .join(code: "BXDLV"))
        // Five letters that can't be a code are not one.
        #expect(DeepLink.pasted("HELLO") == nil)
    }

    @Test func anythingElseIsNotAnInvite() {
        for text in ["", "https://example.com/j/BXDLV", "http://play.conleychaos.com/j/BXDLV", "https://play.conleychaos.com/j/BXDL",
                     "https://play.conleychaos.com/", "see you at dinner", "https://play.conleychaos.com/p/short"] {
            #expect(DeepLink.pasted(text) == nil, "\(text)")
        }
    }

    @Test func theDevSchemeOnlyInDebug() {
        #expect(DeepLink.pasted("pounce-dev://j/BXDLV") == nil)
        #expect(DeepLink.pasted("pounce-dev://j/BXDLV", allowDevScheme: true) == .join(code: "BXDLV"))
    }
}
