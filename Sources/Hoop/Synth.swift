import Foundation

/// Makes the sound packs' effects in code, as mono samples. The noise comes from a fixed seed, so
/// every launch (and the promo) makes exactly the same sounds.
struct Synth {
    let rate: Double
    private var seed: UInt64 = 0x2545_F491_4F6C_DD1D

    init(rate: Double) {
        self.rate = rate
    }

    // MARK: Classic

    /// Band-passed noise whose pitch and loudness swell and fade: something flying past.
    mutating func whoosh(duration: Double, low: Double, high: Double, peak: Float = 0.55) -> [Float] {
        var filter = (lowpass: 0.0, band: 0.0)
        let count = Int(rate * duration)
        return Self.normalized((0..<count).map { i in
            let progress = Double(i) / Double(count)
            let band = Self.bandpass(&filter, noise(), cutoff: low + (high - low) * sin(.pi * progress), damping: 0.7, rate: rate)
            return Float(band * pow(progress, 0.7) * pow(1 - progress, 1.6))
        }, peak: peak)
    }

    /// A hollow bin being hit: inharmonic shell modes (one slightly detuned, for shimmer),
    /// a faint body thump and a tiny strike transient.
    mutating func clank(pitch: Double) -> [Float] {
        let modes: [(ratio: Double, amplitude: Double, decay: Double)] = [
            (1, 1, 0.32), (1.004, 0.5, 0.3), (2.31, 0.55, 0.18), (4.2, 0.3, 0.1), (6.7, 0.15, 0.06),
        ]
        let base = 410 * pitch
        return Self.normalized((0..<Int(rate * 0.55)).map { i in
            let t = Double(i) / rate
            let ring = modes.reduce(0) { $0 + $1.amplitude * sin(2 * .pi * base * $1.ratio * t) * exp(-t / $1.decay) }
            let body = 0.6 * sin(2 * .pi * 120 * t) * exp(-t / 0.04)
            let strike = t < 0.003 ? 0.5 * noise() : 0
            return Float((ring + body) * (1 - exp(-t / 0.0015)) + strike)
        }, peak: 0.35)
    }

    /// A file landing: a soft low tap with a short papery flutter.
    mutating func thud() -> [Float] {
        var phase = 0.0, flutter = 0.0
        return Self.normalized((0..<Int(rate * 0.14)).map { i in
            let t = Double(i) / rate
            phase += 2 * .pi * (48 + 60 * exp(-t * 30)) / rate
            flutter += 0.15 * (noise() - flutter)
            let tap = sin(phase) * exp(-t / 0.045)
            return Float((tap + 0.6 * flutter * exp(-t / 0.018)) * (1 - exp(-t / 0.001)))
        }, peak: 0.3)
    }

    /// A pea whistle: a pure tone warbling as the pea rattles round, with breath behind it. One blast
    /// per entry in `durations` (in seconds), a beat apart.
    mutating func whistle(pitch: Double, durations: [Double], peak: Float) -> [Float] {
        var breath = (lowpass: 0.0, band: 0.0)
        var phase = 0.0
        var samples: [Float] = []
        for duration in durations {
            if !samples.isEmpty { samples += [Float](repeating: 0, count: Int(rate * 0.07)) }
            for i in 0..<Int(rate * duration) {
                let t = Double(i) / rate
                // The pea cuts the air about 30 times a second: the pitch wobbles and the tone flutters.
                let warble = sin(2 * .pi * 31 * t)
                phase += 2 * .pi * pitch * (1 + 0.02 * warble) / rate
                let tone = (sin(phase) + 0.2 * sin(2 * phase)) * (0.8 + 0.2 * warble)
                let air = Self.bandpass(&breath, noise(), cutoff: pitch, damping: 0.4, rate: rate)
                let level = min(1, t / 0.012) * min(1, (duration - t) / 0.04)
                samples.append(Float((tone + 0.35 * air) * level))
            }
        }
        return Self.normalized(samples, peak: peak)
    }

    /// A clock's tick: a short, woody knock.
    mutating func tick(pitch: Double) -> [Float] {
        Self.normalized((0..<Int(rate * 0.05)).map { i in
            let t = Double(i) / rate
            let knock = sin(2 * .pi * pitch * t) * exp(-t / 0.007) + 0.5 * sin(2 * .pi * pitch * 2.76 * t) * exp(-t / 0.003)
            let strike = t < 0.0015 ? 0.4 * noise() : 0
            return Float(knock * (1 - exp(-t / 0.0005)) + strike)
        }, peak: 0.22)
    }

