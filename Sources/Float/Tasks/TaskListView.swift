import SwiftUI
import SwiftData

struct TaskListView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.order) private var tasks: [TaskItem]

    @State private var newTitle = ""
    @State private var tab: TaskStatus = .todo

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Add a task…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button(action: add) { Image(systemName: "plus") }
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)

            Picker("", selection: $tab) {
                ForEach(TaskStatus.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if tasks.isEmpty {
                ContentUnavailableView("No tasks yet", systemImage: "checklist")
                    .frame(maxHeight: .infinity)
            } else if shown.isEmpty {
                ContentUnavailableView("No \(tab.label.lowercased()) tasks", systemImage: "checklist")
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(shown) { task in
                        row(for: task)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var shown: [TaskItem] { tasks.filter { $0.status == tab } }

    private func row(for task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Button {
                services.activeTaskID = (services.activeTaskID == task.id) ? nil : task.id
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.status == .done ? Color.accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .strikethrough(task.status == .done)
                            .lineLimit(1)
                        Text("🍅 \(task.completedPomodoros)/\(task.estimatedPomodoros)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if services.activeTaskID == task.id {
                        Image(systemName: "target").foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Stepper("", value: Binding(
                get: { task.estimatedPomodoros },
                set: { task.estimatedPomodoros = max(1, $0); try? context.save() }
            ))
            .labelsHidden()

            Menu {
                ForEach(TaskStatus.allCases.filter { $0 != task.status }) { status in
                    Button("Move to \(status.label)") {
                        task.status = status
                        try? context.save()
                    }
                }
                Divider()
                Button("Delete", role: .destructive) { delete(task) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .frame(width: 18)
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let nextOrder = (tasks.map(\.order).max() ?? 0) + 1
        context.insert(TaskItem(title: title, order: nextOrder))
        try? context.save()
        newTitle = ""
    }

    private func delete(_ task: TaskItem) {
        if services.activeTaskID == task.id { services.activeTaskID = nil }
        context.delete(task)
        try? context.save()
    }
}
