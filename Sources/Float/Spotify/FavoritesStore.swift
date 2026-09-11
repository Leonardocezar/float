import Foundation

actor FavoritesStore {
    private struct Disk: Codable {
        var artists: [SpotifyArtist] = []
        var updatedAt: Date?
    }

    private var disk = Disk()
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(filename: String = "favorite-artists-cache.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Float", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent(filename)
        load()
    }

    var artists: [SpotifyArtist] { disk.artists }
    var updatedAt: Date? { disk.updatedAt }

    func isFavorite(_ id: String) -> Bool { disk.artists.contains { $0.id == id } }

    func replaceAll(_ artists: [SpotifyArtist]) {
        disk.artists = artists
        disk.updatedAt = .now
        scheduleSave()
    }

    func add(_ artist: SpotifyArtist) {
        if let i = disk.artists.firstIndex(where: { $0.id == artist.id }) {
            disk.artists[i] = artist
        } else {
            disk.artists.insert(artist, at: 0)
        }
        scheduleSave()
    }

    func remove(id: String) {
        disk.artists.removeAll { $0.id == id }
        scheduleSave()
    }

    func localSearch(_ query: String) -> [SpotifyArtist] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return disk.artists.filter { $0.name.lowercased().contains(q) }
    }

    func clear() {
        disk = Disk()
        scheduleSave()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let d = try? JSONDecoder().decode(Disk.self, from: data) else { return }
        disk = d
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
