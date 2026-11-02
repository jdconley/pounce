import Testing
@testable import PounceKit

@Suite struct HandOrderTests {
    @Test func syncKeepsOrderAndAppendsNewCards() {
        var order = HandOrder()
        order.sync([5, 1, 9])
        #expect(order.cards == [5, 1, 9])
        order.move(9, before: 5)
        #expect(order.cards == [9, 5, 1])
        order.sync([1, 5, 9, 40])  // drew 40
        #expect(order.cards == [9, 5, 1, 40])
        order.sync([40, 9])  // played 5 and 1
        #expect(order.cards == [9, 40])
    }

    @Test func moveBeforeAndToEnd() {
        var order = HandOrder()
        order.sync([1, 2, 3, 4])
        order.move(1, before: nil)
        #expect(order.cards == [2, 3, 4, 1])
        order.move(4, before: 2)
        #expect(order.cards == [4, 2, 3, 1])
        order.move(4, before: 4)
        #expect(order.cards == [4, 2, 3, 1])
        order.move(77, before: 2)
        #expect(order.cards == [4, 2, 3, 1])
    }

    @Test func moveToSlotReadsAsTheFanShowedIt() {
        var order = HandOrder()
        order.sync([1, 2, 3, 4, 5])
        // Dragging 1 over the fan [2, 3, 4, 5]: slot 2 puts it between 3 and 4.
        order.move(1, toSlot: 2, shown: [1, 2, 3, 4, 5])
        #expect(order.cards == [2, 3, 1, 4, 5])
        order.move(5, toSlot: 0, shown: order.cards)
        #expect(order.cards == [5, 2, 3, 1, 4])
        order.move(5, toSlot: 4, shown: order.cards)
        #expect(order.cards == [2, 3, 1, 4, 5])
        // Back into its own slot: nothing moves. Out-of-range slots clamp.
        order.move(1, toSlot: 2, shown: order.cards)
        #expect(order.cards == [2, 3, 1, 4, 5])
        order.move(2, toSlot: 99, shown: order.cards)
        #expect(order.cards == [3, 1, 4, 5, 2])
        order.move(2, toSlot: -3, shown: order.cards)
        #expect(order.cards == [2, 3, 1, 4, 5])
        #expect(order.sort == nil)
    }

    @Test func moveToSlotKeepsTrayCardsInPlace() {
        var order = HandOrder()
        order.sync([1, 2, 3, 4, 5])
        // 3 and 5 sit in trays, so the fan shows [1, 2, 4]; 1 goes to the fan's end.
        order.move(1, toSlot: 2, shown: [2, 4])
        #expect(order.cards.filter { [1, 2, 4].contains($0) } == [2, 4, 1])
        #expect(order.cards == [2, 3, 4, 1, 5])
        // A tray card coming back lands in the fan's slot 1.
        order.move(5, toSlot: 1, shown: [2, 4, 1])
        #expect(order.cards.filter { [1, 2, 4, 5].contains($0) } == [2, 5, 4, 1])
    }

    @Test func sortCyclesNumberAndCoat() {
        var order = HandOrder()
        // 7 gray, Cucumber, 2 tabby, Yarn, 7 tabby, 2 calico
        order.sync([79, 104, 1, 96, 6, 49])
        order.cycleSort()
        #expect(order.sort == .number)
        #expect(order.cards == [1, 49, 6, 79, 96, 104])
        order.cycleSort()
        #expect(order.sort == .coat)
        #expect(order.cards == [1, 6, 49, 79, 96, 104])
        order.move(104, before: 1)
        #expect(order.sort == nil)
        order.cycleSort()
        #expect(order.sort == .number)
    }
}
