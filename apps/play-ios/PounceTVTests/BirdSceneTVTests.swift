import PounceKit
import SpriteKit
import SwiftUI
import Testing
@testable import PounceTV

/// Birdwatch on the TV: the iPhone's scene in the TV's arrangement. It never draws a hand, a
/// choice or the five-player partner mark, even fed a room that holds them (defence in depth: a
/// screen's view never has them), and it shows the partner only once the called card is played.
@MainActor
@Suite("Birdwatch on the TV")
struct BirdSceneTVTests {
    private static func screenStore() -> RoomStore {
        let store = RoomStore(code: DemoFixtures.code, socket: QuietSocket(), role: .screen)
        store.handle(.connected)
        return store
    }

    private static func scene(_ room: RoomView) -> (BirdScene, RoomStore) {
        let store = screenStore()
        let scene = BirdScene(store: store)
        scene.size = CGSize(width: 1920, height: 1080)
        scene.safeInsets = UIEdgeInsets(top: 60, left: 80, bottom: 60, right: 80)
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        scene.reconcileFromStore()
        return (scene, store)
    }

    @Test func noHandOnScreen() async {
        // The faces are drawn off the main thread first, as the TV's table does before it opens.
        await BirdCardFactory.shared.prewarm()
        // The room says seat 0 is this device's and holds its hand and its move: the TV draws none of it.
        var room = DemoFixtures.birdRoom(.play)
        // Nobody's banner: the TV's shared banner art is another suite's to time.
        room.birdwatch?.turn = nil
        #expect(room.seats[0].yours && !(room.birdwatch?.hands[0] ?? []).isEmpty)
        let (scene, _) = Self.scene(room)
        #expect(scene.isScreen)
        #expect(scene.layout?.mode == .tv)
        #expect(scene.shownSeat == nil)
        #expect(scene.handNodes.isEmpty)
        #expect(scene.handShown.isEmpty)
        // Every seat sits around the window, the trick on the sill.
        #expect(Set(scene.seatNodes.keys) == Set(0..<4))
        #expect(scene.trickNodes.count == 3)
    }

    @Test func noPartnerBeforeCalledCardPlayed() async {
        await BirdCardFactory.shared.prewarm()
        // Seat 0 holds the called card and the room even says so: the TV shows no mark.
        var marked = DemoFixtures.birdRoom(.partnerMark)
        marked.birdwatch?.turn = nil
        let (hidden, _) = Self.scene(marked)
        for node in hidden.seatNodes.values {
            #expect(BirdSceneTVTests.heartShown(node) == false)
        }
        #expect(BirdTableModel(room: DemoFixtures.birdRoom(.partnerMark))?.ribbon(of: 0) == nil)
        // Once the called card is played the table knows: the bid winner and partner share a ribbon.
        var room = DemoFixtures.birdRoom(.partnerMark)
        room.birdwatch?.partner = 0
        let model = BirdTableModel(room: room)
        #expect(model?.ribbon(of: 0) == .gold)
        #expect(model?.ribbon(of: 1) == .gold)
    }

    /// The partner heart is the seat's only gold-heart sprite; it shows only when not hidden.
    static func heartShown(_ node: BirdSeatNode) -> Bool {
        node.children.contains { ($0 as? SKSpriteNode)?.texture == BirdArt.partnerHeart() && !$0.isHidden }
    }

    @Test func theTVLayoutClearsEveryCat() {
        for n in 4...6 {
            let layout = BirdLayout(size: CGSize(width: 1920, height: 1080), safeTop: 60, safeBottom: 60, others: n, handCount: 0, mode: .tv)
            for spot in layout.seatSpots {
                let cat = CGRect(x: spot.x - layout.catSide / 2, y: spot.y - layout.catSide * 0.82, width: layout.catSide, height: layout.catSide * 1.32)
                #expect(!cat.intersects(layout.sill), "\(n) seats")
            }
        }
    }
}
