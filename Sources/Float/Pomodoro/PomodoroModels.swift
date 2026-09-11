import Foundation
import SwiftData

enum TaskStatus: String, CaseIterable, Identifiable, Codable {
    case todo, inProgress, done
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
}

@Model
final class TaskItem {
    var id: UUID
    var title: String
    var estimatedPomodoros: Int
    var completedPomodoros: Int
    var statusRaw: String = TaskStatus.todo.rawValue
    var createdAt: Date
    var order: Int

    init(
        id: UUID = UUID(),
        title: String,
        estimatedPomodoros: Int = 1,
        completedPomodoros: Int = 0,
        status: TaskStatus = .todo,
        createdAt: Date = .now,
        order: Int = 0
    ) {
        self.id = id
        self.title = title
        self.estimatedPomodoros = estimatedPomodoros
        self.completedPomodoros = completedPomodoros
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.order = order
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class PomodoroSession {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var phaseRaw: String
    var taskID: UUID?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        phase: PomodoroPhase,
        taskID: UUID? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.phaseRaw = phase.rawValue
        self.taskID = taskID
    }

    var phase: PomodoroPhase { PomodoroPhase(rawValue: phaseRaw) ?? .work }
    var minutes: Double { endedAt.timeIntervalSince(startedAt) / 60 }
}
