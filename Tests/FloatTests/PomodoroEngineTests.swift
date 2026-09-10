import XCTest
@testable import Float

@MainActor
final class PomodoroEngineTests: XCTestCase {
    private func makeEngine(_ config: PomodoroConfig, clock: Clock) -> PomodoroEngine {
        let engine = PomodoroEngine(config: config)
        engine.now = { clock.now }
        return engine
    }

    final class Clock {
        var now = Date(timeIntervalSince1970: 0)
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    func testWorkAdvancesToShortBreak() {
        let clock = Clock()
        var config = PomodoroConfig()
        config.workMinutes = 1
        config.autoStartNext = false
        let engine = makeEngine(config, clock: clock)

        engine.start(.work)
        XCTAssertEqual(engine.phase, .work)
        XCTAssertTrue(engine.isRunning)

        clock.advance(61)
        engine.tick()

        XCTAssertEqual(engine.completedWorkSessions, 1)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertFalse(engine.isRunning)
    }

    func testLongBreakCadence() {
        let clock = Clock()
        var config = PomodoroConfig()
        config.workMinutes = 1
        config.shortBreakMinutes = 1
        config.longBreakMinutes = 1
        config.sessionsBeforeLongBreak = 4
        config.autoStartNext = true
        let engine = makeEngine(config, clock: clock)

        engine.start(.work)
        var phases: [PomodoroPhase] = []

        for _ in 0..<8 {
            clock.advance(61)
            engine.tick()
            phases.append(engine.phase)
        }

        XCTAssertTrue(phases.contains(.longBreak))
        XCTAssertEqual(engine.completedWorkSessions, 4)
    }

    func testRemainingSurvivesClockJump() {
        let clock = Clock()
        var config = PomodoroConfig()
        config.workMinutes = 25
        config.autoStartNext = false
        let engine = makeEngine(config, clock: clock)

        engine.start(.work)
        clock.advance(10 * 60)
        engine.tick()

        XCTAssertEqual(engine.remaining, 15 * 60, accuracy: 1)
        XCTAssertEqual(engine.phase, .work)
    }

    func testPauseResumeResetFireCallbacks() {
        let clock = Clock()
        var config = PomodoroConfig()
        config.workMinutes = 10
        let engine = makeEngine(config, clock: clock)

        var events: [String] = []
        engine.onPhaseStart = { _ in events.append("start") }
        engine.onPause = { events.append("pause") }
        engine.onResume = { _ in events.append("resume") }
        engine.onReset = { events.append("reset") }

        engine.start(.work)
        clock.advance(30); engine.tick()
        engine.pause()
        engine.resume()
        engine.reset()

        XCTAssertEqual(events, ["start", "pause", "resume", "reset"])
    }

    func testPauseAndResume() {
        let clock = Clock()
        var config = PomodoroConfig()
        config.workMinutes = 10
        let engine = makeEngine(config, clock: clock)

        engine.start(.work)
        clock.advance(120)
        engine.tick()
        engine.pause()
        let remainingAtPause = engine.remaining

        clock.advance(300)
        engine.resume()
        engine.tick()

        XCTAssertEqual(engine.remaining, remainingAtPause, accuracy: 1)
    }
}
