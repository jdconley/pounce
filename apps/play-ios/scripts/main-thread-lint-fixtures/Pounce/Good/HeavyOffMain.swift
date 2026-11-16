// expect: none
import CoreImage
import PounceKit
enum QR {
    @concurrent
    static func render() async -> CGImage? {
        let context = CIContext()
        return context.createCGImage(CIImage.empty(), from: .zero)
    }

    @concurrent
    static func hint(_ draft: TilesDraft) async -> TilesHints.Hint? { TilesHints.next(draft) }
}
