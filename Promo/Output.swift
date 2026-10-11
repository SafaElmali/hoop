import AVFoundation
import Metal
import SpriteKit

/// Renders a SpriteKit scene offscreen with Metal, one frame at a time, at a fixed clock.
final class FrameRenderer {
    let width: Int
    let height: Int
    private(set) var pixels: [UInt8]
    private let renderer: SKRenderer
    private let queue: MTLCommandQueue
    private let texture: MTLTexture
    private let pass = MTLRenderPassDescriptor()

    init(scene: SKScene, width: Int, height: Int) {
        let device = MTLCreateSystemDefaultDevice()!
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        renderer = SKRenderer(device: device)
        renderer.scene = scene
        renderer.ignoresSiblingOrder = true
        queue = device.makeCommandQueue()!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        texture = device.makeTexture(descriptor: descriptor)!
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
    }

    /// Advances actions and physics to `time` and draws the frame; SKRenderer only steps the
    /// scene when it's also rendered. With `readBack`, copies it into `pixels` (BGRA, top row first).
    func render(at time: TimeInterval, readBack: Bool = true) {
        // SKRenderer ignores a clock that starts at zero, so run it from an arbitrary later point.
        renderer.update(atTime: 1_000 + time)
        let commands = queue.makeCommandBuffer()!
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: width, height: height), commandBuffer: commands, renderPassDescriptor: pass)
        commands.commit()
        commands.waitUntilCompleted()
        if readBack {
            texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
    }

    func image() -> CGImage {
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
}

/// Runs ffmpeg (from PATH): raw frames in through a pipe, H.264 out.
enum FFmpeg {
    static func start(_ arguments: [String], stdin: Pipe? = nil) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"] + arguments
        process.standardInput = stdin
        try process.run()
        return process
    }

    static func run(_ arguments: [String]) throws {
        let process = try start(arguments)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// Sounds the game asked for, with timestamps, mixed into a soundtrack after rendering.
final class SoundLog: SoundEffects {
    enum Sound {
        case game(Sounds.Effect)
        case click
    }

    var now: TimeInterval = 0
    private(set) var events: [(sound: Sound, volume: Float, time: TimeInterval)] = []

    func play(_ effect: Sounds.Effect, volume: Float) {
        events.append((.game(effect), volume, now))
    }

    func click() {
        events.append((.click, 1, now))
    }

    /// Mixes every event into a stereo WAV of `duration` seconds.
    func writeSoundtrack(to url: URL, duration: TimeInterval) throws {
        let rate = 44_100.0
        let sounds = Sounds()
        let frames = Int(duration * rate)
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        let click = Self.click(rate: rate)

        for event in events {
            let start = Int(event.time * rate)
            let channels: [[Float]]
            let gain: Float
            switch event.sound {
            case .click:
                channels = [click]
                gain = 0.35
            case let .game(effect):
                guard let buffer = sounds.samples(for: effect), let data = buffer.floatChannelData else { continue }
                let length = Int(buffer.frameLength)
                channels = (0..<Int(buffer.format.channelCount)).map { Array(UnsafeBufferPointer(start: data[$0], count: length)) }
                gain = Self.gain[effect] ?? 0.7
            }
            let volume = event.volume * gain
            for index in 0..<channels[0].count where start + index < frames {
                left[start + index] += channels[0][index] * volume
                right[start + index] += channels[channels.count > 1 ? 1 : 0][index] * volume
            }
        }

        let peak = max(left.map(abs).max() ?? 0, right.map(abs).max() ?? 0)
        let scale: Float = peak > 0.95 ? 0.95 / peak : 1
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for index in 0..<frames {
            buffer.floatChannelData![0][index] = left[index] * scale
            buffer.floatChannelData![1][index] = right[index] * scale
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private static let gain: [Sounds.Effect: Float] = [.trash: 0.95, .whoosh: 0.75, .dodge: 0.8, .clank: 0.7, .thud: 0.45]

    /// A short tick for keyboard shortcuts and menu clicks.
    private static func click(rate: Double) -> [Float] {
        (0..<Int(rate * 0.03)).map { index in
            let t = Double(index) / rate
            return Float((sin(2 * .pi * 2_200 * t) * 0.6 + Double.random(in: -0.4...0.4)) * exp(-t / 0.004))
        }
    }
}
