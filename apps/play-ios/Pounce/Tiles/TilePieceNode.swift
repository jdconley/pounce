import PounceKit
import SpriteKit
import UIKit

/// One toy token on the table: a single sprite (`TilePieceFactory`), with a paw dot when it was
/// placed this turn and a ring when it is picked up or newly arrived.
@MainActor
final class TilePieceNode: SKSpriteNode {
    let tile: TileID
    private(set) var faceSize: TilePieceFactory.Size
    private(set) var standing: TileStanding?
    private let dot = SKSpriteNode(texture: TilePieceFactory.shared.badge(.placed))
    private let ring = SKSpriteNode(texture: TilePieceFactory.shared.plate(.target))
    private var ringColor: UIColor?
    /// Lifted pieces (picked up, or selected in the stash) draw larger, above the rest.
    private(set) var lifted = false
    /// Where the layout last put it (its parent's space), for snapping back.
    var home = CGPoint.zero
    /// The stash's pieces are this phone's alone: never drawn for a seat that isn't shown.
    var isPrivate = false

    init(tile: TileID, size: CGSize, face: TilePieceFactory.Size, standing: TileStanding? = nil) {
        self.tile = tile
        faceSize = face
        self.standing = standing
        let texture = TilePieceFactory.shared.face(tile, size: face, standing: standing)
        super.init(texture: texture, color: .clear, size: size)
        pieceSize = size
        dot.zPosition = 2
        dot.isHidden = true
        addChild(dot)
        ring.centerRect = TilePieceFactory.plateCenter
        ring.zPosition = -1
        ring.isHidden = true
        addChild(ring)
        layoutParts()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Draws the piece at `size` with the face for it (`large` in the stash and the loupe,
    /// `small` on the rug) and, for a Yarn in a set, the ghost of what it stands for.
    func show(size: CGSize, face: TilePieceFactory.Size, standing: TileStanding?) {
        if face != faceSize || standing != self.standing {
            faceSize = face
            self.standing = standing
            texture = TilePieceFactory.shared.face(tile, size: face, standing: standing)
        }
        if pieceSize != size {
            // Sized at scale 1: a sprite's size and its scale are not independent.
            let scale = xScale
            setScale(1)
            self.size = size
            setScale(scale)
            pieceSize = size
            layoutParts()
        }
    }

    /// The size the piece is drawn at when it isn't lifted.
    private(set) var pieceSize = CGSize.zero

    private func layoutParts() {
        let size = pieceSize
        let side = max(size.width * 0.36, 11)
        dot.setScale(1)
        dot.size = CGSize(width: side, height: side)
        dot.position = CGPoint(x: size.width / 2 - side * 0.32, y: size.height / 2 - side * 0.32)
        // The ring keeps its texture size and stretches by scale, as `centerRect` wants.
        let pad: CGFloat = 4
        ring.xScale = (size.width + 2 * pad) / 36
        ring.yScale = (size.height + 2 * pad) / 36
    }

    /// The paw dot: this piece came from the stash this turn and may go back.
    func setPlaced(_ placed: Bool) {
        dot.isHidden = !placed
    }

    /// A ring around the piece in `color` (a seat's colour for what it just placed, white for a
    /// piece picked up); nil takes it away.
    func setRing(_ color: UIColor?) {
        guard color != ringColor else { return }
        ringColor = color
        ring.isHidden = color == nil
        if let color { ring.texture = TilePieceFactory.shared.plate(.recap, tint: color) }
    }

    func setLifted(_ on: Bool) {
        lifted = on
    }
}

/// A set's bed and badge on the rug (tile game spec §5.5): plain at rest, a solid lime glow and
/// a check paw when it was changed this turn and is fine, a dashed outline that breathes with
/// one glyph for why when it isn't a set yet, a thin ring while the rug is locked.
@MainActor
final class TileSetNode: SKNode {
    enum Look: Equatable {
        case plain, locked, changed, target, refused
        case broken(TilesDraft.Problem)
    }

    private let plate = SKSpriteNode()
    private let dashes = SKSpriteNode()
    private let badge = SKSpriteNode()
    private(set) var look: Look?
    private(set) var boxSize = CGSize.zero

    override init() {
        super.init()
        plate.centerRect = TilePieceFactory.plateCenter
        plate.zPosition = 0
        dashes.zPosition = 1
        dashes.isHidden = true
        badge.zPosition = 30
        badge.isHidden = true
        [plate, dashes, badge].forEach(addChild)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// True while the dashed outline is breathing (the scene keeps the view awake for it).
    var breathes: Bool { !dashes.isHidden && dashes.action(forKey: "breathe") != nil }

    func show(_ look: Look, size: CGSize, reduceMotion: Bool) {
        guard look != self.look || size != boxSize else { return }
        self.look = look
        boxSize = size
        let factory = TilePieceFactory.shared
        dashes.removeAction(forKey: "breathe")
        dashes.alpha = 1
        var mark: TilePieceFactory.Badge?
        switch look {
        case .plain:
            plate.texture = factory.plate(.plain)
            dashes.isHidden = true
        case .locked:
            plate.texture = factory.plate(.locked)
            dashes.isHidden = true
        case .changed:
            plate.texture = factory.plate(.changed)
            dashes.isHidden = true
            mark = .check
        case .target:
            plate.texture = factory.plate(.target)
            dashes.isHidden = true
        case .refused:
            plate.texture = factory.plate(.target, tint: UIColor(Palette.refuse))
            dashes.isHidden = true
        case .broken(let problem):
            plate.texture = factory.plate(.plain)
            dashes.texture = factory.dashed(size, color: UIColor(Palette.orange))
            dashes.size = size
            dashes.isHidden = false
            mark = .problem(problem)
            if !reduceMotion {
                dashes.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.45, duration: 0.7).eased(.easeInEaseOut), .fadeAlpha(to: 1, duration: 0.7).eased(.easeInEaseOut),
                ])), withKey: "breathe")
            }
        }
        // The plate keeps its texture size and stretches by scale, as `centerRect` wants.
        plate.setScale(1)
        plate.size = CGSize(width: 36, height: 36)
        plate.xScale = size.width / 36
        plate.yScale = size.height / 36
        if let mark {
            let side = min(max(size.height * 0.5, 18), 26)
            badge.texture = factory.badge(mark)
            badge.size = CGSize(width: side, height: side)
            badge.position = CGPoint(x: size.width / 2 - side * 0.2, y: size.height / 2 - side * 0.1)
            badge.isHidden = false
        } else {
            badge.isHidden = true
        }
    }
}

