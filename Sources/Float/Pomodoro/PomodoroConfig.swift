import Foundation

enum PomodoroPhase: String, Codable, CaseIterable {
    case idle
    case work
    case shortBreak
    case longBreak

    var isBreak: Bool { self == .shortBreak || self == .longBreak }

    var title: String {
        switch self {
        case .idle: return "Ready"
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
}

struct PomodoroConfig: Codable, Equatable {
    var workMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var sessionsBeforeLongBreak: Int = 4
    var autoStartNext: Bool = true

    func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .idle: return 0
        case .work: return TimeInterval(max(1, workMinutes) * 60)
        case .shortBreak: return TimeInterval(max(1, shortBreakMinutes) * 60)
        case .longBreak: return TimeInterval(max(1, longBreakMinutes) * 60)
        }
    }
}
