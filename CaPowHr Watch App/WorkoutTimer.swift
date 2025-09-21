import Foundation

final class WorkoutTimer {
    private var timer: Timer?
    private(set) var startTime: Date?

    var onTick: ((TimeInterval) -> Void)?

    func start() {
        startTime = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            self.onTick?(Date().timeIntervalSince(start))
        }
    }

    func stop(reset: Bool = true) {
        timer?.invalidate()
        timer = nil
        if reset { startTime = nil }
    }
}


