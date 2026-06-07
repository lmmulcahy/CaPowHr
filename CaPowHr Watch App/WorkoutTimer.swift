import Foundation

final class WorkoutTimer {
    private var timer: Timer?
    private(set) var startTime: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStartedAt: Date?

    var onTick: ((TimeInterval) -> Void)?

    var isPaused: Bool { pauseStartedAt != nil }

    func start() {
        startTime = Date()
        pausedAccumulated = 0
        pauseStartedAt = nil
        startTicking()
    }

    func pause() {
        guard pauseStartedAt == nil else { return }
        pauseStartedAt = Date()
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard let pauseStart = pauseStartedAt else { return }
        pausedAccumulated += Date().timeIntervalSince(pauseStart)
        pauseStartedAt = nil
        startTicking()
    }

    func stop(reset: Bool = true) {
        timer?.invalidate()
        timer = nil
        if reset {
            startTime = nil
            pausedAccumulated = 0
            pauseStartedAt = nil
        }
    }

    func elapsedSeconds(now: Date = Date()) -> TimeInterval {
        guard let start = startTime else { return 0 }
        var elapsed = now.timeIntervalSince(start) - pausedAccumulated
        if let pauseStart = pauseStartedAt {
            elapsed -= now.timeIntervalSince(pauseStart)
        }
        return max(0, elapsed)
    }

    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onTick?(self.elapsedSeconds())
        }
    }
}
