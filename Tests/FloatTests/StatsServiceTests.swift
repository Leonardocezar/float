import XCTest
@testable import Float

final class StatsServiceTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func session(dayOffset: Int, minutes: Double, phase: PomodoroPhase = .work, now: Date) -> PomodoroSession {
        let start = cal.date(byAdding: .day, value: dayOffset, to: now)!
        return PomodoroSession(startedAt: start,
                               endedAt: start.addingTimeInterval(minutes * 60),
                               phase: phase)
    }

    func testSummaryTotals() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sessions = [
            session(dayOffset: 0, minutes: 25, now: now),
            session(dayOffset: 0, minutes: 25, now: now),
            session(dayOffset: -2, minutes: 25, now: now),
            session(dayOffset: -10, minutes: 25, now: now),
            session(dayOffset: 0, minutes: 5, phase: .shortBreak, now: now),
        ]

        let s = StatsService.summary(from: sessions, calendar: cal, now: now)
        XCTAssertEqual(s.todaySessions, 2)
        XCTAssertEqual(s.todayMinutes, 50, accuracy: 0.01)
        XCTAssertEqual(s.weekMinutes, 75, accuracy: 0.01)
    }

    func testStreakCountsConsecutiveDays() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sessions = [
            session(dayOffset: 0, minutes: 25, now: now),
            session(dayOffset: -1, minutes: 25, now: now),
            session(dayOffset: -2, minutes: 25, now: now),
            session(dayOffset: -4, minutes: 25, now: now),
        ]
        XCTAssertEqual(StatsService.streak(from: sessions, calendar: cal, now: now), 3)
    }

    func testStreakZeroWhenStale() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sessions = [session(dayOffset: -3, minutes: 25, now: now)]
        XCTAssertEqual(StatsService.streak(from: sessions, calendar: cal, now: now), 0)
    }

    func testLast7DaysHasSevenBuckets() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let days = StatsService.last7Days(from: [session(dayOffset: 0, minutes: 25, now: now)],
                                          calendar: cal, now: now)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last?.minutes ?? 0, 25, accuracy: 0.01)
    }
}
