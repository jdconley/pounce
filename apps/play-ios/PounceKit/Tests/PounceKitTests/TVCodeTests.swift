import Foundation
import PounceKit
import Testing

/// "Show on TV": the scanner takes only a TV's link, and a typed backup code is cleaned up.
@Suite struct TVCodeTests {
    private let token = "dXEFk25T_lIQ7aDyHSVP2w"

    @Test func aTVsQRGivesItsToken() {
        #expect(TVCode.token(scanned: "https://play.conleychaos.com/tv/\(token)") == token)
        // The scanner's text may carry a stray newline.
        #expect(TVCode.token(scanned: " https://play.conleychaos.com/tv/\(token)\n") == token)
        #expect(TVCode.token(scanned: DeepLink.tvURL(token: token).absoluteString) == token)
    }

    @Test func anyOtherQRIsIgnored() {
        for text in [
            "",
            "hello",
            token,
            "BCDFGH",
            // Pounce's other links: an invite, a move, a pounce.
            "https://play.conleychaos.com/j/BCDFG",
            "https://play.conleychaos.com/j/BCDFG?move=BCDFGH",
            "https://play.conleychaos.com/p/\(token)",
            // Near misses.
            "http://play.conleychaos.com/tv/\(token)",
            "https://play.conleychaos.com:8443/tv/\(token)",
            "https://play.conleychaos.com.evil.example/tv/\(token)",
            "https://evil.example/tv/\(token)",
            "https://evil.example/?u=https://play.conleychaos.com/tv/\(token)",
            "https://someone@play.conleychaos.com/tv/\(token)",
            "https://play.conleychaos.com/tv/\(token)/",
            "https://play.conleychaos.com/tv/\(token)?x=1",
            "https://play.conleychaos.com/tv/\(token)#x",
            "https://play.conleychaos.com/tv/\(token.dropLast())",
            "https://play.conleychaos.com/tv/\(token)A",
            "https://play.conleychaos.com/tv/dXEFk25T+lIQ7aDyHSVP2w",
            "https://play.conleychaos.com/TV/\(token)",
            "https://play.conleychaos.com/play/tv-link/\(token)",
            // The debug scheme never counts for a scanned code, even in a debug build.
            "pounce-dev://tv/\(token)",
            "WIFI:S:Home;T:WPA;P:secret;;",
        ] {
            #expect(TVCode.token(scanned: text) == nil, "\(text)")
        }
    }

    @Test func aTypedCodeIsNormalised() {
        #expect(TVCode.normalized("BCDFGH") == "BCDFGH")
        #expect(TVCode.normalized("bcdfgh") == "BCDFGH")
        #expect(TVCode.normalized(" bcd fgh ") == "BCDFGH")
        #expect(TVCode.normalized("BCD-FGH") == "BCDFGH")
        #expect(TVCode.normalized("bc-df-gh") == "BCDFGH")
        #expect(TVCode.normalized("2346 79") == "234679")
    }

    @Test func aWrongLengthOrLetterIsNoCode() {
        for text in ["", "BCDFG", "BCDFGHJ", "BCDFGA", "BCDF0H", "BCDF1H", "BCDFOH", "BCD.FGH", "BCDFG\u{00C9}"] {
            #expect(TVCode.normalized(text) == nil, "\(text)")
        }
        #expect(TVCode.length == 6)
    }
}

/// What Show on TV shows first.
@Suite struct TVSheetStartTests {
    @Test func noScannerMeansTheCodeEntryWhateverThePermission() {
        for permission in [CameraPermission.authorized, .denied, .restricted, .notDetermined] {
            for ask in [true, false] {
                #expect(TVSheetStart.first(supported: false, available: false, permission: permission, askForCamera: ask) == .type)
            }
        }
    }

    @Test func deniedOrRestrictedIsTheCodeEntry() {
        for permission in [CameraPermission.denied, .restricted] {
            for ask in [true, false] {
                #expect(TVSheetStart.first(supported: true, available: true, permission: permission, askForCamera: ask) == .type)
                #expect(TVSheetStart.first(supported: true, available: false, permission: permission, askForCamera: ask) == .type)
            }
        }
    }

    @Test func notDeterminedAsksOnlyFromTheButton() {
        #expect(TVSheetStart.first(supported: true, available: false, permission: .notDetermined, askForCamera: true) == .askForCamera)
        // A TV link opened on the phone never asks for the camera.
        #expect(TVSheetStart.first(supported: true, available: false, permission: .notDetermined, askForCamera: false) == .type)
        #expect(TVSheetStart.afterAsking(allowed: true, available: true) == .scan)
        #expect(TVSheetStart.afterAsking(allowed: true, available: false) == .type)
        #expect(TVSheetStart.afterAsking(allowed: false, available: true) == .type)
    }

    @Test func authorizedScansOnlyWhenTheScannerCanRun() {
        #expect(TVSheetStart.first(supported: true, available: true, permission: .authorized, askForCamera: true) == .scan)
        #expect(TVSheetStart.first(supported: true, available: true, permission: .authorized, askForCamera: false) == .scan)
        #expect(TVSheetStart.first(supported: true, available: false, permission: .authorized, askForCamera: true) == .type)
    }
}

/// A QR that didn't link is tried again only when the server didn't refuse it.
@Suite struct TVScanRetryTests {
    @Test func aFailureOrACancelTriesAgain() {
        #expect(TVCode.retriesScan(after: nil), "Cancel on Move the TV to this table?")
        #expect(TVCode.retriesScan(after: URLError(.notConnectedToInternet)))
        #expect(TVCode.retriesScan(after: APIError.server(500)))
        #expect(TVCode.retriesScan(after: APIError.transport("offline")))
    }

    @Test func theServersRefusalsStand() {
        for refusal: ScreenLinkError in [.notFound, .tooManyAttempts(retryAfter: 30), .tooManyAttempts(retryAfter: nil), .notSeated, .seated] {
            #expect(!TVCode.retriesScan(after: refusal), "\(refusal)")
        }
    }
}

/// A pasted TV link isn't counted as an invite pasted.
@Suite struct InviteKindTests {
    @Test func onlyTablesAndPicksAreInvites() {
        let token = "dXEFk25T_lIQ7aDyHSVP2w"
        #expect(DeepLink.join(code: "BCDFG").isInvite)
        #expect(DeepLink.move(code: "BCDFG", moveCode: "BCDFGH").isInvite)
        #expect(DeepLink.pounce(token: token).isInvite)
        #expect(!DeepLink.tv(token: token).isInvite)
        #expect(DeepLink.pasted("https://play.conleychaos.com/tv/\(token)")?.isInvite == false)
    }
}
