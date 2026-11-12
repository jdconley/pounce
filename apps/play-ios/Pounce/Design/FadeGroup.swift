import SpriteKit

/// Fades a group of overlapping nodes as one layer. Setting `alpha` on a plain `SKNode`
/// multiplies it into every child, so each card of a fan is drawn see-through on its own and
/// the cards under it show through. Below 1, a `FadeGroup` draws its children into one
/// offscreen image first and fades that, so the group looks like a single translucent sheet.
/// At 1 it costs nothing (effects off, children drawn directly).
///
/// Dim a hand, a fan of example cards, a cat with its badges or a tile's set with this, never
/// with `alpha` on the pieces. Set `alpha` directly, not with an `SKAction` fade: SpriteKit's
/// own fades write alpha without going through the setter, so the group would not be
/// flattened. `rasterize` caches the image for groups that sit still while dimmed.
///
/// A single card resting on another isn't a group: darken it (`colorBlendFactor`) instead of
/// fading it, or the card under it shows through. SwiftUI's counterpart is `groupOpacity`.
@MainActor
class FadeGroup: SKEffectNode {
    init(rasterize: Bool = false) {
        super.init()
        shouldRasterize = rasterize
        shouldEnableEffects = false
    }

    override convenience init() { self.init(rasterize: false) }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    override var alpha: CGFloat {
        didSet {
            // Only on a change: toggling effects drops or rebuilds the offscreen image.
            let flat = Self.flattens(alpha)
            if flat != shouldEnableEffects { shouldEnableEffects = flat }
        }
    }

    /// Flattened while it is see-through but still drawn.
    nonisolated static func flattens(_ alpha: CGFloat) -> Bool { alpha > 0 && alpha < 1 }
}
