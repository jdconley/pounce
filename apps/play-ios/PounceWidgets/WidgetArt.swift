import PounceKit
import SwiftUI
import UIKit
import WidgetKit

/// The app's own art, read from the containing app's asset catalog (as `PounceNotify` does), so
/// the widgets carry no copy and PR 8's art swaps reach them. Each picture is redrawn at the size
/// it's shown (WidgetKit refuses images much larger than the widget), and in accented and vibrant
/// modes as its mono template (`MonoArt`).
enum WidgetArt {
    /// `Pounce.app`, around `Pounce.app/PlugIns/PounceWidgets.appex`; this bundle in previews.
    static let bundle: Bundle = {
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        if app.pathExtension == "app", let bundle = Bundle(url: app) { return bundle }
        return .main
    }()

    /// Pixels per point the art is redrawn at.
    static let scale: CGFloat = 2

    static func image(_ name: String, points: CGFloat) -> UIImage? {
        guard let source = UIImage(named: name, in: bundle, compatibleWith: nil) ?? UIImage(named: name) else { return nil }
        let size = source.size
        guard size.width > 0, size.height > 0 else { return nil }
        let fit = min(1, points / max(size.width, size.height))
        let pixels = CGSize(width: (size.width * fit * scale).rounded(), height: (size.height * fit * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let drawn = UIGraphicsImageRenderer(size: pixels, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: pixels))
        }
        guard let cg = drawn.cgImage else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }

    static func mono(_ name: String, points: CGFloat) -> UIImage? {
        guard let color = image(name, points: points), let cg = color.cgImage, let mono = MonoArt.template(cg) else { return nil }
        return UIImage(cgImage: mono, scale: scale, orientation: .up)
    }

    /// PNG data, for the partner list's faces.
    static func png(_ name: String, points: CGFloat) -> Data? {
        image(name, points: points)?.pngData()
    }

    static func cat(_ index: Int, _ pose: WidgetPose) -> String {
        ArtName.cat(index, CatPose(rawValue: pose.rawValue) ?? .idle)
    }
}

/// A picture from the app's art: in color on a full-color widget, else its mono template.
struct ArtImage: View {
    let name: String
    var points: CGFloat

    @Environment(\.widgetRenderingMode) private var mode

    init(_ name: String, points: CGFloat) {
        self.name = name
        self.points = points
    }

    var body: some View {
        if mode == .fullColor {
            if let ui = WidgetArt.image(name, points: points) {
                Image(uiImage: ui).resizable().scaledToFit()
            }
        } else if let ui = WidgetArt.mono(name, points: points) {
            Image(uiImage: ui).renderingMode(.template).resizable().scaledToFit()
        }
    }
}

/// The streak numeral: chunky outlined toy lettering in full color, plain and accentable otherwise.
struct Numeral: View {
    let value: Int
    let size: CGFloat

    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        if mode == .fullColor {
            OutlinedText(String(value), size: size, width: max(2, size / 10))
                .fixedSize()
        } else {
            Text(verbatim: String(value))
                .font(.system(size: size, weight: .black, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .widgetAccentable()
        }
    }
}
