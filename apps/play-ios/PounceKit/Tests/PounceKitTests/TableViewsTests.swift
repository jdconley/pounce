import Foundation
import Testing
@testable import PounceKit

@Suite struct TableViewsTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("table-views-\(UUID().uuidString)")
    }

    @Test func aTableShowsCardsUntilChosen() async {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let views = await TableViews.open(directory: dir)
        #expect(views.view(code: "BCDFG") == .cards)
        views.set(.table, code: "BCDFG")
        #expect(views.view(code: "BCDFG") == .table)
        #expect(views.view(code: "OTHER") == .cards)
        views.set(.cards, code: "BCDFG")
        #expect(views.view(code: "BCDFG") == .cards)
    }

    @Test func theChoiceSurvivesARestart() async {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let views = await TableViews.open(directory: dir)
        views.set(.table, code: "BCDFG")
        await views.flush()
        #expect(await TableViews.open(directory: dir).view(code: "BCDFG") == .table)
    }

    @Test func itKeepsTheNewest30Tables() async {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let views = await TableViews.open(directory: dir)
        for i in 0..<31 { views.set(.table, code: "T\(i)") }
        #expect(views.view(code: "T0") == .cards, "the oldest went")
        for i in 1..<31 { #expect(views.view(code: "T\(i)") == .table, "T\(i)") }
        // Setting an old table again makes it the newest.
        views.set(.cards, code: "T1")
        views.set(.table, code: "T1")
        views.set(.table, code: "NEW")
        #expect(views.view(code: "T1") == .table)
        #expect(views.view(code: "T2") == .cards)
        await views.flush()
        let again = await TableViews.open(directory: dir)
        #expect(again.view(code: "NEW") == .table)
        #expect(again.view(code: "T2") == .cards)
        #expect(again.view(code: "T1") == .table)
    }
}
