import CoreImage
import CoreImage.CIFilterBuiltins
import LinkPresentation
import SwiftUI
import UIKit

/// Presents the system share sheet for a room link while `isPresented` is true (spec §5.6).
/// The item carries `LPLinkMetadata` (title "Cat Tower", the host's cat as icon and image),
/// so the share sheet's header shows cat art. Put it in a `.background`.
struct ShareRoom: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let url: URL
    /// Asset name of the cat drawn in the share sheet header.
    let catArt: String

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard isPresented, !context.coordinator.presenting else { return }
        context.coordinator.presenting = true
        let item = RoomShareItem(url: url, image: UIImage(named: catArt))
        let sheet = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        let coordinator = context.coordinator
        let binding = $isPresented
        sheet.completionWithItemsHandler = { _, _, _, _ in
            coordinator.presenting = false
            binding.wrappedValue = false
        }
        // Present from the next run loop turn, outside the view update.
        Task { @MainActor in
            guard controller.view.window != nil else {
                coordinator.presenting = false
                binding.wrappedValue = false
                return
            }
            controller.present(sheet, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var presenting = false
    }
}

/// The shared link plus rich metadata for the share sheet header. Immutable after init, so the
/// share sheet may call it from any thread.
final class RoomShareItem: NSObject, UIActivityItemSource {
    let url: URL
    private let metadata: LPLinkMetadata

    init(url: URL, image: UIImage?) {
        self.url = url
        let metadata = LPLinkMetadata()
        metadata.title = "Cat Tower"
        metadata.originalURL = url
        metadata.url = url
        if let image {
            metadata.iconProvider = NSItemProvider(object: image)
            metadata.imageProvider = NSItemProvider(object: image)
        }
        self.metadata = metadata
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        metadata
    }
}

/// A QR code of `text` on a white rounded tile with a thick ink outline, scaled with
/// nearest-neighbor so the modules stay crisp.
struct QRTile: View {
    let text: String
    var side: CGFloat = 220

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
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5))
        .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 7)
        .task(id: text) { image = Self.render(text) }
    }

    static func render(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
