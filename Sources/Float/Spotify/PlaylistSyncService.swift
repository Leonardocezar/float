import Foundation
import Combine

@MainActor
final class PlaylistSyncService: ObservableObject {
    @Published private(set) var lastFullSyncAt: Date?
    @Published private(set) var syncing: Set<String> = []
    @Published private(set) var runningFullSync = false

    @Published private(set) var status: String = "idle"

    private let web: SpotifyWebClient
    private let store: PlaylistStore
    private let auth: SpotifyAuth
    private var timer: Timer?

    private let requestGap: Duration = .milliseconds(280)
    private let fullSyncInterval: TimeInterval = 20 * 60
    private let maxPlaylistsPerRun = 100
    private let maxTracksPerPlaylist = 1_000

    init(web: SpotifyWebClient, store: PlaylistStore, auth: SpotifyAuth) {
        self.web = web
        self.store = store
        self.auth = auth
    }

    func isSyncing(_ id: String) -> Bool { syncing.contains(id) }

    func startPeriodic() {
        timer?.invalidate()
        let t = Timer(timeInterval: fullSyncInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.runFullSync() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        Task {
            try? await Task.sleep(for: .seconds(6))
            await runFullSync()
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func runFullSync() async {
        guard auth.isAuthorized else { status = "not connected"; return }
        guard !web.isRateLimited else { status = "rate limited"; return }
        guard !runningFullSync else { return }
        runningFullSync = true
        defer { runningFullSync = false }

        status = "listing playlists…"
        let myID: String
        let all: [SpotifyPlaylist]
        do {
            myID = try await web.currentUserID()
            all = try await web.allUserPlaylists()
        } catch {
            status = "list failed: \(error.localizedDescription)"
            return
        }

        await store.putPlaylists(all)
        let mine = all.filter { ($0.ownerID != nil && $0.ownerID == myID) || $0.collaborative }
        status = "\(all.count) playlists, \(mine.count) mine"

        for (i, pl) in mine.prefix(maxPlaylistsPerRun).enumerated() {
            if web.isRateLimited { status = "rate limited (\(i)/\(mine.count))"; break }
            status = "syncing \(i + 1)/\(mine.count): \(pl.name)"
            await syncPlaylist(id: pl.id, force: false)
            try? await Task.sleep(for: requestGap)
        }
        lastFullSyncAt = .now
        status = "synced \(mine.count) playlists"
    }

    func syncPlaylist(id: String, force: Bool = false) async {
        guard auth.isAuthorized, !web.isRateLimited, !syncing.contains(id) else { return }

        if !force, let cached = await store.entry(for: id), cached.complete,
           Date().timeIntervalSince(cached.updatedAt) < 5 * 60 {
            return
        }

        let header: SpotifyWebClient.PlaylistHeader
        do { header = try await web.playlistHeader(id: id) }
        catch {
            status = "header failed: \(error.localizedDescription)"
            return
        }

        if !force,
           let cached = await store.entry(for: id),
           cached.snapshotID == header.snapshotID, cached.complete {
            return
        }

        syncing.insert(id)
        defer { syncing.remove(id) }

        let pageSize = 50
        var acc: [SpotifyTrack] = []
        var total = 0
        var offset = 0
        while acc.count < maxTracksPerPlaylist {
            if web.isRateLimited { break }
            let page: SpotifyWebClient.PlaylistPage
            do { page = try await web.playlistPage(id: id, offset: offset, limit: pageSize) }
            catch { status = "page failed: \(error.localizedDescription)"; break }

            acc += page.tracks
            if page.total > 0 { total = page.total }
            let complete = !page.hasMore
            await store.put(id: id, name: header.name, snapshotID: header.snapshotID,
                            tracks: acc, total: total, complete: complete)
            if complete || page.tracks.isEmpty { break }
            offset += pageSize
            try? await Task.sleep(for: requestGap)
        }
    }
}
