import AppKit
import Combine

@MainActor
final class SpotifyModel: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var playlists: [SpotifyPlaylist] = []
    @Published private(set) var playlistsFromCache = false
    @Published private(set) var playlistsUpdatedAt: Date?
    @Published private(set) var searchIsOffline = false
    @Published var lastError: String?

    var isRateLimited: Bool { web.isRateLimited }

    @Published private(set) var contextName: String = ""
    @Published private(set) var contextTracks: [SpotifyTrack] = []
    @Published private(set) var isLoadingContext = false
    @Published private(set) var contextComplete = true
    @Published private(set) var contextTotal = 0

    @Published private(set) var searchResults = SpotifySearchResults()
    @Published private(set) var isSearching = false
    @Published private(set) var openedList: SpotifyBrowseItem?
    @Published private(set) var openedListTracks: [SpotifyTrack] = []
    @Published private(set) var isLoadingList = false
    @Published private(set) var openListError: String?
    @Published private(set) var openedListComplete = true
    @Published private(set) var openedListTotal = 0
    @Published private(set) var myUserID: String?

    let store: PlaylistStore
    let sync: PlaylistSyncService

    private var openedPlaylistID: String?
    private var contextPlaylistID: String?

    @Published var notice: String?

    private var noticeClearWork: DispatchWorkItem?

    private var loadedContextURI: String?

    private var apiContextURI: String?
    private var apiTrackURI: String?
    private var lastSnapshotAt: Date = .distantPast
    private var drawerPollTimer: Timer?

    let engine: SpotifyPlaybackEngine
    let web: SpotifyWebClient
    let auth: SpotifyAuth

    private var cancellables = Set<AnyCancellable>()
    private var ticker: Timer?

    var isAuthorized: Bool { auth.isAuthorized }
    var isPlayerReady: Bool { engine.deviceID != nil }
    var needsActivation: Bool { engine.deviceID != nil && !engine.isActivated }
    var playerLog: String? { engine.lastLog }

    init(engine: SpotifyPlaybackEngine, web: SpotifyWebClient, auth: SpotifyAuth,
         store: PlaylistStore, sync: PlaylistSyncService) {
        self.engine = engine
        self.web = web
        self.auth = auth
        self.store = store
        self.sync = sync

        Task { [weak self] in
            await store.setOnChange { id in
                Task { @MainActor in self?.storeEntryChanged(id) }
            }
        }
        sync.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        engine.$nowPlaying
            .sink { [weak self] np in
                guard let self else { return }
                let trackChanged = np?.trackURI != self.nowPlaying?.trackURI
                self.nowPlaying = np
                if trackChanged { self.syncPlaybackSnapshot(force: false) }
            }
            .store(in: &cancellables)
        engine.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        engine.$lastError
            .compactMap { $0 }
            .sink { [weak self] in self?.lastError = $0 }
            .store(in: &cancellables)
        auth.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        engine.startIfNeeded()
        if auth.isAuthorized {
            Task { await loadPlaylists() }
        }
        ticker?.invalidate()

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    func playPause() { engine.togglePlay() }
    func next() { engine.next() }
    func previous() { engine.previous() }

    func play() { engine.play(web: web) }
    func resume() { play() }

    func pause() { engine.pause() }
    func activate() { engine.activate() }

    func seek(fraction: Double) {
        guard let np = nowPlaying, np.duration > 0 else { return }
        engine.seek(toMilliseconds: np.duration * fraction)
    }

    func play(uri: String) {
        guard !uri.isEmpty else { return }
        guard isAuthorized else { lastError = "Connect Spotify in Settings first."; return }
        engine.play(contextURI: uri, web: web)
    }

    var currentContextURI: String? {
        apiContextURI ?? nowPlaying?.contextURI ?? nowPlaying?.albumURI
    }
    var currentTrackURI: String? { nowPlaying?.trackURI ?? apiTrackURI }

    private var listedContextURI: String?

    func playDrawerTrack(_ track: SpotifyTrack) {
        let context = listedContextURI ?? currentContextURI
        if let context {
            engine.playTrack(uri: track.uri, inContext: context, web: web)
        } else {
            engine.play(contextURI: track.uri, web: web)
        }
        apiTrackURI = track.uri
    }

    private var lastSearchQuery = ""

    func search(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchResults = SpotifySearchResults(); lastSearchQuery = ""; searchIsOffline = false; return
        }
        guard q.lowercased() != lastSearchQuery else { return }
        lastSearchQuery = q.lowercased()

        if web.isRateLimited || !auth.isAuthorized {
            Task { await self.offlineSearch(q) }
            return
        }

        isSearching = true
        Task {
            do {
                self.searchResults = try await web.search(q)
                self.searchIsOffline = false
            } catch {
                await self.offlineSearch(q)
                if self.searchResults.isEmpty { self.lastError = error.localizedDescription }
                self.lastSearchQuery = ""
            }
            self.isSearching = false
        }
    }

    /// Search over everything already in the local cache — works with no network.
    private func offlineSearch(_ q: String) async {
        let hits = await store.localSearch(q)
        let pls = await store.localPlaylists(matching: q)
        var r = SpotifySearchResults()
        r.tracks = hits.map(\.track)
        r.playlists = pls.map {
            SpotifyBrowseItem(id: $0.id, name: $0.name,
                              subtitle: isOwned($0) ? "Playlist" : "Followed",
                              uri: $0.uri, kind: .playlist,
                              ownerID: $0.ownerID, collaborative: $0.collaborative,
                              imageURL: $0.imageURL)
        }
        searchResults = r
        searchIsOffline = true
    }

    func clearSearch() {
        searchResults = SpotifySearchResults(); lastSearchQuery = ""; searchIsOffline = false
    }

    func canBrowse(_ item: SpotifyBrowseItem) -> Bool {
        if item.kind == .album { return true }
        if item.collaborative { return true }
        guard let owner = item.ownerID else { return true }
        return myUserID == nil || owner == myUserID
    }

    func isOwned(_ pl: SpotifyPlaylist) -> Bool {
        if pl.collaborative { return true }
        guard let owner = pl.ownerID, let me = myUserID else { return false }
        return owner == me
    }

    func openList(_ item: SpotifyBrowseItem) {
        openedList = item
        openedListTracks = []
        openListError = nil
        openedListComplete = true
        openedListTotal = 0
        openedPlaylistID = item.kind == .playlist ? item.id : nil

        if item.kind == .album {
            isLoadingList = true
            Task {
                do {
                    let r = try await web.contextTracks(contextURI: item.uri)
                    self.openedListTracks = r.tracks
                    if r.tracks.isEmpty { self.openListError = "Couldn’t load this album." }
                } catch {
                    self.openListError = self.friendlyOpenError(error)
                }
                self.isLoadingList = false
            }
            return
        }

        Task {
            if let e = await store.entry(for: item.id) {
                self.applyOpenedEntry(e)
            } else {
                self.isLoadingList = true
            }
            await sync.syncPlaylist(id: item.id)

            if self.openedPlaylistID == item.id,
               await store.entry(for: item.id) == nil {
                self.isLoadingList = false
                self.openListError = "Spotify only lets Float open playlists you own or collaborate on. Tap ▶ to play it."
            }
        }
    }

    private func applyOpenedEntry(_ e: PlaylistStore.Entry) {
        openedListTracks = e.tracks
        openedListComplete = e.complete
        openedListTotal = e.displayTotal
        isLoadingList = false
        openListError = nil
    }

    func closeList() {
        openedList = nil
        openedListTracks = []
        openListError = nil
        openedPlaylistID = nil
        openedListComplete = true
    }

    func refreshOpenedList() {
        guard let item = openedList, item.kind == .playlist else { return }
        Task { await sync.syncPlaylist(id: item.id, force: true) }
    }

    private func friendlyOpenError(_ error: Error) -> String {
        let d = error.localizedDescription
        if d.contains("403") {
            return "Spotify only lets Float open playlists you own or collaborate on. Tap ▶ to play it."
        }
        return d
    }

    func storeEntryChanged(_ id: String) {
        Task {
            guard let e = await store.entry(for: id) else { return }
            if openedPlaylistID == id { applyOpenedEntry(e) }
            if contextPlaylistID == id {
                contextTracks = e.tracks
                contextName = e.name
                contextComplete = e.complete
                contextTotal = e.displayTotal
                isLoadingContext = false
            }
        }
    }

    func playTrack(_ track: SpotifyTrack, inContext contextURI: String?) {
        if let contextURI {
            engine.playTrack(uri: track.uri, inContext: contextURI, web: web)
        } else {
            engine.play(contextURI: track.uri, web: web)
        }
        apiTrackURI = track.uri
    }

    func playList(uri: String) { play(uri: uri) }

    func queue(_ track: SpotifyTrack) {
        Task {
            do {
                try await web.addToQueue(uri: track.uri, deviceID: engine.deviceID)
                self.showNotice("Queued “\(track.name)”")
            } catch { self.lastError = error.localizedDescription }
        }
    }

    func addTrack(_ track: SpotifyTrack, to playlist: SpotifyPlaylist) {
        Task {
            do {
                try await web.addTracks([track.uri], toPlaylist: playlist.id)
                self.showNotice("Added to \(playlist.name)")
            } catch { self.lastError = self.friendlyModifyError(error) }
        }
    }

    func createPlaylist(named name: String, addingTrack track: SpotifyTrack? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                let pl = try await web.createPlaylist(name: trimmed)
                if let track { try await web.addTracks([track.uri], toPlaylist: pl.id) }
                await self.loadPlaylists(force: true)
                self.showNotice(track == nil ? "Created \(pl.name)" : "Created \(pl.name) with “\(track!.name)”")
            } catch { self.lastError = self.friendlyModifyError(error) }
        }
    }

    private func friendlyModifyError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.contains("403") {
            return "Reconnect Spotify in Settings to enable playlist editing."
        }
        return msg
    }

    private func showNotice(_ text: String) {
        notice = text
        noticeClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    func drawerDidOpen() {
        syncPlaybackSnapshot(force: true)
        Task { await loadPlaylists() }
        if myUserID == nil {
            Task { self.myUserID = try? await web.currentUserID() }
        }
        drawerPollTimer?.invalidate()

        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPlaybackSnapshot(force: false) }
        }
        RunLoop.main.add(t, forMode: .common)
        drawerPollTimer = t
    }

    func drawerDidClose() {
        drawerPollTimer?.invalidate()
        drawerPollTimer = nil
        closeList()
        searchResults = SpotifySearchResults()
    }

    func refreshContext() {
        if let pid = contextPlaylistID {
            Task { await sync.syncPlaylist(id: pid, force: true) }
        }
        loadedContextURI = nil
        lastSnapshotAt = .distantPast
        syncPlaybackSnapshot(force: true)
    }

    private func syncPlaybackSnapshot(force: Bool) {
        guard auth.isAuthorized, !web.isRateLimited else { return }

        if !force, Date().timeIntervalSince(lastSnapshotAt) < 8 { return }
        lastSnapshotAt = .now

        Task {
            if let snap = try? await web.currentPlayback() {
                self.apiContextURI = snap.contextURI
                self.apiTrackURI = snap.trackURI
            } else {
                self.apiContextURI = nil
                self.apiTrackURI = nil
            }
            self.reloadContextIfNeeded(self.currentContextURI)
        }
    }

    private func reloadContextIfNeeded(_ contextURI: String?) {
        guard let contextURI else {
            loadedContextURI = nil
            listedContextURI = nil
            contextPlaylistID = nil
            contextName = ""
            contextTracks = []
            contextComplete = true
            return
        }

        guard contextURI != loadedContextURI else { return }
        loadedContextURI = contextURI
        listedContextURI = contextURI

        let ref = SpotifyWebClient.parseContextURI(contextURI)

        if ref?.kind == "playlist", let pid = ref?.id {
            contextPlaylistID = pid
            contextComplete = true
            contextTotal = 0
            isLoadingContext = true
            Task {
                if let e = await store.entry(for: pid) {
                    self.contextName = e.name
                    self.contextTracks = e.tracks
                    self.contextComplete = e.complete
                    self.contextTotal = e.displayTotal
                    self.isLoadingContext = false
                }
                await sync.syncPlaylist(id: pid)
                if self.contextPlaylistID == pid, await store.entry(for: pid) == nil {
                    self.contextPlaylistID = nil
                    self.loadAlbumContext(self.nowPlaying?.albumURI)
                }
            }
            return
        }

        contextPlaylistID = nil
        isLoadingContext = true
        loadAlbumContext(contextURI)
    }

    private func loadAlbumContext(_ uri: String?) {
        guard let uri else { contextTracks = []; isLoadingContext = false; return }
        Task {
            do {
                let r = try await web.contextTracks(contextURI: uri)
                self.contextName = r.name
                self.contextTracks = r.tracks
                self.contextComplete = true
                self.contextTotal = r.tracks.count
                self.listedContextURI = uri
            } catch {
                self.contextTracks = []
            }
            self.isLoadingContext = false
        }
    }

    func connect() async {
        do {
            try await auth.authorize()
            engine.startIfNeeded()
            self.myUserID = try? await web.currentUserID()
            await loadPlaylists(force: true)
            await sync.runFullSync()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        auth.signOut()
        playlists = []
        playlistsFromCache = false
        playlistsUpdatedAt = nil
        searchResults = SpotifySearchResults()
        Task { await store.clear() }
    }

    private var playlistsLoadedAt: Date = .distantPast

    func loadPlaylists(force: Bool = false) async {
        // Always show the cached list first so the UI is never empty.
        if playlists.isEmpty {
            let cached = await store.playlists
            if !cached.isEmpty {
                playlists = cached
                playlistsFromCache = true
                playlistsUpdatedAt = await store.playlistsUpdatedAt
            }
        }

        guard auth.isAuthorized, !web.isRateLimited else { return }
        if !force, !playlistsFromCache, !playlists.isEmpty,
           Date().timeIntervalSince(playlistsLoadedAt) < 60 { return }

        do {
            let fresh = try await web.currentUserPlaylists()
            playlists = fresh
            playlistsFromCache = false
            playlistsLoadedAt = .now
            playlistsUpdatedAt = .now
            await store.putPlaylists(fresh)
        } catch {
            // Keep whatever cache we already showed.
            if playlists.isEmpty { lastError = error.localizedDescription }
        }
    }

    func likeCurrent() async {
        guard auth.isAuthorized else { lastError = "Connect Spotify in Settings to save songs."; return }
        do {
            if let id = nowPlaying?.trackID {
                try await web.saveTrack(id: id)
            } else {
                try await web.likeCurrentTrack()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
