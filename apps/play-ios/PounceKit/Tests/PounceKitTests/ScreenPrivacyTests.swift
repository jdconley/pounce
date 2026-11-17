import PounceKit
import Testing

/// `pounce-e2e screen`'s check: what a TV hears must hold nothing private.
@Suite struct ScreenPrivacyTests {
    private let seats = #"[{"kind":"human","person":{"id":"a","name":"Mia","cat":1}},{"kind":"bot"}]"#

    @Test func aCleanSnapshotPasses() {
        let snapshot = #"{"t":"snapshot","protocol":1,"seq":4,"room":{"code":"BCDFG","status":"playing","screen":true,"youAreHost":false,"seats":\#(seats),"game":{"round":1,"handCounts":[10,10],"hands":{}},"tiles":{"racks":{}}}}"#
        #expect(ScreenPrivacy.leak(inJSON: snapshot) == nil)
        let bare = #"{"t":"snapshot","protocol":1,"seq":1,"room":{"code":"BCDFG","status":"lobby","seats":\#(seats)}}"#
        #expect(ScreenPrivacy.leak(inJSON: bare) == nil)
    }

    @Test func aHandARackOrASeatIsFlagged() {
        let hand = #"{"t":"snapshot","seq":4,"room":{"seats":\#(seats),"game":{"hands":{"0":[3,17,40]}}}}"#
        #expect(ScreenPrivacy.leak(inJSON: hand) == "hands")
        let rack = #"{"t":"snapshot","seq":4,"room":{"seats":\#(seats),"tiles":{"racks":{"1":[5,6]}}}}"#
        #expect(ScreenPrivacy.leak(inJSON: rack) == "racks")
        let listed = #"{"t":"snapshot","seq":4,"room":{"seats":\#(seats),"game":{"hands":[[3]]}}}"#
        #expect(ScreenPrivacy.leak(inJSON: listed) == "hands")
        let mine = #"{"t":"snapshot","seq":4,"room":{"seats":[{"kind":"human","yours":true}]}}"#
        #expect(ScreenPrivacy.leak(inJSON: mine) == "a seat")
        let host = #"{"t":"snapshot","seq":4,"room":{"seats":[],"youAreHost":true}}"#
        #expect(ScreenPrivacy.leak(inJSON: host) == "the host")
    }

    @Test func aCardOrTileDrawnFromTheDeckIsFlagged() {
        let card = #"{"t":"event","seq":9,"event":{"kind":"game","event":{"kind":"drew","seat":0,"from":"deck","card":42}}}"#
        #expect(ScreenPrivacy.leak(inJSON: card) == "a drawn card")
        let tile = #"{"t":"event","seq":9,"event":{"kind":"tiles","event":{"kind":"drew","seat":1,"tile":7}}}"#
        #expect(ScreenPrivacy.leak(inJSON: tile) == "a drawn tile")
    }

    @Test func publicDrawsPass() {
        // From the discard pile the card was face up already; from the deck, no card named.
        let discard = #"{"t":"event","seq":9,"event":{"kind":"game","event":{"kind":"drew","seat":0,"from":"discard","card":42}}}"#
        #expect(ScreenPrivacy.leak(inJSON: discard) == nil)
        let deck = #"{"t":"event","seq":9,"event":{"kind":"game","event":{"kind":"drew","seat":0,"from":"deck"}}}"#
        #expect(ScreenPrivacy.leak(inJSON: deck) == nil)
        let tile = #"{"t":"event","seq":9,"event":{"kind":"tiles","event":{"kind":"drew","seat":1}}}"#
        #expect(ScreenPrivacy.leak(inJSON: tile) == nil)
        #expect(ScreenPrivacy.leak(inJSON: #"{"t":"aim","seat":0}"#) == nil)
        #expect(ScreenPrivacy.leak(inJSON: "not json") == nil)
    }
}
