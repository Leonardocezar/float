import Foundation
import Combine

@MainActor
final class PomodoroEngine: ObservableObject {
    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval = 0

    @Published private(set) var completedWorkSessions = 0

    var config: PomodoroConfig

    var now: () -> Date = Date.init

    var onPhaseStart: ((PomodoroPhase) -> Void)?

    var onPhaseComplete: ((PomodoroPhase, _ start: Date, _ end: Date) -> Void)?

    var onPause: (() -> Void)?

    var onResume: ((PomodoroPhase) -> Void)?

    var onReset: (() -> Void)?

    private var endDate: Date?
    private var phaseStart: Date?
    private var timer: Timer?

    init(config: PomodoroConfig) {
        self.config = config
        self.remaining = config.duration(for: .work)
    }

    func start(_ phase: PomodoroPhase = .work) {
        guard phase != .idle else { return }
        beginPhase(phase)
    }

    func toggle() {
        switch (phase, isRunning) {
        case (.idle, _):
            beginPhase(.work)
        case (_, true):
            pause()
        case (_, false):
            resume()
        }
    }

    func pause() {
        guard isRunning, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSince(now()))
        isRunning = false
        endDate = nil
        stopTimer()
        onPause?()
    }

    func resume() {
        guard !isRunning, phase != .idle, remaining > 0 else { return }
        endDate = now().addingTimeInterval(remaining)
        isRunning = true
        startTimer()
        onResume?(phase)
    }

    func skip() {
        guard phase != .idle else { return }
        finishCurrentPhase()
    }

    func reset() {
        stopTimer()
        phase = .idle
        isRunning = false
        endDate = nil
        phaseStart = nil
        completedWorkSessions = 0
        remaining = config.duration(for: .work)
        onReset?()
    }

    func tick() {
        guard isRunning, let end = endDate else { return }
        let r = end.timeIntervalSince(now())
        if r <= 0 {
            remaining = 0
            finishCurrentPhase()
        } else {
            remaining = r
        }
    }

    private func beginPhase(_ p: PomodoroPhase) {
        let duration = config.duration(for: p)
        phase = p
        remaining = duration
        phaseStart = now()
        endDate = now().addingTimeInterval(duration)
        isRunning = true
        startTimer()
        onPhaseStart?(p)
    }

    private func finishCurrentPhase() {
        let finished = phase
        let start = phaseStart ?? now()
        let end = now()
        stopTimer()
        isRunning = false
        endDate = nil

        if finished == .work {
            completedWorkSessions += 1
        }
        onPhaseComplete?(finished, start, end)

        let next = nextPhase(after: finished)
        if config.autoStartNext {
            beginPhase(next)
        } else {
            phase = next
            remaining = config.duration(for: next)
            phaseStart = nil
        }
    }

    private func nextPhase(after finished: PomodoroPhase) -> PomodoroPhase {
        switch finished {
        case .work:
            let n = max(1, config.sessionsBeforeLongBreak)
            return completedWorkSessions % n == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak, .idle:
            return .work
        }
    }

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
