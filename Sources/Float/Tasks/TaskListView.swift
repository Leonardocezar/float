import SwiftUI
import SwiftData

struct TaskListView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.order) private var tasks: [TaskItem]

    @State private var newTitle = ""

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

            if tasks.isEmpty {
                ContentUnavailableView("No tasks yet", systemImage: "checklist")
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(tasks) { task in
                        row(for: task)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
    }

    private func row(for task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Button {
                task.isDone.toggle()
                try? context.save()
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .lineLimit(1)
                Text("🍅 \(task.completedPomodoros)/\(task.estimatedPomodoros)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if services.activeTaskID == task.id {
                Image(systemName: "target").foregroundStyle(Color.accentColor)
            }

            Stepper("", value: Binding(
                get: { task.estimatedPomodoros },
                set: { task.estimatedPomodoros = max(1, $0); try? context.save() }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            services.activeTaskID = (services.activeTaskID == task.id) ? nil : task.id
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

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let task = tasks[index]
            if services.activeTaskID == task.id { services.activeTaskID = nil }
            context.delete(task)
        }
        try? context.save()
    }
}
