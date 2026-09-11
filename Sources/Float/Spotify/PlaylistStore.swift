import Foundation

actor PlaylistStore {
    struct Entry: Codable, Equatable {
        var name: String
        var tracks: [SpotifyTrack]
        /// The playlist's track count as of the last check — the signal used
        /// to decide whether it needs re-syncing.
        var total: Int
        var complete: Bool
        var updatedAt: Date

        var displayTotal: Int { max(total, tracks.count) }
    }

    private struct Disk: Codable {
        var entries: [String: Entry] = [:]
        var playlists: [SpotifyPlaylist] = []
        var playlistsUpdatedAt: Date?
    }

    private var disk = Disk()
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

    // MARK: - Track listings

    func entry(for id: String) -> Entry? { disk.entries[id] }
    var ids: [String] { Array(disk.entries.keys) }
    var newestUpdate: Date? { disk.entries.values.map(\.updatedAt).max() }

    func put(id: String, name: String, tracks: [SpotifyTrack], total: Int, complete: Bool) {
        disk.entries[id] = Entry(name: name, tracks: tracks, total: total,
                                 complete: complete, updatedAt: .now)
        scheduleSave()
        onChange?(id)
    }

    // MARK: - The playlist list itself

    var playlists: [SpotifyPlaylist] { disk.playlists }
    var playlistsUpdatedAt: Date? { disk.playlistsUpdatedAt }

    func putPlaylists(_ list: [SpotifyPlaylist]) {
        disk.playlists = list
        disk.playlistsUpdatedAt = .now
        // forget cached track listings for playlists that are gone
        let keep = Set(list.map(\.id))
        disk.entries = disk.entries.filter { keep.contains($0.key) }
        scheduleSave()
    }

    // MARK: - Offline search over everything cached

    struct LocalHit: Equatable {
        var track: SpotifyTrack
        var playlistName: String
    }

    func localSearch(_ query: String, limit: Int = 40) -> [LocalHit] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        var hits: [LocalHit] = []
        for (_, e) in disk.entries {
            for t in e.tracks where hits.count < limit {
                guard t.name.lowercased().contains(q) || t.artist.lowercased().contains(q) else { continue }
                guard seen.insert(t.uri).inserted else { continue }
                hits.append(LocalHit(track: t, playlistName: e.name))
            }
        }
        return hits
    }

    func localPlaylists(matching query: String) -> [SpotifyPlaylist] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return disk.playlists.filter { $0.name.lowercased().contains(q) }
    }

    func clear() {
        disk = Disk()
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let d = try? JSONDecoder().decode(Disk.self, from: data) {
            disk = d
        } else if let legacy = try? JSONDecoder().decode([String: Entry].self, from: data) {
            disk.entries = legacy
            scheduleSave()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = disk
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
