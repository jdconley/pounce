import CoreGraphics

/// The mono template version of a piece of art (spec §11.1: in accented and vibrant modes the
/// cats and condo draw as mono templates). Made on the device from the same sprite, so PR 8's
/// art swaps reach it: white, with alpha from how dark (inky) each pixel is, so the chunky
/// outlines and shading survive where a plain template would be one flat silhouette.
public enum MonoArt {
    /// How much of a white pixel's alpha is taken away (white is faint, never gone).
    static let lightFade = 0.85

    public static func template(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, var px = pixels(image) else { return nil }
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3])
            guard a > 0 else { continue }
            // Unpremultiply, then Rec. 601 luma.
            let r = Double(px[i]) / a, g = Double(px[i + 1]) / a, b = Double(px[i + 2]) / a
            let luma = min(1, 0.299 * r + 0.587 * g + 0.114 * b)
            let out = UInt8(max(0, min(255, (a * (1 - lightFade * luma)).rounded())))
            px[i] = out
            px[i + 1] = out
            px[i + 2] = out
            px[i + 3] = out
        }
        return px.withUnsafeMutableBytes { raw in
            context(raw.baseAddress, width: width, height: height)?.makeImage()
        }
    }

    /// The image as premultiplied RGBA8, row by row.
    static func pixels(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var px = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = context(raw.baseAddress, width: width, height: height) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? px : nil
    }

    private static func context(_ data: UnsafeMutableRawPointer?, width: Int, height: Int) -> CGContext? {
        CGContext(
            data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
