import Foundation

actor PlaylistStore {
    struct Entry: Codable, Equatable {
        var name: String
        var snapshotID: String
        var tracks: [SpotifyTrack]

        var total: Int

        var complete: Bool
        var updatedAt: Date

        var displayTotal: Int { max(total, tracks.count) }
    }

    private var entries: [String: Entry] = [:]
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    var onChange: (@Sendable (String) -> Void)?

    init(filename: String = "playlist-cache.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Float", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent(filename)
        load()
    }

    func setOnChange(_ handler: @escaping @Sendable (String) -> Void) { onChange = handler }

    func entry(for id: String) -> Entry? { entries[id] }
    func snapshot(for id: String) -> String? { entries[id]?.snapshotID }
    var ids: [String] { Array(entries.keys) }
    var newestUpdate: Date? { entries.values.map(\.updatedAt).max() }

    func put(id: String, name: String, snapshotID: String,
             tracks: [SpotifyTrack], total: Int, complete: Bool) {
        entries[id] = Entry(name: name, snapshotID: snapshotID, tracks: tracks,
                            total: total, complete: complete, updatedAt: .now)
        scheduleSave()
        onChange?(id)
    }

    func keepOnly(ids keep: Set<String>) {
        let before = entries.count
        entries = entries.filter { keep.contains($0.key) }
        if entries.count != before { scheduleSave() }
    }

    func clear() {
        entries = [:]
        scheduleSave()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = decoded
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = entries
        let url = fileURL
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
