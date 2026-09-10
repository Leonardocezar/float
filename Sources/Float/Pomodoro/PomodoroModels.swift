import Foundation
import SwiftData

@Model
final class TaskItem {
    var id: UUID
    var title: String
    var estimatedPomodoros: Int
    var completedPomodoros: Int
    var isDone: Bool
    var createdAt: Date
    var order: Int

    init(
        id: UUID = UUID(),
        title: String,
        estimatedPomodoros: Int = 1,
        completedPomodoros: Int = 0,
        isDone: Bool = false,
        createdAt: Date = .now,
        order: Int = 0
    ) {
        self.id = id
        self.title = title
        self.estimatedPomodoros = estimatedPomodoros
        self.completedPomodoros = completedPomodoros
        self.isDone = isDone
        self.createdAt = createdAt
        self.order = order
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
