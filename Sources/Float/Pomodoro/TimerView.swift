import SwiftUI
import SwiftData

struct TimerView: View {
    @EnvironmentObject private var engine: PomodoroEngine
    @EnvironmentObject private var services: AppServices
    @Query private var tasks: [TaskItem]

    private var activeTask: TaskItem? {
        guard let id = services.activeTaskID else { return nil }
        return tasks.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(engine.phase.title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(engine.phase.isBreak ? Color.teal : Color.accentColor)

            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        engine.phase.isBreak ? Color.teal : Color.accentColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: progress)

                VStack(spacing: 2) {
                    Text(timeString)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("🍅 \(engine.completedWorkSessions)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
            .padding(.vertical, 4)

            if let activeTask {
                Label(activeTask.title, systemImage: "target")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Button {
                    engine.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(engine.phase == .idle && !engine.isRunning)

                Button {
                    engine.toggle()
                } label: {
                    Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
                        .frame(width: 30)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    engine.skip()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(.bordered)
                .disabled(engine.phase == .idle)
            }
        }
        .padding(16)
    }

    private var progress: CGFloat {
        let total = engine.config.duration(for: engine.phase == .idle ? .work : engine.phase)
        guard total > 0 else { return 0 }
        return CGFloat(1 - engine.remaining / total)
    }

    private var timeString: String {
        let secs = Int(engine.remaining.rounded())
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }
}
