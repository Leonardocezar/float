import Foundation
import Combine

/// Keeps `PlaylistStore` populated with the track listing of every playlist
/// the user owns / collaborates on. Runs only when asked to (the Library
/// tab's refresh button, or opening a single playlist) — there is no
/// background timer. Each playlist is cheaply checked by its track count
/// first; only playlists whose count changed are paged through again.
@MainActor
final class PlaylistSyncService: ObservableObject {
    @Published private(set) var lastFullSyncAt: Date?
    @Published private(set) var syncing: Set<String> = []
    @Published private(set) var runningFullSync = false
    @Published private(set) var status: String = "idle"

    private let web: SpotifyWebClient
    private let store: PlaylistStore
    private let auth: SpotifyAuth

    private let requestGap: Duration = .milliseconds(280)
    private let maxPlaylistsPerRun = 100
    private let maxTracksPerPlaylist = 1_000

    init(web: SpotifyWebClient, store: PlaylistStore, auth: SpotifyAuth) {
        self.web = web
        self.store = store
        self.auth = auth
    }

    func isSyncing(_ id: String) -> Bool { syncing.contains(id) }

    /// Check every owned/collaborative playlist's track count and re-fetch
    /// only the ones that changed. User-triggered only.
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

        var changed = 0
        for (i, pl) in mine.prefix(maxPlaylistsPerRun).enumerated() {
            if web.isRateLimited { status = "rate limited (\(i)/\(mine.count) checked)"; break }
            status = "checking \(i + 1)/\(mine.count): \(pl.name)"
            if await syncPlaylist(id: pl.id, force: false) { changed += 1 }
            try? await Task.sleep(for: requestGap)
        }
        lastFullSyncAt = .now
        status = changed == 0
            ? "checked \(mine.count) playlists — all up to date"
            : "checked \(mine.count) playlists — \(changed) updated"
    }

    /// Re-fetch one playlist's tracks page by page, but only if its track
    /// count changed since the last check (or `force`). Returns whether it
    /// actually re-synced.
    @discardableResult
    func syncPlaylist(id: String, force: Bool = false) async -> Bool {
        guard auth.isAuthorized, !web.isRateLimited, !syncing.contains(id) else { return false }

        let header: SpotifyWebClient.PlaylistHeader
        do { header = try await web.playlistHeader(id: id) }
        catch {
            status = "check failed: \(error.localizedDescription)"
            return false
        }

        if !force,
           let cached = await store.entry(for: id),
           cached.total == header.total, cached.complete {
            return false
        }

        syncing.insert(id)
        defer { syncing.remove(id) }

        let pageSize = 50
        var acc: [SpotifyTrack] = []
        var offset = 0
        while acc.count < maxTracksPerPlaylist {
            if web.isRateLimited { break }
            let page: SpotifyWebClient.PlaylistPage
            do { page = try await web.playlistPage(id: id, offset: offset, limit: pageSize) }
            catch { status = "page failed: \(error.localizedDescription)"; break }

            acc += page.tracks
            let total = page.total > 0 ? page.total : header.total
            let complete = !page.hasMore
            await store.put(id: id, name: header.name, tracks: acc, total: total, complete: complete)
            if complete || page.tracks.isEmpty { break }
            offset += pageSize
            try? await Task.sleep(for: requestGap)
        }
        return true
    }
}