    /// A buzzer: detuned saws through a lowpass (`brightness`, 0…1, is how much of the buzz gets
    /// through), driven (`drive`) into a growl.
    func buzzer(pitches: [Double], duration: Double, brightness: Double, drive: Double, peak: Float) -> [Float] {
        var phases = [Double](repeating: 0, count: pitches.count)
        var tone = 0.0
        return Self.normalized((0..<Int(rate * duration)).map { i in
            let t = Double(i) / rate
            var saw = 0.0
            for index in pitches.indices {
                phases[index] = (phases[index] + pitches[index] / rate).truncatingRemainder(dividingBy: 1)
                saw += 2 * phases[index] - 1
            }
            tone += brightness * (saw - tone)
            let level = min(1, t / 0.01) * min(1, (duration - t) / 0.08)
            return Float(tanh(tone * drive) * level)
        }, peak: peak)
    }

    // MARK: Arcade

    /// A pulse wave gliding from `from` to `to` Hz and fading in 8-bit volume steps:
    /// a throw (up), a dodge or a bounce (down).
    func sweep(duration: Double, from: Double, to: Double, duty: Double, peak: Float) -> [Float] {
        var phase = 0.0
        let count = Int(rate * duration)
        return Self.normalized((0..<count).map { i in
            let progress = Double(i) / Double(count)
            phase = (phase + from * pow(to / from, progress) / rate).truncatingRemainder(dividingBy: 1)
            return Float(Self.pulse(phase, duty: duty) * Self.stepped(min(1, progress * 30) * (1 - progress)))
        }, peak: peak)
    }

    /// A file hitting the floor: a burst of a console's chunky noise over a falling triangle-wave kick.
    mutating func chipThud() -> [Float] {
        var phase = 0.0, held = 0.0
        // Console noise channels change value a few thousand times a second, not every sample.
        let hold = Int(rate / 5_000)
        return Self.normalized((0..<Int(rate * 0.12)).map { i in
            let t = Double(i) / rate
            if i % hold == 0 { held = noise() }
            phase = (phase + (45 + 110 * exp(-t * 35)) / rate).truncatingRemainder(dividingBy: 1)
            let triangle = 1 - 4 * abs(phase - 0.5)
            return Float((triangle + 0.6 * held * exp(-t / 0.025)) * Self.stepped(exp(-t / 0.05)))
        }, peak: 0.3)
    }

    /// A make: a coin's two notes, then a quick run up an E major chord, with a console-style echo.
    func coin() -> [Float] {
        let notes: [(frequency: Double, duration: Double, duty: Double)] = [
            (988, 0.06, 0.5), (1_319, 0.12, 0.5), (1_661, 0.05, 0.25), (1_976, 0.05, 0.25), (2_637, 0.26, 0.25),
        ]
        var phase = 0.0
        var samples: [Float] = []
        for (index, note) in notes.enumerated() {
            let count = Int(rate * note.duration)
            let isLast = index == notes.count - 1
            for i in 0..<count {
                phase = (phase + note.frequency / rate).truncatingRemainder(dividingBy: 1)
                let level = isLast ? 1 - Double(i) / Double(count) : 1
                samples.append(Float(Self.pulse(phase, duty: note.duty) * Self.stepped(level)))
            }
        }
        // Consoles faked an echo by replaying the phrase quieter, a beat later.
        let delay = Int(rate * 0.12)
        samples += [Float](repeating: 0, count: delay * 2)
        for i in delay..<samples.count {
            samples[i] += 0.35 * samples[i - delay]
        }
        return Self.normalized(samples, peak: 0.22)
    }

