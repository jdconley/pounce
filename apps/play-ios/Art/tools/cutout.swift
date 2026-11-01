#!/usr/bin/env swift
// cutout.swift — lift subjects off a generated image into transparent PNGs.
//
//   swift Art/tools/cutout.swift <in.png> <outdir> --names a,b,c [--pad 4]
//
// Uses Vision's VNGenerateForegroundInstanceMaskRequest.
//  - One name: the whole foreground (all instances together) is exported as <name>.png.
//  - N names: each detected instance is exported, in row-major order (instances sorted by
//    center y and grouped into rows of similar height, then by x), as <name>.png.
// Each PNG is trimmed to the subject plus --pad pixels (default 4) of transparent padding.
// Exits non-zero, listing what Vision found, if the instance count does not equal N.
import AppKit
import CoreImage
import Vision

struct Item {
    let index: Int
    var minX: Int, minY: Int, maxX: Int, maxY: Int  // pixel bounds, origin top-left, inclusive
    var cx: Double { Double(minX + maxX) / 2 }
    var cy: Double { Double(minY + maxY) / 2 }
    var h: Double { Double(maxY - minY + 1) }
}

func fail(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("cutout: " + msg + "\n").utf8))
    exit(code)
}

/// Pixel bounds (top-left origin) of mask values > 0.5, for 8-bit or float masks.
func bounds(of mask: CVPixelBuffer) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    CVPixelBufferLockBaseAddress(mask, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
    let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
    let bpr = CVPixelBufferGetBytesPerRow(mask)
    guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
    let fmt = CVPixelBufferGetPixelFormatType(mask)
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<h {
        let row = base + y * bpr
        for x in 0..<w {
            let on: Bool
            switch fmt {
            case kCVPixelFormatType_OneComponent8:
                on = row.load(fromByteOffset: x, as: UInt8.self) > 127
            case kCVPixelFormatType_OneComponent32Float:
                on = row.load(fromByteOffset: x * 4, as: Float.self) > 0.5
            case kCVPixelFormatType_OneComponent16Half:
                on = Float(row.load(fromByteOffset: x * 2, as: Float16.self)) > 0.5
            default:
                fail("unsupported mask pixel format \(fmt)")
            }
            if on {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    return maxX < 0 ? nil : (minX, minY, maxX, maxY)
}

/// Group items into rows (top to bottom), each row left to right.
func rowMajor(_ items: [Item]) -> [Item] {
    let byY = items.sorted { $0.cy < $1.cy }
    var rows: [[Item]] = []
    for it in byY {
        if var last = rows.last {
            let meanCy = last.map(\.cy).reduce(0, +) / Double(last.count)
            let meanH = last.map(\.h).reduce(0, +) / Double(last.count)
            // Same row when the center is within half of the smaller height of the row.
            if abs(it.cy - meanCy) <= 0.5 * min(meanH, it.h) {
                last.append(it)
                rows[rows.count - 1] = last
                continue
            }
        }
        rows.append([it])
    }
    return rows.flatMap { $0.sorted { $0.cx < $1.cx } }
}

func run() {
    var args = Array(CommandLine.arguments.dropFirst())
    func option(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        args.removeSubrange(i...(i + 1))
        return v
    }
    let namesArg = option("--names")
    let pad = Int(option("--pad") ?? "4") ?? 4
    guard args.count == 2, let namesArg, !namesArg.isEmpty else {
        fail("usage: swift cutout.swift <in.png> <outdir> --names a,b,c [--pad 4]", code: 64)
    }
    let names = namesArg.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    let inURL = URL(fileURLWithPath: args[0]), outDir = URL(fileURLWithPath: args[1])

    guard let nsImage = NSImage(contentsOf: inURL),
          let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { fail("cannot read image \(inURL.path)") }
    let width = cg.width, height = cg.height

    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    do { try handler.perform([request]) } catch { fail("Vision request failed: \(error)") }
    guard let obs = request.results?.first else { fail("Vision found no foreground in \(inURL.lastPathComponent)") }

    var items: [Item] = []
    for idx in obs.allInstances {
        do {
            let mask = try obs.generateScaledMaskForImage(forInstances: IndexSet(integer: idx), from: handler)
            guard let b = bounds(of: mask) else { continue }
            items.append(Item(index: idx, minX: b.minX, minY: b.minY, maxX: b.maxX, maxY: b.maxY))
        } catch { fail("mask for instance \(idx) failed: \(error)") }
    }

    let describe = rowMajor(items).enumerated().map { i, it in
        "  #\(i + 1): center (\(Int(it.cx)), \(Int(it.cy))) size \(it.maxX - it.minX + 1)x\(it.maxY - it.minY + 1)"
    }.joined(separator: "\n")

    // Which instance sets to export, paired with names.
    var jobs: [(name: String, instances: IndexSet, box: Item)] = []
    if names.count == 1 {
        guard !items.isEmpty else { fail("no foreground instances found") }
        let box = Item(index: 0,
                       minX: items.map(\.minX).min()!, minY: items.map(\.minY).min()!,
                       maxX: items.map(\.maxX).max()!, maxY: items.map(\.maxY).max()!)
        jobs = [(names[0], obs.allInstances, box)]
    } else {
        guard items.count == names.count else {
            fail("Vision found \(items.count) foreground instance(s) in \(inURL.lastPathComponent) but --names lists "
                 + "\(names.count) (\(names.joined(separator: ","))). Nothing was written.\n"
                 + "Detected, in row-major order:\n\(describe.isEmpty ? "  (none)" : describe)\n"
                 + "Fix: pass --names with \(items.count) names, or regenerate the image with clearer separation "
                 + "between items (touching or overlapping items merge into one instance).")
        }
        for (name, it) in zip(names, rowMajor(items)) { jobs.append((name, IndexSet(integer: it.index), it)) }
    }

    do { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }
    catch { fail("cannot create \(outDir.path): \(error)") }

    let ci = CIContext(options: [.useSoftwareRenderer: false])
    for job in jobs {
        let masked: CVPixelBuffer
        do {
            masked = try obs.generateMaskedImage(ofInstances: job.instances, from: handler, croppedToInstancesExtent: false)
        } catch { fail("masked image for \(job.name) failed: \(error)") }
        let full = CIImage(cvPixelBuffer: masked)
        guard let fullCG = ci.createCGImage(full, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            fail("cannot render \(job.name)")
        }
        let x0 = max(0, job.box.minX - pad), y0 = max(0, job.box.minY - pad)
        let x1 = min(width, job.box.maxX + 1 + pad), y1 = min(height, job.box.maxY + 1 + pad)
        // Draw into a transparent canvas the size of the padded box (keeps padding even at image edges).
        let cw = job.box.maxX - job.box.minX + 1 + 2 * pad, chh = job.box.maxY - job.box.minY + 1 + 2 * pad
        guard let ctx = CGContext(data: nil, width: cw, height: chh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { fail("cannot create canvas for \(job.name)") }
        ctx.clear(CGRect(x: 0, y: 0, width: cw, height: chh))
        // CG images are drawn bottom-left origin; cropping uses top-left pixel coords.
        guard let crop = fullCG.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else {
            fail("crop failed for \(job.name)")
        }
        let dx = (job.box.minX - pad >= 0) ? 0 : -(job.box.minX - pad)
        let dyTop = (job.box.minY - pad >= 0) ? 0 : -(job.box.minY - pad)
        ctx.draw(crop, in: CGRect(x: dx, y: chh - dyTop - (y1 - y0), width: x1 - x0, height: y1 - y0))
        guard let outCG = ctx.makeImage() else { fail("cannot finalize \(job.name)") }
        let rep = NSBitmapImageRep(cgImage: outCG)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("PNG encode failed for \(job.name)") }
        let outURL = outDir.appendingPathComponent("\(job.name).png")
        do { try png.write(to: outURL) } catch { fail("cannot write \(outURL.path): \(error)") }
        print("wrote \(outURL.path) (\(cw)x\(chh))")
    }
}

run()
