import Foundation

struct StatsSummary: Equatable {
    var todayMinutes: Double = 0
    var weekMinutes: Double = 0
    var todaySessions: Int = 0
    var streakDays: Int = 0
}

struct DailyFocus: Identifiable, Equatable {
    var id: Date { day }
    var day: Date
    var minutes: Double
}

enum StatsService {
    static func workSessions(_ sessions: [PomodoroSession]) -> [PomodoroSession] {
        sessions.filter { $0.phase == .work }
    }

    static func summary(
        from sessions: [PomodoroSession],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> StatsSummary {
        let work = workSessions(sessions)
        let startOfToday = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday

        var s = StatsSummary()
        for session in work {
            if session.startedAt >= startOfToday {
                s.todayMinutes += session.minutes
                s.todaySessions += 1
            }
            if session.startedAt >= weekStart {
                s.weekMinutes += session.minutes
            }
        }
        s.streakDays = streak(from: work, calendar: calendar, now: now)
        return s
    }

    static func streak(
        from work: [PomodoroSession],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let days = Set(work.map { calendar.startOfDay(for: $0.startedAt) })
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)

        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    static func last7Days(
        from sessions: [PomodoroSession],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [DailyFocus] {
        let work = workSessions(sessions)
        let startOfToday = calendar.startOfDay(for: now)
        return (0..<7).reversed().map { offset -> DailyFocus in
            let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) ?? startOfToday
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let minutes = work
                .filter { $0.startedAt >= day && $0.startedAt < next }
                .reduce(0) { $0 + $1.minutes }
            return DailyFocus(day: day, minutes: minutes)
        }
    }
}