    /// A referee's whistle on a sound chip: a pulse wave trilling between two pitches, in two blasts.
    func chipWhistle() -> [Float] {
        var phase = 0.0
        var samples: [Float] = []
        for duration in [0.08, 0.28] {
            if !samples.isEmpty { samples += [Float](repeating: 0, count: Int(rate * 0.06)) }
            let count = Int(rate * duration)
            for i in 0..<count {
                // Flipping pitch 60 times a second, the way chip music fakes a trill.
                let pitch = Int(Double(i) / rate * 60).isMultiple(of: 2) ? 1_976.0 : 2_093.0
                phase = (phase + pitch / rate).truncatingRemainder(dividingBy: 1)
                samples.append(Float(Self.pulse(phase, duty: 0.5) * Self.stepped(1 - 0.6 * Double(i) / Double(count))))
            }
        }
        return Self.normalized(samples, peak: 0.18)
    }

    // MARK: Stadium

    /// An arena-sized whoosh: a low and a high whoosh together, echoing round the room.
    mutating func bigWhoosh(duration: Double, low: Double, high: Double) -> [Float] {
        let body = whoosh(duration: duration, low: low, high: high, peak: 1)
        let air = whoosh(duration: duration, low: low * 2.5, high: high * 2.5, peak: 1)
        return Self.normalized(arena(Self.layered([(body, 1), (air, 0.4)]), wet: 0.25), peak: 0.6)
    }

    /// A basketball rim: a metal ring's bending modes, each beating against a slightly detuned twin,
    /// after a hard strike and a thump from the backboard.
    mutating func rim(pitch: Double) -> [Float] {
        // A thin ring's modes go as n(n² − 1)/√(n² + 1) for n = 2, 3, 4, 5; here relative to the first.
        let modes: [(ratio: Double, amplitude: Double, decay: Double)] = [
            (1, 1, 0.6), (2.83, 0.6, 0.38), (5.42, 0.35, 0.22), (8.77, 0.2, 0.12),
        ]
        let base = 560 * pitch
        let dry = (0..<Int(rate * 0.9)).map { i -> Float in
            let t = Double(i) / rate
            let ring: Double = modes.reduce(0) { sum, mode in
                let angle = 2 * .pi * base * mode.ratio * t
                let pair = sin(angle) + 0.6 * sin(angle * 1.003)
                return sum + mode.amplitude * exp(-t / mode.decay) * pair
            }
            let backboard = 0.7 * sin(2 * .pi * 95 * t) * exp(-t / 0.05)
            let strike = t < 0.004 ? noise() * (1 - t / 0.004) : 0
            return Float((ring + backboard) * (1 - exp(-t / 0.001)) + strike)
        }
        return Self.normalized(arena(dry, wet: 0.2), peak: 0.38)
    }

    /// A ball bouncing on hardwood: a deep boom and a slap, echoing round the arena.
    mutating func bounce() -> [Float] {
        var phase = 0.0
        let dry = (0..<Int(rate * 0.25)).map { i -> Float in
            let t = Double(i) / rate
            phase += 2 * .pi * (60 + 120 * exp(-t * 40)) / rate
            let boom = sin(phase) * exp(-t / 0.07)
            let slap = noise() * exp(-t / 0.005)
            return Float((boom + 0.5 * slap) * (1 - exp(-t / 0.0008)))
        }
        return Self.normalized(arena(dry, wet: 0.3), peak: 0.34)
    }

    /// A make: an air horn blast over a crowd that swells and fades.
    mutating func hornAndCrowd() -> [Float] {
        let mix = Self.layered([(airHorn(), 0.55), (crowd(), 0.9)])
        return Self.normalized(arena(mix, wet: 0.25), peak: 0.5)
    }

    /// A referee's whistle, two blasts, ringing round the arena.
    mutating func refereeWhistle() -> [Float] {
        Self.normalized(arena(whistle(pitch: 2_900, durations: [0.12, 0.5], peak: 1), wet: 0.3), peak: 0.4)
    }

    /// The scoreboard counting down: a short electric beep, echoing round the arena.
    func scoreboardBeep() -> [Float] {
        Self.normalized(arena(buzzer(pitches: [1_046, 1_049], duration: 0.1, brightness: 0.35, drive: 1.5, peak: 1), wet: 0.3), peak: 0.3)
    }

    /// The end-of-period horn: a harsh, slightly sour buzz that fills the arena.
    func arenaHorn() -> [Float] {
        Self.normalized(arena(buzzer(pitches: [233, 234.4, 277], duration: 1.2, brightness: 0.3, drive: 2.5, peak: 1), wet: 0.25), peak: 0.45)
    }