/// The bar across the top for the tile game: every other seat's cat in turn order, with its
/// pieces left on a token back, a closed toy box until it has opened, Zzz once it has passed,
/// and its name under it. The seat to move wears the glow and the paw.
@MainActor
final class TilesOpponentsNode: SKNode {
    private var cats: [Seat: CatNode] = [:]
    private var tags: [Seat: SKSpriteNode] = [:]
    private var tagText: [Seat: String] = [:]
    private var boxes: [Seat: SKSpriteNode] = [:]
    private var naps: [Seat: SKSpriteNode] = [:]
    private(set) var order: [Seat] = []

    func node(for seat: Seat) -> CatNode? { cats[seat] }

    /// Seats whose ring just became the current player's.
    @discardableResult
    func update(model: TilesTableModel, seats: [Seat], layout: TilesLayout) -> [Seat] {
        var turnedOn: [Seat] = []
        let slots = layout.opponentSlots
        let diameter = layout.catDiameter
        let names = SeatInfo.names(model.room)
        let textScale = TableText.scale
        let spacing = slots.count > 1 ? abs(slots[1].x - slots[0].x) : layout.size.width
        let tagWidth = min(spacing - 2, (layout.arrangement == .phone ? 140 : 170) * textScale)
        let nameSize = TableTextScale.nameSize(scale: textScale)
        let chipScale = TableTextScale.chips(scale: textScale, spacing: spacing, diameter: diameter)

        for (seat, node) in cats where !seats.contains(seat) || node.diameter != diameter || node.textScale != chipScale
            || node.cat != SeatInfo.catIndex(model.room.seats[safe: seat]) {
            node.removeFromParent()
            cats[seat] = nil
        }
        for seat in Array(tags.keys) where !seats.contains(seat) {
            tags[seat]?.removeFromParent()
            tags[seat] = nil
            tagText[seat] = nil
        }
        for seat in Array(boxes.keys) where !seats.contains(seat) {
            boxes[seat]?.removeFromParent()
            boxes[seat] = nil
            naps[seat]?.removeFromParent()
            naps[seat] = nil
        }
        for (i, seat) in seats.enumerated() where i < slots.count {
            let view = model.room.seats[safe: seat]
            let marks = model.marks(seat)
            let node: CatNode
            if let existing = cats[seat] {
                node = existing
            } else {
                node = CatNode(cat: SeatInfo.catIndex(view), ringColor: SeatInfo.ringColor(seat), diameter: diameter, textScale: chipScale)
                cats[seat] = node
                addChild(node)
            }
            node.position = CGPoint(x: slots[i].x, y: slots[i].y + layout.catLift)
            node.zPosition = CGFloat(i)
            node.setPresence(view?.kind == .bot ? nil : view?.presence)
            node.alpha = marks.forfeited ? 0.45 : 1
            node.setLink(marks.forfeited ? nil : (view?.kind == .human ? LinkWords.seat(view?.link)?.level : nil))
            node.setBadges(bot: marks.bot, skip: false)
            node.slotWidth = spacing
            node.setCount(marks.forfeited ? nil : marks.count)
            if node.setActive(marks.onTheMove) { turnedOn.append(seat) }

            // Not opened yet: a closed toy box at the ring's lower left. Passed: Zzz at its upper left.
            let r = diameter / 2
            let box = boxes[seat] ?? {
                let n = SKSpriteNode(texture: TableArt.image(ArtName.Tiles.toyBoxClosed))
                n.zPosition = 40
                boxes[seat] = n
                addChild(n)
                return n
            }()
            let boxSide = max(diameter * 0.42, 24)
            box.size = CGSize(width: boxSide, height: boxSide)
            box.position = CGPoint(x: node.position.x - r * 0.72, y: node.position.y - r * 0.62)
            box.isHidden = !marks.notOpened
            let nap = naps[seat] ?? {
                let n = SKSpriteNode(texture: TableArt.image(ArtName.iconZzz))
                n.zPosition = 41
                naps[seat] = n
                addChild(n)
                return n
            }()
            let napSide = max(diameter * 0.4, 22)
            nap.size = CGSize(width: napSide, height: napSide)
            nap.position = CGPoint(x: node.position.x - r * 0.72, y: node.position.y + r * 0.72)
            nap.isHidden = !marks.passed

            let tag = tags[seat] ?? {
                let t = SKSpriteNode()
                tags[seat] = t
                addChild(t)
                return t
            }()
            let name = marks.forfeited
                ? String(localized: "Forfeited", comment: "Under a player's name: they left the game")
                : (names[safe: seat] ?? "")
            let key = "\(name)|\(tagWidth)|\(nameSize)"
            if tagText[seat] != key || tag.texture == nil {
                tagText[seat] = key
                let texture = CardFaceFactory.shared.nameTag(name, maxWidth: tagWidth, active: false, size: nameSize)
                tag.texture = texture
                tag.size = texture.size()
            }
            tag.position = CGPoint(x: slots[i].x, y: slots[i].y - layout.nameDrop)
            tag.zPosition = 20 + CGFloat(i)
        }
        order = Array(seats.prefix(slots.count))
        return turnedOn
    }

    func clear() {
        removeAllChildren()
        cats.removeAll()
        tags.removeAll()
        tagText.removeAll()
        boxes.removeAll()
        naps.removeAll()
        order = []
    }

    /// Touch / accessibility frame of a seat's cat, in this node's parent space.
    func frame(of seat: Seat) -> CGRect? {
        guard let node = cats[seat] else { return nil }
        let d = max(node.diameter, TilesLayout.buttonHit)
        return CGRect(x: node.position.x - d / 2, y: node.position.y - d / 2, width: d, height: d)
    }
}
