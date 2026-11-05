import Foundation
import Testing
@testable import PounceKit

@Suite struct WidgetLinkTests {
    @Test func roundTrips() {
        for link in [WidgetLink.table("GH2VD"), .us(pair: "pr_3f9cAAAAAAAAAAAAAAAAAA"), .us(pair: nil), .app] {
            #expect(WidgetLink.parse(link.url) == link)
        }
        #expect(WidgetLink.table("GH2VD").url.absoluteString == "pounce-widget://table/GH2VD")
        #expect(WidgetLink.app.url.absoluteString == "pounce-widget://app")
    }

    @Test func rejectsOthers() {
        #expect(WidgetLink.parse(URL(string: "pounce-dev://j/GH2VD")!) == nil)
        #expect(WidgetLink.parse(URL(string: "https://play.conleychaos.com/j/GH2VD")!) == nil)
        #expect(WidgetLink.parse(URL(string: "pounce-widget://table/nope!")!) == nil)
        #expect(WidgetLink.parse(URL(string: "pounce-widget://table")!) == nil)
        #expect(WidgetLink.parse(URL(string: "pounce-widget://elsewhere")!) == nil)
    }
}
