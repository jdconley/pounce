import PounceKit
import SwiftUI

/// The table on the TV: the shared SpriteKit scene for the room's game, drawn in the TV's
/// arrangement because its store is a screen's. The scene draws everything on the table itself:
/// every seat, the piles or board, "<Name>'s turn", the big moments and "Reconnecting".
struct TableHost: View {
    let table: TVRoom

    var body: some View {
        Group {
            switch table.scene {
            case .catTower(let scene): TableView(scene: scene)
            case .tiles(let scene): TilesTableView(scene: scene)
            case .birdwatch(let scene): BirdTableView(scene: scene)
            case .purrtrait: PurrTVTable(table: table)
            case nil: Color.clear
            }
        }
        .ignoresSafeArea()
    }
}
