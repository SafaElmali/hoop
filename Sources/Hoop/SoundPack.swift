/// A set of sounds for the game, picked in 🏀 → Sounds.
enum SoundPack: String, CaseIterable {
    /// Soft whooshes, a hollow bin and soft landings; a make is Finder's own trash sound.
    case classic
    /// 8-bit: pulse-wave sweeps and blips, and a coin jingle for a make.
    case arcade
    /// Arena-sized: big whooshes, a ringing rim, a bouncing ball, and an air horn over the crowd for a make.
    case stadium
    case off

    var title: String { rawValue.capitalized }

    /// Each effect's variants as mono samples at `rate`. `Sounds` adds the system's Trash crumple.
    func synthesize(rate: Double) -> [Sounds.Effect: [[Float]]] {
        var synth = Synth(rate: rate)
        switch self {
        case .classic:
            return [
                .whoosh: [synth.whoosh(duration: 0.42, low: 450, high: 1_500)],
                .dodge: [synth.whoosh(duration: 0.16, low: 1_200, high: 3_400)],
                .clank: [0.9, 1, 1.12].map { synth.clank(pitch: $0) },
                .thud: [synth.thud()],
            ]
        case .arcade:
            return [
                .whoosh: [synth.sweep(duration: 0.2, from: 220, to: 880, duty: 0.25, peak: 0.2)],
                .dodge: [synth.sweep(duration: 0.12, from: 1_500, to: 300, duty: 0.125, peak: 0.2)],
                .clank: [0.9, 1, 1.12].map { synth.sweep(duration: 0.07, from: 760 * $0, to: 380 * $0, duty: 0.5, peak: 0.2) },
                .thud: [synth.chipThud()],
                .make: [synth.coin()],
            ]
        case .stadium:
            return [
                .whoosh: [synth.bigWhoosh(duration: 0.62, low: 220, high: 950)],
                .dodge: [synth.bigWhoosh(duration: 0.24, low: 700, high: 2_600)],
                .clank: [0.94, 1, 1.07].map { synth.rim(pitch: $0) },
                .thud: [synth.bounce()],
                .make: [synth.hornAndCrowd()],
            ]
        case .off:
            return [:]
        }
    }
}
