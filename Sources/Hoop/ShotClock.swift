import Foundation

/// A Shot Clock round: as many makes as you can before the buzzer. Counts down a second at a time,
/// and keeps the best round across launches.
final class ShotClock {
    static let standardSeconds = 30
    private static let bestKey = "shotClockBest"

    private(set) var secondsLeft: Int
    private(set) var made = 0
    /// The most made in a round before this one.
    let previousBest = UserDefaults.standard.integer(forKey: ShotClock.bestKey)

    var isOver: Bool { secondsLeft == 0 }
    var isNewBest: Bool { made > previousBest }

    /// The resting toast during the round, like "Shot Clock · 0:23" over "4 made · best 9".
    var hud: ToastContent {
        let best = max(previousBest, made)
        let score = made == 0 ? "Grab a paper ball and flick it" : "\(made) made"
        return ToastContent(
            title: String(format: "Shot Clock · %d:%02d", secondsLeft / 60, secondsLeft % 60),
            subtitle: best > 0 ? "\(score) · best \(best)" : score
        )
    }

    /// At the buzzer: "Time! 7 made", with a trophy for a new best.
    var result: ToastContent {
        ToastContent(title: "Time! \(made) made", subtitle: isNewBest ? "New best 🏆" : "Best \(previousBest)")
    }

    private let onTick: (ShotClock) -> Void
    private var timer: Timer?

    /// `onTick` runs each time a second comes off the clock, the last time at zero, when the round is over.
    init(seconds: Int = ShotClock.standardSeconds, onTick: @escaping (ShotClock) -> Void) {
        secondsLeft = seconds
        self.onTick = onTick
    }

    /// Starts the countdown. It keeps going while a menu is open.
    func start() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the clock where it is; a round called off this way doesn't count for the best.
    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    func recordMake() {
        if !isOver { made += 1 }
    }

    /// Takes a second off the clock (`start()` does this every second). At zero the round is over
    /// and a new best is saved.
    func tick() {
        guard !isOver else { return }
        secondsLeft -= 1
        if isOver {
            cancel()
            if isNewBest { UserDefaults.standard.set(made, forKey: Self.bestKey) }
        }
        onTick(self)
    }
}
