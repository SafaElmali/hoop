import Foundation

/// An original lo-fi loop for the gameplay video: electric-piano chords, bass, swung drums and a
/// little vinyl crackle. Fully synthesised and seeded, so every render sounds the same.
enum Music {
    static let rate = 44_100.0
    private static let bpm = 92.0

    static func render(duration: TimeInterval) -> (left: [Float], right: [Float]) {
        let beat = 60 / bpm, bar = beat * 4
        let frames = Int(duration * rate)
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        var random = Seeded(seed: 7)

        func add(_ samples: [Float], at time: Double, gain: Float, pan: Float = 0) {
            let start = Int(time * rate)
            let leftGain = gain * min(1, 1 - pan), rightGain = gain * min(1, 1 + pan)
            for index in samples.indices where start + index >= 0 && start + index < frames {
                left[start + index] += samples[index] * leftGain
                right[start + index] += samples[index] * rightGain
            }
        }

        // Fmaj9 – Em7 – Dm9 – Cmaj7, one bar each.
        let chords = [[53, 57, 60, 64, 67], [52, 55, 59, 62], [50, 53, 57, 60, 64], [48, 52, 55, 59]]
        let roots = [41, 40, 38, 36]
        let kick = Self.kick(), snare = Self.snare(), hat = Self.hat(open: false), openHat = Self.hat(open: true)
        var keys: [Int: [Float]] = [:], stabs: [Int: [Float]] = [:], basses: [Int: [Float]] = [:]

        for barIndex in 0..<Int((duration / bar).rounded(.up)) {
            let start = Double(barIndex) * bar
            let chord = chords[barIndex % 4], root = roots[barIndex % 4]
            for (voice, note) in chord.enumerated() {
                let strum = Double(voice) * 0.012
                if keys[note] == nil { keys[note] = epiano(note, length: bar * 0.95, decay: 1.4) }
                if stabs[note] == nil { stabs[note] = epiano(note, length: beat * 1.2, decay: 0.35) }
                add(keys[note]!, at: start + strum, gain: 0.075, pan: -0.25)
                add(stabs[note]!, at: start + beat * 2.5 + strum, gain: 0.04, pan: 0.25)
            }
            guard barIndex >= 1 else { continue }
            if basses[root] == nil { basses[root] = bass(root, length: beat * 1.6) }
            add(basses[root]!, at: start, gain: 0.32)
            add(basses[root]!, at: start + beat * 2.5, gain: 0.22)
            guard barIndex >= 2 else { continue }
            add(kick, at: start, gain: 0.6)
            add(kick, at: start + beat * 1.75, gain: 0.35)
            add(kick, at: start + beat * 2.5, gain: 0.5)
            for backbeat in [1.0, 3.0] { add(snare, at: start + beat * backbeat + 0.015, gain: 0.32) }
            for eighth in 0..<8 {
                let swing = eighth % 2 == 1 ? beat * 0.1 : 0
                let time = start + Double(eighth) * beat / 2 + swing
                let isOpen = eighth == 7 && barIndex % 2 == 1
                add(isOpen ? openHat : hat, at: time, gain: Float.random(in: 0.08...0.13, using: &random), pan: 0.35)
            }
        }

        // Vinyl: a soft hiss and the odd crackle.
        var hiss: Float = 0
        for index in 0..<frames {
            hiss += 0.02 * (Float.random(in: -1...1, using: &random) - hiss)
            var sample = hiss * 0.02
            if Float.random(in: 0...1, using: &random) < 0.00008 { sample += Float.random(in: -0.12...0.12, using: &random) }
            left[index] += sample
            right[index] += sample
        }

        // Fade in and out, then soft-clip and level.
        for index in 0..<frames {
            let time = Double(index) / rate
            let fade = Float(min(1, time / 1.5, (duration - time) / 2.5))
            left[index] = tanh(left[index] * 1.2) * max(0, fade)
            right[index] = tanh(right[index] * 1.2) * max(0, fade)
        }
        let peak = max(left.map(abs).max() ?? 0, right.map(abs).max() ?? 0)
        if peak > 0 {
            let scale = 0.9 / peak
            left = left.map { $0 * scale }
            right = right.map { $0 * scale }
        }
        return (left, right)
    }

    // MARK: Voices

    private static func frequency(_ midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    /// A Rhodes-ish tone: a sine with fading overtones, a slow tremolo and a warm low-pass.
    private static func epiano(_ midi: Int, length: Double, decay: Double) -> [Float] {
        let f = frequency(midi)
        var low = 0.0
        let count = Int(length * rate)
        return (0..<count).map { index in
            let t = Double(index) / rate
            let tone = sin(2 * .pi * f * t) + 0.28 * sin(4 * .pi * f * t) * exp(-t / 0.4) + 0.08 * sin(6 * .pi * f * t) * exp(-t / 0.15)
            let envelope = (1 - exp(-t / 0.004)) * exp(-t / decay) * min(1, Double(count - index) / (0.05 * rate))
            let sample = tone * envelope * (1 + 0.06 * sin(2 * .pi * 4.5 * t))
            low += 0.35 * (sample - low)
            return Float(low)
        }
    }

    private static func bass(_ midi: Int, length: Double) -> [Float] {
        let f = frequency(midi)
        let count = Int(length * rate)
        return (0..<count).map { index in
            let t = Double(index) / rate
            let tone = sin(2 * .pi * f * t) + 0.2 * sin(4 * .pi * f * t)
            let envelope = (1 - exp(-t / 0.008)) * exp(-t / 0.55) * min(1, Double(count - index) / (0.03 * rate))
            return Float(tanh(1.5 * tone * envelope))
        }
    }

    private static func kick() -> [Float] {
        var phase = 0.0
        return (0..<Int(rate * 0.35)).map { index in
            let t = Double(index) / rate
            phase += 2 * .pi * (48 + 95 * exp(-t * 32)) / rate
            let click = t < 0.002 ? 0.3 : 0
            return Float(sin(phase) * exp(-t / 0.17) + click)
        }
    }

    private static func snare() -> [Float] {
        var random = Seeded(seed: 3)
        var low = 0.0, band = 0.0, tail = 0.0
        return (0..<Int(rate * 0.4)).map { index in
            let t = Double(index) / rate
            let noise = Double.random(in: -1...1, using: &random)
            let f = 2 * sin(.pi * 1_800 / rate)
            low += f * band
            band += f * (noise - low - 0.8 * band)
            tail += 0.08 * (noise - tail)
            let body = 0.4 * sin(2 * .pi * 190 * t) * exp(-t / 0.05)
            return Float(band * exp(-t / 0.1) + body + 0.25 * tail * exp(-t / 0.22))
        }
    }

    private static func hat(open: Bool) -> [Float] {
        var random = Seeded(seed: open ? 11 : 5)
        var low = 0.0
        return (0..<Int(rate * (open ? 0.3 : 0.06))).map { index in
            let t = Double(index) / rate
            let noise = Double.random(in: -1...1, using: &random)
            low += 0.6 * (noise - low)
            return Float((noise - low) * exp(-t / (open ? 0.12 : 0.022)))
        }
    }
}

/// A tiny deterministic random source (SplitMix64), so the beat is identical on every render.
struct Seeded: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
