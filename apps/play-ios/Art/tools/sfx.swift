#!/usr/bin/env swift
// sfx.swift — synthesizes Pounce's sound effects (no samples, no licensing).
//
//   swift Art/tools/sfx.swift <outdir>      # writes sfx-*.caf (44.1 kHz mono, <= 0.6 s)
//
// Deterministic: the noise source is a fixed-seed generator, so re-running produces
// identical files.
import AVFoundation

let sampleRate = 44_100.0
let maxDuration = 0.6

struct Rng {  // xorshift64*, fixed seed
    var s: UInt64 = 0x9E37_79B9_7F4A_7C15
    mutating func next() -> Double {
        s ^= s >> 12; s ^= s << 25; s ^= s >> 27
        let v = s &* 2_685_821_657_736_338_717
        return Double(v >> 11) / Double(1 << 53) * 2 - 1
    }
}

/// Build `seconds` of samples from f(t, i); applies a 3 ms attack ramp and limits the peak to 0.85.
func make(_ seconds: Double, _ f: (Double, Int) -> Double) -> [Float] {
    precondition(seconds <= maxDuration, "sfx must be <= \(maxDuration)s")
    let n = Int(seconds * sampleRate)
    var out: [Float] = (0..<n).map { i in
        let t = Double(i) / sampleRate
        let attack = min(1, t / 0.003)
        return Float(f(t, i) * attack)
    }
    // Keep headroom: anything hotter than 0.85 is scaled down (quiet sounds stay quiet).
    let peak = out.map { abs($0) }.max() ?? 0
    if peak > 0.85 { out = out.map { $0 * 0.85 / peak } }
    return out
}

func sine(_ phase: Double) -> Double { sin(2 * .pi * phase) }
func square(_ phase: Double) -> Double { (phase - floor(phase)) < 0.5 ? 1 : -1 }
func env(_ t: Double, decay: Double) -> Double { exp(-t * decay) }

/// Integrates a time-varying frequency into phase so glides stay click-free.
struct Osc {
    var phase = 0.0
    mutating func step(_ freq: Double) -> Double {
        phase += freq / sampleRate
        return phase
    }
}

var sounds: [(String, [Float])] = []

// pop: pitched sine blip with fast decay.
sounds.append(("sfx-pop", { var o = Osc(); return make(0.14) { t, _ in
    sine(o.step(900 - 500 * t / 0.14)) * 0.8 * env(t, decay: 28) } }()))

// flip: filtered noise swish (one-pole low-pass whose cutoff opens, then closes).
sounds.append(("sfx-flip", { var r = Rng(); var lp = 0.0; return make(0.16) { t, _ in
    let shape = sin(.pi * min(1, t / 0.16))
    let a = 0.08 + 0.45 * shape
    lp += a * (r.next() - lp)
    return lp * 2.2 * shape } }()))

// bat: short noise burst + low thump.
sounds.append(("sfx-bat", { var r = Rng(); var o = Osc(); var lp = 0.0; return make(0.22) { t, _ in
    lp += 0.35 * (r.next() - lp)
    let click = lp * 1.6 * env(t, decay: 70)
    let thump = sine(o.step(150 - 90 * min(1, t / 0.2))) * 0.9 * env(t, decay: 16)
    return click + thump } }()))

// thud: low sine drop.
sounds.append(("sfx-thud", { var o = Osc(); return make(0.3) { t, _ in
    sine(o.step(120 - 70 * min(1, t / 0.3))) * 1.0 * env(t, decay: 11) } }()))

// nope: two descending square blips.
sounds.append(("sfx-nope", { var o = Osc(); return make(0.3) { t, _ in
    let second = t >= 0.15
    let lt = second ? t - 0.15 : t
    let f = second ? 220.0 : 330.0
    return square(o.step(f)) * 0.35 * env(lt, decay: 14) * (lt < 0.12 ? 1 : 0) } }()))

// sparkle: rising sine arpeggio (pentatonic, high).
sounds.append(("sfx-sparkle", { var o = Osc(); let notes = [880.0, 1175, 1480, 1760, 2349]
    return make(0.45) { t, _ in
        let step = 0.07
        let k = min(notes.count - 1, Int(t / step))
        let lt = t - Double(k) * step
        return sine(o.step(notes[k])) * 0.5 * env(lt, decay: 9) * (t < step * Double(notes.count) + 0.2 ? 1 : 0) } }()))

// whoosh: noise sweep (band moves up while the level swells and fades).
sounds.append(("sfx-whoosh", { var r = Rng(); var lp = 0.0; return make(0.4) { t, _ in
    let p = t / 0.4
    let a = 0.03 + 0.5 * p * p
    lp += a * (r.next() - lp)
    return lp * 2.4 * sin(.pi * p) } }()))

// scream: fast vibrato sine glide, rising then wobbling (cat panic).
sounds.append(("sfx-scream", { var o = Osc(); return make(0.5) { t, _ in
    let base = 700 + 900 * min(1, t / 0.15)
    let vib = 1 + 0.06 * sin(2 * .pi * 28 * t)
    let body = sine(o.step(base * vib))
    return body * 0.55 * min(1, (0.5 - t) / 0.12) * 1.0 } }()))

// leap: rising slide.
sounds.append(("sfx-leap", { var o = Osc(); return make(0.25) { t, _ in
    sine(o.step(300 + 900 * (t / 0.25) * (t / 0.25))) * 0.7 * min(1, (0.25 - t) / 0.06) } }()))

// fanfare: 4-note major arpeggio (C5 E5 G5 C6), last note held.
sounds.append(("sfx-fanfare", { var o = Osc(); let notes = [523.25, 659.25, 783.99, 1046.5]
    return make(0.6) { t, _ in
        let k = min(3, Int(t / 0.1))
        let lt = t - Double(k) * 0.1
        let e = k == 3 ? env(lt, decay: 4.5) : env(lt, decay: 9)
        let ph = o.step(notes[k])
        return (sine(ph) * 0.5 + sine(ph * 2) * 0.12) * e * min(1, (0.6 - t) / 0.05) } }()))

// tick: 5 ms click.
sounds.append(("sfx-tick", { var o = Osc(); return make(0.005) { t, _ in
    sine(o.step(2200)) * 0.8 * (1 - t / 0.005) } }()))

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift sfx.swift <outdir>\n".utf8))
    exit(64)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
for (name, samples) in sounds {
    let url = outDir.appendingPathComponent("\(name).caf")
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(forWriting: url, settings: format.settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count))!
    buf.frameLength = AVAudioFrameCount(samples.count)
    for (i, s) in samples.enumerated() { buf.floatChannelData![0][i] = s }
    try file.write(from: buf)
    print("wrote \(name).caf  \(String(format: "%.3f", Double(samples.count) / sampleRate)) s")
}
