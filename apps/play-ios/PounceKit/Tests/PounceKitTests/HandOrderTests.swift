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
