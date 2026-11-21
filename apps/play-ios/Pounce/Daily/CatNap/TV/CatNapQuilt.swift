import PounceKit
import SwiftUI

/// Where a quilt's cells sit in a square of side `side`.
struct CatNapGeometry: Equatable {
    let n: Int
    let side: CGFloat

    var unit: CGFloat { side / CGFloat(n) }

    func rect(_ cell: Int) -> CGRect {
        CGRect(x: CGFloat(cell % n) * unit, y: CGFloat(cell / n) * unit, width: unit, height: unit)
    }

    /// The cell under `point`, or nil off the quilt.
    func cell(at point: CGPoint) -> Int? {
        guard point.x >= 0, point.y >= 0, point.x < side, point.y < side else { return nil }
        return min(n - 1, Int(point.y / unit)) * n + min(n - 1, Int(point.x / unit))
    }

    /// The cells a finger crossed from `a` to `b`, in order, sampled finely so a fast swipe
    /// skips none.
    func cells(from a: CGPoint, to b: CGPoint) -> [Int] {
        let steps = max(1, Int((hypot(b.x - a.x, b.y - a.y) / (unit / 4)).rounded(.up)))
        var out: [Int] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            if let c = cell(at: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)), out.last != c { out.append(c) }
        }
        return out
    }
}

/// The quilt as drawn, read-only: the cloth, the "no cat" marks, the clashes and the sleeping
/// cats. The phone's play view puts its input on top; the TV's watch view shows it alone.
struct CatNapQuilt: View {
    let quilt: NapQuilt
    let state: NapState
    let check: NapCheck
    let side: CGFloat

    var body: some View {
        let geo = CatNapGeometry(n: quilt.n, side: side)
        ZStack(alignment: .topLeading) {
            CatNapCloth(quilt: quilt, geo: geo)
                .equatable()
            CatNapMarks(quilt: quilt, state: state, clashes: check.clashes, geo: geo)
            ForEach(state.cats, id: \.self) { cell in
                CatNapCat(
                    cat: CatNapQuilt.cat(for: quilt.patches[cell]),
                    pose: check.complete ? .celebrate : check.clashes.cells.contains(cell) ? .awake : .asleep,
                    clash: check.clashes.cells.contains(cell),
                    hinted: state.hinted.contains(cell),
                    unit: geo.unit)
                    .position(x: geo.rect(cell).midX, y: geo.rect(cell).midY)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: side, height: side)
        .overlay {
            // The quilt's binding, over the marks, so a crowded line's hatching stops at the hem.
            RoundedRectangle(cornerRadius: geo.unit / 3.5, style: .continuous)
                .stroke(check.complete ? Palette.yellow : Palette.ink, lineWidth: min(7, max(4, geo.unit / 8)))
                .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: state.cats)
        .animation(.easeOut(duration: 0.2), value: check)
    }

    /// A cat for each patch, so a quilt naps with a mix of Pounce's eight cats.
    static func cat(for patch: Int) -> Int { (patch * 3 + 1) % ArtName.catCount }
}

/// The cloth: patches, their patterns and the seams. Drawn once per quilt and size, flattened
/// into one layer (`drawingGroup`), so marking cells never redraws it.
private struct CatNapCloth: View, Equatable {
    let quilt: NapQuilt
    let geo: CatNapGeometry

