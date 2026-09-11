import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query private var sessions: [PomodoroSession]

    private var summary: StatsSummary {
        StatsService.summary(from: sessions)
    }
    private var week: [DailyFocus] {
        StatsService.last7Days(from: sessions)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    stat("Today", "\(Int(summary.todayMinutes)) min", "\(summary.todaySessions) sessions")
                    stat("This week", "\(Int(summary.weekMinutes)) min", "\(summary.streakDays)-day streak")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Last 7 days")
                        .font(.caption).foregroundStyle(.secondary)
                    Chart(week) { day in
                        BarMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Minutes", day.minutes)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    }
                    .frame(height: 130)
                }
                .padding(10)
                .background(Dracula.currentLine.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(12)
        }
    }

    private func stat(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(sub).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Dracula.currentLine.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
