import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code of `text` on a white rounded tile with a thick ink outline, scaled with
/// nearest-neighbor so the modules stay crisp. The iPhone's invites and the Apple TV's links
/// both draw it; the code is made off the main thread and kept (`QRImages`).
struct QRTile: View {
    let text: String
    var side: CGFloat = 220
    /// The tile's padding, corner and outline, as the iPhone draws them; the TV passes bigger ones.
    var padding: CGFloat = 18
    var corner: CGFloat = 28
    var outline: CGFloat = 5

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.white
            }
        }
        .frame(width: side, height: side)
        .padding(padding)
        .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Palette.ink, lineWidth: outline))
        // One layer, so the drop falls under the tile only, not under the code inside it too.
        .compositingGroup()
        .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: outline * 1.4)
        .task(id: text) { image = await QRImages.shared.image(for: text) }
    }
}

/// QR codes, made off the main thread and kept: a TV's link and a table's invite are drawn again
/// whenever their screen comes back, and the same text always makes the same code.
actor QRImages {
    static let shared = QRImages()

    /// The most codes kept; the oldest goes first.
    private static let limit = 16
    private var kept: [String: CGImage] = [:]
    private var order: [String] = []

    func image(for text: String) async -> CGImage? {
        if let image = kept[text] { return image }
        guard let image = await Self.render(text) else { return nil }
        kept[text] = image
        order.removeAll { $0 == text }
        order.append(text)
        if order.count > Self.limit { kept[order.removeFirst()] = nil }
        return image
    }

    /// Off the main thread: a Core Image context is slow to make and the render is real work.
    @concurrent
    static func render(_ text: String) async -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
