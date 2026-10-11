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

/// Plays the chosen sound pack: macOS's own "move to trash" crumple when a file goes in, plus
/// synthesised whooshes, clanks, landings, the Shot Clock's whistle, ticks and buzzer and, in some
/// packs, a cheer for a make.
final class Sounds: SoundEffects {
    enum Effect: CaseIterable {
        /// A file goes into the Trash.
        case trash
        /// A file is thrown; play louder for faster throws.
        case whoosh
        /// Impossible mode: the Trash darts out of the way.
        case dodge
        /// A file hits the can or a rim.
        case clank
        /// A file lands on the floor, or bangs off the backboard.
        case thud
        /// A make, once the file is in the Trash or its folder. Classic leaves it to Finder's own trash sound.
        case make
        /// The Shot Clock starts.
        case whistle
        /// Each of the Shot Clock's last five seconds.
        case tick
        /// The Shot Clock runs out.
        case buzzer
    }

    /// The pack picked in the menu. Before packs there was only a Sound Effects switch; off stays off.
    var pack: SoundPack {
        get {
            if let pack = UserDefaults.standard.string(forKey: "soundPack").flatMap(SoundPack.init(rawValue:)) { return pack }
            return UserDefaults.standard.object(forKey: "soundEnabled") as? Bool == false ? .off : .classic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "soundPack")
            UserDefaults.standard.removeObject(forKey: "soundEnabled")
            _ = buffers(for: newValue) // synthesise now rather than in the middle of a throw
        }
    }

    private static let systemSounds = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds")
    private static let mono = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private let engine = AVAudioEngine()
    private let crumple = Sounds.load(Sounds.systemSounds.appending(path: "finder/move to trash.aif"))
    /// Each pack's variants per effect, made the first time the pack is used. One variant is
    /// picked at random each time so repeats don't sound identical.
    private var library: [SoundPack: [Effect: [AVAudioPCMBuffer]]] = [:]
    private var voices: [Effect: [AVAudioPlayerNode]] = [:]
    private var nextVoice: [Effect: Int] = [:]

    init() {
        for effect in Effect.allCases {
            // Every pack makes an effect in the same format, so one set of voices plays them all.
            let format = effect == .trash ? crumple?.format ?? Self.mono : Self.mono
            voices[effect] = (0..<3).map { _ in
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                return player
            }
        }
        _ = buffers(for: pack)
    }

    func play(_ effect: Effect, volume: Float = 1) {
        guard let buffer = buffers(for: pack)[effect]?.randomElement(), let players = voices[effect] else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let index = nextVoice[effect, default: 0]
        nextVoice[effect] = (index + 1) % players.count
        let player = players[index]
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    /// A taste of the current pack: its make, or a clank for a pack without one.
    func preview() {
        play(buffers(for: pack)[.make] == nil ? .clank : .make)
    }

    /// One of the effect's sound variants in `pack`, for mixing offline.
    func samples(for effect: Effect, in pack: SoundPack = .classic) -> AVAudioPCMBuffer? {
        buffers(for: pack)[effect]?.randomElement()
    }

    private func buffers(for pack: SoundPack) -> [Effect: [AVAudioPCMBuffer]] {
        if let buffers = library[pack] { return buffers }
        var buffers = pack.synthesize(rate: Self.mono.sampleRate).mapValues { $0.map { Self.buffer($0, format: Self.mono) } }
        if pack != .off, let crumple { buffers[.trash] = [crumple] }
        library[pack] = buffers
        return buffers
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
}
