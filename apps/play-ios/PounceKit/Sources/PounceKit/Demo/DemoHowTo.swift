#if DEBUG
import Foundation
// DEBUG only: demo and test data never ships in a Release build.

/// The tables the How to play videos are recorded on (`apps/play-ios/HowTo/`). Each is staged so
/// one scripted turn shows a whole lesson.
extension DemoFixtures {
    /// Cat Tower's video (`-demo howto`): round 3, my draw step on level 2 (a set of 3 and a run
    /// of 4), four seats, nobody waiting on a skip. My hand has two 9s, 4-5-6, a Yarn, an 8, a
    /// Cucumber and two loose cards; the deck's top card is the third 9 (`howToDraw`). Leo has
    /// laid a set of 7s and the run 4-7, so the 8 hits his run once my level is down.
    public static func howTo() -> RoomView {
        var room = table(seats: 4, mySeat: 0, phase: 1)
        room.seats[2].presence = .awake
        room.game!.pendingSkip = Array(repeating: false, count: 4)
        room.game!.hands = [0: howToHand]
        room.game!.handCounts[0] = howToHand.count
        room.game!.laid[1] = [
            laidPhaseOne[0],
            .run(cards: [id2(4, .gray), id2(5, .gray), id2(6, .tabby), id2(7, .calico)], start: 4, end: 7),
        ]
        room.game!.phase[1] = 1
        room.game!.handCounts[1] = 3
        balance(&room.game!)
        return room
    }

    static let howToHand: [CardID] = [
        id(9, .tabby), id(11, .tabby), id(4, .tuxedo), id(9, .gray), 96, id(5, .gray),
        id(2, .gray), id(6, .calico), id(8, .gray), 104,
    ]

    /// The card on top of the deck in `howTo()`.
    public static let howToDraw: CardID = id(9, .calico)

    /// What the other seats discard after my turn in `howTo()`, in seat order (Leo is skipped).
    public static let howToDiscards: [Seat: CardID] = [1: id2(12, .tuxedo), 2: id2(11, .calico), 3: id2(2, .tabby)]

    /// The tile game's last turn (`-demo tiles-last`): `tilesMid()`'s rug with three pieces left in
    /// my stash, each of which fits a row, so playing all three goes out and wins.
    public static func tilesLast() -> RoomView {
        tilesRoom(
            seats: 4, turns: 44, table: tilesMidTable,
            rack: [tile(7, .fish), tile(13, .mouse), tile(11, .feather)], others: [4, 6, 5],
            opened: [true, true, true, true])
    }
}
#endif
