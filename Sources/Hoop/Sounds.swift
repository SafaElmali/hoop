import AVFoundation

/// What the game needs from a sound player; the promo renderer records these instead of playing them.
protocol SoundEffects: AnyObject {
    func play(_ effect: Sounds.Effect, volume: Float)
}

extension SoundEffects {
    func play(_ effect: Sounds.Effect) {
        play(effect, volume: 1)
    }
}

/// Sound effects: macOS's own "move to trash" crumple when a file goes in, plus synthesised
/// whooshes, can clanks and landings.
final class Sounds: SoundEffects {
    enum Effect {
        /// A file goes into the Trash.
        case trash
        /// A file is thrown; play louder for faster throws.
        case whoosh
        /// Impossible mode: the Trash darts out of the way.
        case dodge
        /// A file hits the can.
        case clank
        /// A file lands on the floor.
        case thud
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundEnabled") }
    }

    private static let systemSounds = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds")

    private let engine = AVAudioEngine()
    /// Variants per effect, one picked at random each time so repeats don't sound identical.
    private var buffers: [Effect: [AVAudioPCMBuffer]] = [:]
    private var voices: [Effect: [AVAudioPlayerNode]] = [:]
    private var nextVoice: [Effect: Int] = [:]

    init() {
        let mono = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let rate = mono.sampleRate
        buffers = [
            .whoosh: [Self.buffer(Self.whoosh(rate: rate, duration: 0.42, low: 450, high: 1_500), format: mono)],
            .dodge: [Self.buffer(Self.whoosh(rate: rate, duration: 0.16, low: 1_200, high: 3_400), format: mono)],
            .clank: [0.9, 1, 1.12].map { Self.buffer(Self.clank(rate: rate, pitch: $0), format: mono) },
            .thud: [Self.buffer(Self.thud(rate: rate), format: mono)],
        ]
        if let crumple = Self.load(Self.systemSounds.appending(path: "finder/move to trash.aif")) {
            buffers[.trash] = [crumple]
        }
        for (effect, variants) in buffers {
            guard let format = variants.first?.format else { continue }
            voices[effect] = (0..<3).map { _ in
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                return player
            }
        }
    }

    func play(_ effect: Effect, volume: Float = 1) {
        guard isEnabled, let buffer = buffers[effect]?.randomElement(), let players = voices[effect] else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let index = nextVoice[effect, default: 0]
        nextVoice[effect] = (index + 1) % players.count
        let player = players[index]
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    /// One of the effect's sound variants, for mixing offline.
    func samples(for effect: Effect) -> AVAudioPCMBuffer? {
        buffers[effect]?.randomElement()
    }

    private static func load(_ url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil
        else { return nil }
        return buffer
    }

    private static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    // MARK: Synthesis

    /// Band-passed noise whose pitch and loudness swell and fade: something flying past.
    private static func whoosh(rate: Double, duration: Double, low: Double, high: Double) -> [Float] {
        var lowpass = 0.0, band = 0.0
        let count = Int(rate * duration)
        return normalized((0..<count).map { i in
            let progress = Double(i) / Double(count)
            let cutoff = low + (high - low) * sin(.pi * progress)
            let f = 2 * sin(.pi * cutoff / rate)
            lowpass += f * band
            let highpass = Double.random(in: -1...1) - lowpass - 0.7 * band
            band += f * highpass
            return Float(band * pow(progress, 0.7) * pow(1 - progress, 1.6))
        }, peak: 0.55)
    }

    /// A hollow bin being hit: inharmonic shell modes (one slightly detuned, for shimmer),
    /// a faint body thump and a tiny strike transient.
    private static func clank(rate: Double, pitch: Double) -> [Float] {
        let modes: [(ratio: Double, amplitude: Double, decay: Double)] = [
            (1, 1, 0.32), (1.004, 0.5, 0.3), (2.31, 0.55, 0.18), (4.2, 0.3, 0.1), (6.7, 0.15, 0.06),
        ]
        let base = 410 * pitch
        return normalized((0..<Int(rate * 0.55)).map { i in
            let t = Double(i) / rate
            let ring = modes.reduce(0) { $0 + $1.amplitude * sin(2 * .pi * base * $1.ratio * t) * exp(-t / $1.decay) }
            let body = 0.6 * sin(2 * .pi * 120 * t) * exp(-t / 0.04)
            let strike = t < 0.003 ? Double.random(in: -0.5...0.5) : 0
            return Float((ring + body) * (1 - exp(-t / 0.0015)) + strike)
        }, peak: 0.35)
    }

    /// A file landing: a soft low tap with a short papery flutter.
    private static func thud(rate: Double) -> [Float] {
        var phase = 0.0, flutter = 0.0
        return normalized((0..<Int(rate * 0.14)).map { i in
            let t = Double(i) / rate
            phase += 2 * .pi * (48 + 60 * exp(-t * 30)) / rate
            flutter += 0.15 * (Double.random(in: -1...1) - flutter)
            let tap = sin(phase) * exp(-t / 0.045)
            return Float((tap + 0.6 * flutter * exp(-t / 0.018)) * (1 - exp(-t / 0.001)))
        }, peak: 0.3)
    }

    private static func normalized(_ samples: [Float], peak: Float) -> [Float] {
        let maximum = samples.map(abs).max() ?? 0
        guard maximum > 0 else { return samples }
        return samples.map { $0 / maximum * peak }
    }
}
