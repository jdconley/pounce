import CoreGraphics
import Testing
@testable import PounceTV

/// Home's shelf of posters fits the TV at any count (four in a Release 1.3 build, five with Toy
/// Tumble or Tonight's board, six and more later): the shelf spans the safe area's 1760 points,
/// every poster is wholly on screen with room for the focus grow, and four look as they always did.
/// A tvOS layout is 1920 by 1080 points on a 1080p and a 4K TV alike (4K is 2x pixels).
@Suite struct TVShelfTests {
    static let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    static let safe = screen.insetBy(dx: 80, dy: 60)
    /// `TVButtonStyle`'s focus grow.
    static let grow: CGFloat = 1.05

    @Test func fourPostersAreFullSize() {
        #expect(TVShelf.scale(4) == 1)
        #expect(TVShelf.shelfWidth(4) == 1760)
        #expect(TVShelf.scale(3) == 1)
    }

    @Test(arguments: [4, 5, 6, 7]) func everyPosterFitsWithItsFocusGrow(_ count: Int) {
        let k = TVShelf.scale(count)
        let width = TVShelf.shelfWidth(count)
        #expect(width <= TVShelf.span + 0.5, "\(count) posters are \(width) wide")
        // Centred, as the home's VStack lays it out.
        let x0 = Self.screen.midX - width / 2
        for i in 0..<count {
            let poster = CGRect(x: x0 + CGFloat(i) * (TVShelf.width + TVShelf.gap) * k, y: 0, width: TVShelf.width * k, height: 1)
            let focused = poster.insetBy(dx: -poster.width * (Self.grow - 1) / 2, dy: 0)
            #expect(focused.minX >= Self.screen.minX + 60 && focused.maxX <= Self.screen.maxX - 60, "\(count): poster \(i) at \(focused)")
            #expect(poster.minX >= Self.safe.minX - 0.5 && poster.maxX <= Self.safe.maxX + 0.5, "\(count): poster \(i) leaves the safe area")
        }
    }

    /// The whole poster scales together; at six the name is still big from the sofa.
    @Test func sixStillReadFromTheSofa() {
        let k = TVShelf.scale(6)
        #expect(k < 1 && k > 0.6)
        #expect(58 * k >= 36, "the name's size at six posters")
        #expect(30 * k >= 19, "the pill's size at six posters")
    }
}