    /// A buzzy F major chord, two slightly detuned saws per note, scooping up to pitch and
    /// lowpassed so it sounds brassy rather than fizzy.
    private func airHorn() -> [Float] {
        let pitches = [349.2, 440.0, 523.3].flatMap { [$0, $0 * 1.004] }
        var phases = [Double](repeating: 0, count: pitches.count)
        var brass = 0.0
        let duration = 0.8
        return Self.normalized((0..<Int(rate * duration)).map { i in
            let t = Double(i) / rate
            let scoop = 1 - 0.05 * exp(-t / 0.04)
            var saw = 0.0
            for index in pitches.indices {
                phases[index] = (phases[index] + pitches[index] * scoop / rate).truncatingRemainder(dividingBy: 1)
                saw += 2 * phases[index] - 1
            }
            brass += 0.2 * (saw - brass)
            let level = min(1, t / 0.02) * min(1, (duration - t) / 0.1)
            return Float(tanh(brass * 0.5) * level)
        }, peak: 1)
    }

    /// Thousands of voices: two bands of noise (the "aah" and the hiss of it) slowly wavering in
    /// loudness, swelling for half a second and fading out over the next one and a half.
    private mutating func crowd() -> [Float] {
        var aah = (lowpass: 0.0, band: 0.0), hiss = (lowpass: 0.0, band: 0.0)
        var waver = 0.0
        let duration = 2.2
        return Self.normalized((0..<Int(rate * duration)).map { i in
            let t = Double(i) / rate
            let input = noise()
            let voices = Self.bandpass(&aah, input, cutoff: 750, rate: rate) + 0.5 * Self.bandpass(&hiss, input, cutoff: 2_200, rate: rate)
            waver += 0.0004 * (noise() - waver)
            let swell = min(1, t / 0.5) * min(1, (duration - t) / 1.5)
            return Float(voices * swell * max(0, 1 + 25 * waver))
        }, peak: 1)
    }

    // MARK: Building blocks

    /// A big room: four feedback echoes (Schroeder comb filters) under the dry sound, ringing on after it.
    private func arena(_ dry: [Float], wet: Float, tail: Double = 0.7) -> [Float] {
        let input = dry + [Float](repeating: 0, count: Int(rate * tail))
        var output = input
        for delay in [0.0297, 0.0371, 0.0411, 0.0437].map({ Int(rate * $0) }) {
            var comb = [Float](repeating: 0, count: input.count)
            for i in input.indices {
                let echo = i >= delay ? comb[i - delay] : 0
                comb[i] = input[i] + 0.7 * echo
                output[i] += wet / 4 * echo
            }
        }
        return output
    }

    /// One step of a band-pass filter (a Chamberlin state-variable filter) on `input`.
    private static func bandpass(_ state: inout (lowpass: Double, band: Double), _ input: Double, cutoff: Double, damping: Double = 1, rate: Double) -> Double {
        let f = 2 * sin(.pi * cutoff / rate)
        state.lowpass += f * state.band
        state.band += f * (input - state.lowpass - damping * state.band)
        return state.band
    }

    /// A pulse wave with this duty cycle, centred on zero so it carries no DC offset.
    private static func pulse(_ phase: Double, duty: Double) -> Double {
        (phase < duty ? 1 : 0) - duty
    }

    /// A level rounded to one of 16 steps, like a console's 4-bit volume.
    private static func stepped(_ level: Double) -> Double {
        (level * 15).rounded() / 15
    }

    /// Sounds started together, each at its gain.
    private static func layered(_ layers: [(samples: [Float], gain: Float)]) -> [Float] {
        var mix = [Float](repeating: 0, count: layers.map(\.samples.count).max() ?? 0)
        for layer in layers {
            for (index, sample) in layer.samples.enumerated() { mix[index] += sample * layer.gain }
        }
        return mix
    }

    private static func normalized(_ samples: [Float], peak: Float) -> [Float] {
        let maximum = samples.map(abs).max() ?? 0
        guard maximum > 0 else { return samples }
        return samples.map { $0 / maximum * peak }
    }

    /// Seeded white noise in -1...1 (xorshift64).
    private mutating func noise() -> Double {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return Double(seed >> 11) * 0x1p-53 * 2 - 1
    }
}