    var body: some View {
        Canvas { ctx, _ in
            let n = quilt.n, u = geo.unit
            for patch in 0..<n {
                var shape = Path()
                var bounds = CGRect.null
                for cell in 0..<quilt.size where quilt.patches[cell] == patch {
                    let r = geo.rect(cell)
                    shape.addRect(r)
                    bounds = bounds.union(r)
                }
                let cloth = CatNapFabric.cloth(patch)
                ctx.fill(shape, with: .color(cloth.color))
                ctx.drawLayer { layer in
                    layer.clip(to: shape)
                    let (marks, width) = CatNapFabric.path(cloth.pattern, in: bounds, unit: u)
                    if let width {
                        layer.stroke(marks, with: .color(cloth.tint), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                    } else {
                        layer.fill(marks, with: .color(cloth.tint))
                    }
                }
            }
            // Thin lines between cells of one patch, thick seams between patches.
            var thin = Path(), seam = Path()
            for cell in 0..<quilt.size {
                let r = geo.rect(cell)
                if cell % n < n - 1 {
                    let edge = Path { $0.move(to: CGPoint(x: r.maxX, y: r.minY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
                    if quilt.patches[cell] == quilt.patches[cell + 1] { thin.addPath(edge) } else { seam.addPath(edge) }
                }
                if cell / n < n - 1 {
                    let edge = Path { $0.move(to: CGPoint(x: r.minX, y: r.maxY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
                    if quilt.patches[cell] == quilt.patches[cell + n] { thin.addPath(edge) } else { seam.addPath(edge) }
                }
            }
            ctx.stroke(thin, with: .color(Palette.ink.opacity(0.32)), lineWidth: max(1, u / 36))
            ctx.stroke(seam, with: .color(Palette.ink), style: StrokeStyle(lineWidth: max(3, u / 11), lineCap: .round))
            // Stitches just inside the hem.
            let hem = CGRect(x: 0, y: 0, width: geo.side, height: geo.side).insetBy(dx: u / 7, dy: u / 7)
            ctx.stroke(
                Path(roundedRect: hem, cornerRadius: u / 5), with: .color(.white.opacity(0.75)),
                style: StrokeStyle(lineWidth: max(1.5, u / 30), lineCap: .round, dash: [u / 9, u / 11]))
        }
        .frame(width: geo.side, height: geo.side)
        .clipShape(RoundedRectangle(cornerRadius: geo.unit / 3.5, style: .continuous))
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// "No cat" marks and the clashes: warning hatching over a crowded row, column or patch.
private struct CatNapMarks: View {
    let quilt: NapQuilt
    let state: NapState
    let clashes: NapClashes
    let geo: CatNapGeometry

    var body: some View {
        Canvas { ctx, _ in
            let u = geo.unit
            // A crowded row or column: warning hatching across it.
            var lines = Path()
            for cell in 0..<quilt.size where clashes.rows.contains(cell / quilt.n) || clashes.cols.contains(cell % quilt.n) {
                lines.addRect(geo.rect(cell))
            }
            if !lines.isEmpty {
                ctx.drawLayer { layer in
                    layer.clip(to: lines)
                    layer.fill(lines, with: .color(Palette.refuse.opacity(0.18)))
                    let (hatch, _) = CatNapFabric.path(.stripes, in: CGRect(x: 0, y: 0, width: geo.side, height: geo.side), unit: u * 1.5)
                    layer.stroke(hatch, with: .color(Palette.refuse.opacity(0.6)), lineWidth: max(1.5, u / 18))
                }
            }
            // A crowded patch: a dashed red edge around it.
            var edge = Path()
            for cell in 0..<quilt.size where clashes.patches.contains(quilt.patches[cell]) {
                let r = geo.rect(cell), p = quilt.patches[cell], n = quilt.n
                let sides: [(Bool, CGPoint, CGPoint)] = [
                    (cell / n == 0 || quilt.patches[cell - n] != p, CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)),
                    (cell / n == n - 1 || quilt.patches[cell + n] != p, CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)),
                    (cell % n == 0 || quilt.patches[cell - 1] != p, CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.maxY)),
                    (cell % n == n - 1 || quilt.patches[cell + 1] != p, CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY)),
                ]
                for (open, a, b) in sides where open {
                    edge.move(to: a)
                    edge.addLine(to: b)
                }
            }
            ctx.stroke(edge, with: .color(Palette.refuse), style: StrokeStyle(lineWidth: max(3, u / 9), lineCap: .round, dash: [u / 6, u / 9]))
            var x = Path()
            for cell in 0..<quilt.size where state.cells[cell] == NapState.noCat {
                let r = geo.rect(cell).insetBy(dx: u * 0.36, dy: u * 0.36)
                x.move(to: CGPoint(x: r.minX, y: r.minY))
                x.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                x.move(to: CGPoint(x: r.maxX, y: r.minY))
                x.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            }
            let w = max(2.5, u / 12)
            ctx.stroke(x, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: w + max(2, u / 22), lineCap: .round))
            ctx.stroke(x, with: .color(Palette.ink), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }
        .frame(width: geo.side, height: geo.side)
        .clipShape(RoundedRectangle(cornerRadius: geo.unit / 3.5, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One sleeping cat on the quilt. It wakes up, ringed, when it breaks a rule; a hint's cat wears
/// a padlock, since it can't be moved.
struct CatNapCat: View {
    let cat: Int
    let pose: CatPose
    let clash: Bool
    let hinted: Bool
    let unit: CGFloat

    var body: some View {
        ZStack {
            if clash {
                Circle()
                    .stroke(Palette.refuse, style: StrokeStyle(lineWidth: max(2.5, unit / 12), dash: [unit / 8, unit / 14]))
                    .background(Circle().fill(Color.white.opacity(0.55)))
                    .frame(width: unit * 0.92, height: unit * 0.92)
            }
            Image(ArtName.cat(cat, pose))
                .resizable()
                .scaledToFit()
                .frame(width: unit * 0.86, height: unit * 0.86)
                .shadow(color: Palette.ink.opacity(0.35), radius: 0, x: 0, y: unit / 30)
            if hinted {
                Image(ArtName.Habit.iconPadlock)
                    .resizable()
                    .scaledToFit()
                    .frame(width: unit * 0.3, height: unit * 0.3)
                    .offset(x: unit * 0.3, y: unit * 0.3)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The quilt's cats so far, as beds along the top: a cat for each one placed with no rule
/// broken, an empty bed for each still to find. Progress that gives nothing away.
struct CatNapBeds: View {
    let n: Int
    let placed: Int
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.18) {
            ForEach(0..<n, id: \.self) { i in
                ZStack {
                    Capsule()
                        .fill(Palette.ink.opacity(0.35))
                        .overlay(Capsule().stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                        .frame(width: size, height: size * 0.5)
                        .offset(y: size * 0.22)
                    if i < placed {
                        Image(ArtName.cat(CatNapQuilt.cat(for: i), .asleep))
                            .resizable()
                            .scaledToFit()
                            .frame(width: size, height: size)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: placed)
        .compositingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(placed) of \(n) cats")
        .accessibilityIdentifier("catnap.beds")
    }
}
