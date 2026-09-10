import Foundation

struct SpotifyPlaylist: Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var uri: String
    var ownerID: String? = nil
    var collaborative: Bool = false
}

struct SpotifyDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var isActive: Bool
}

struct SpotifyTrack: Identifiable, Equatable, Codable {
    var id: String
    var uri: String
    var name: String
    var artist: String
    var durationMs: Double
}

struct SpotifyContextTracks: Equatable {
    var name: String
    var tracks: [SpotifyTrack]
}

struct SpotifyBrowseItem: Identifiable, Equatable, Hashable {
    enum Kind: String { case playlist, album }
    var id: String
    var name: String
    var subtitle: String
    var uri: String
    var kind: Kind

    var ownerID: String?
    var collaborative: Bool = false
}

struct SpotifySearchResults: Equatable {
    var tracks: [SpotifyTrack] = []
    var playlists: [SpotifyBrowseItem] = []
    var albums: [SpotifyBrowseItem] = []
    var isEmpty: Bool { tracks.isEmpty && playlists.isEmpty && albums.isEmpty }
}

final class SpotifyWebClient {
    enum WebError: LocalizedError {
        case notAuthorized
        case rateLimited(TimeInterval)
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Connect Spotify in Settings first."
            case .rateLimited(let s): return "Spotify rate limit — retrying in \(Int(s.rounded()))s."
            case .http(let code, let msg): return "Spotify API error \(code): \(msg)"
            }
        }
    }

    private let auth: SpotifyAuth
    let store: PlaylistStore?
    private let base = URL(string: "https://api.spotify.com/v1/")!

    private var backoffUntil: Date?

    var isRateLimited: Bool {
        if let backoffUntil, Date() < backoffUntil { return true }
        return false
    }

    init(auth: SpotifyAuth, store: PlaylistStore? = nil) {
        self.auth = auth
        self.store = store
    }

    func currentUserPlaylists(limit: Int = 50) async throws -> [SpotifyPlaylist] {
        try await parsePlaylists(get("me/playlists?limit=\(limit)"))
    }

    func allUserPlaylists(max: Int = 200) async throws -> [SpotifyPlaylist] {
        var out: [SpotifyPlaylist] = []
        var offset = 0
        while out.count < max {
            let json = try await get("me/playlists?limit=50&offset=\(offset)")
            let page = parsePlaylists(json)
            out += page
            let next = json["next"]
            if page.isEmpty || next == nil || next is NSNull { break }
            offset += 50
        }
        return out
    }

    private func parsePlaylists(_ json: [String: Any]) -> [SpotifyPlaylist] {
        let items = json["items"] as? [Any] ?? []
        return items.compactMap { entry in
            guard let item = entry as? [String: Any],
                  let id = item["id"] as? String,
                  let name = item["name"] as? String,
                  let uri = item["uri"] as? String else { return nil }
            return SpotifyPlaylist(
                id: id, name: name, uri: uri,
                ownerID: (item["owner"] as? [String: Any])?["id"] as? String,
                collaborative: item["collaborative"] as? Bool ?? false
            )
        }
    }

    func search(_ query: String, limit: Int = 10) async throws -> SpotifySearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SpotifySearchResults() }
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        var path = "search?q=\(q)&type=track,playlist,album&limit=\(min(limit, 10))"
        if let market = try? await currentUserCountry() { path += "&market=\(market)" }
        let json = try await get(path)

        var r = SpotifySearchResults()
        if let items = (json["tracks"] as? [String: Any])?["items"] as? [[String: Any]] {
            r.tracks = items.compactMap { Self.track(from: $0) }
        }
        if let items = (json["playlists"] as? [String: Any])?["items"] as? [Any] {
            r.playlists = items.compactMap { Self.browseItem($0 as? [String: Any], kind: .playlist) }
        }
        if let items = (json["albums"] as? [String: Any])?["items"] as? [Any] {
            r.albums = items.compactMap { Self.browseItem($0 as? [String: Any], kind: .album) }
        }
        return r
    }

    static func browseItem(_ obj: [String: Any]?, kind: SpotifyBrowseItem.Kind) -> SpotifyBrowseItem? {
        guard let obj,
              let id = obj["id"] as? String,
              let name = obj["name"] as? String,
              let uri = obj["uri"] as? String else { return nil }
        let owner = obj["owner"] as? [String: Any]
        let subtitle: String
        switch kind {
        case .album:
            subtitle = (obj["artists"] as? [[String: Any]])?
                .compactMap { $0["name"] as? String }.joined(separator: ", ") ?? "Album"
        case .playlist:
            subtitle = (owner?["display_name"] as? String).map { "by \($0)" } ?? "Playlist"
        }
        return SpotifyBrowseItem(
            id: id, name: name, subtitle: subtitle, uri: uri, kind: kind,
            ownerID: owner?["id"] as? String,
            collaborative: obj["collaborative"] as? Bool ?? false
        )
    }

    private var cachedUserID: String?
    private var cachedCountry: String?

    func currentUserID() async throws -> String {
        if let cachedUserID { return cachedUserID }
        try await loadProfile()
        return cachedUserID ?? ""
    }

    func currentUserCountry() async throws -> String? {
        if let cachedCountry { return cachedCountry }
        try await loadProfile()
        return cachedCountry
    }

    private func loadProfile() async throws {
        let json = try await get("me")
        cachedUserID = json["id"] as? String ?? cachedUserID
        cachedCountry = json["country"] as? String ?? cachedCountry
    }

    func addTracks(_ uris: [String], toPlaylist playlistID: String) async throws {
        guard !uris.isEmpty else { return }

        _ = try await send("POST", "playlists/\(playlistID)/items", json: ["uris": uris])
    }

    func createPlaylist(name: String, isPublic: Bool = false) async throws -> SpotifyPlaylist {
        let uid = try await currentUserID()
        let json = try await send("POST", "users/\(uid)/playlists",
                                  json: ["name": name, "public": isPublic])
        return SpotifyPlaylist(
            id: json["id"] as? String ?? "",
            name: json["name"] as? String ?? name,
            uri: json["uri"] as? String ?? ""
        )
    }

    func addToQueue(uri: String, deviceID: String?) async throws {
        let u = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uri
        var path = "me/player/queue?uri=\(u)"
        if let deviceID { path += "&device_id=\(deviceID)" }
        _ = try await send("POST", path, json: nil)
    }

    struct PlaybackSnapshot: Equatable {
        var contextURI: String?
        var trackURI: String?
        var isPlaying: Bool
    }

    func currentPlayback() async throws -> PlaybackSnapshot? {
        let json = try await get("me/player")
        guard !json.isEmpty else { return nil }
        return PlaybackSnapshot(
            contextURI: (json["context"] as? [String: Any])?["uri"] as? String,
            trackURI: (json["item"] as? [String: Any])?["uri"] as? String,
            isPlaying: json["is_playing"] as? Bool ?? false
        )
    }

    func devices() async throws -> [SpotifyDevice] {
        let json = try await get("me/player/devices")
        let items = json["devices"] as? [[String: Any]] ?? []
        return items.compactMap { d in
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            return SpotifyDevice(id: id, name: name, isActive: d["is_active"] as? Bool ?? false)
        }
    }

    func play(contextURI: String?, offsetTrackURI: String? = nil, deviceID: String? = nil) async throws {
        var path = "me/player/play"
        if let deviceID { path += "?device_id=\(deviceID)" }
        var body: [String: Any] = [:]
        if let contextURI {
            if contextURI.contains(":track:") {
                body["uris"] = [contextURI]
            } else {
                body["context_uri"] = contextURI
            }
        }
        if let offsetTrackURI { body["offset"] = ["uri": offsetTrackURI] }
        _ = try await send("PUT", path, json: body.isEmpty ? nil : body)
    }

    struct URIRef { var kind: String; var id: String }

    static func parseContextURI(_ uri: String) -> URIRef? {
        let parts = uri.split(separator: ":").map(String.init)
        guard let idx = parts.firstIndex(where: { ["playlist", "album", "artist"].contains($0) }),
              idx + 1 < parts.count else { return nil }
        return URIRef(kind: parts[idx], id: parts[idx + 1])
    }

    func contextTracks(contextURI: String) async throws -> SpotifyContextTracks {
        guard let ref = Self.parseContextURI(contextURI) else {
            return SpotifyContextTracks(name: "", tracks: [])
        }
        switch ref.kind {
        case "album": return try await albumTracks(id: ref.id)
        default:      return SpotifyContextTracks(name: "", tracks: [])
        }
    }

    struct PlaylistHeader { var name: String; var snapshotID: String }

    func playlistHeader(id: String) async throws -> PlaylistHeader {
        let json: [String: Any]
        do { json = try await get("playlists/\(id)?fields=name,snapshot_id") }
        catch { json = try await get("playlists/\(id)") }
        return PlaylistHeader(name: json["name"] as? String ?? "Playlist",
                              snapshotID: json["snapshot_id"] as? String ?? "")
    }

    struct PlaylistPage { var tracks: [SpotifyTrack]; var total: Int; var hasMore: Bool }

    func playlistPage(id: String, offset: Int, limit: Int = 50) async throws -> PlaylistPage {
        var q = "playlists/\(id)/items?limit=\(min(limit, 50))&offset=\(offset)&additional_types=track"
        if let m = try? await currentUserCountry() { q += "&market=\(m)" }
        let page = try await get(q)
        let items = page["items"] as? [[String: Any]] ?? []
        let tracks = items.compactMap {
            Self.track(from: ($0["item"] ?? $0["track"]) as? [String: Any])
        }
        let next = page["next"]
        let hasMore = !(next == nil || next is NSNull) && !items.isEmpty
        return PlaylistPage(tracks: tracks,
                            total: page["total"] as? Int ?? 0,
                            hasMore: hasMore)
    }

    private func albumTracks(id: String) async throws -> SpotifyContextTracks {
        let json = try await get("albums/\(id)")
        let name = json["name"] as? String ?? "Album"
        let items = (json["tracks"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
        return SpotifyContextTracks(name: name, tracks: items.compactMap { Self.track(from: $0) })
    }

    private static func track(from obj: [String: Any]?) -> SpotifyTrack? {
        guard let obj,
              let id = obj["id"] as? String,
              let uri = obj["uri"] as? String,
              let name = obj["name"] as? String else { return nil }
        let artist = (obj["artists"] as? [[String: Any]])?
            .compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
        return SpotifyTrack(id: id, uri: uri, name: name, artist: artist,
                            durationMs: obj["duration_ms"] as? Double ?? 0)
    }

    func pause() async throws { _ = try await send("PUT", "me/player/pause", json: nil) }

    func transferPlayback(to deviceID: String, play: Bool = true) async throws {
        _ = try await send("PUT", "me/player", json: ["device_ids": [deviceID], "play": play])
    }

    func saveTrack(id: String) async throws {
        _ = try await send("PUT", "me/tracks?ids=\(id)", json: nil)
    }

    func likeCurrentTrack() async throws {
        let json = try await get("me/player/currently-playing")
        guard let item = json["item"] as? [String: Any], let id = item["id"] as? String else { return }
        try await saveTrack(id: id)
    }

    private func get(_ path: String) async throws -> [String: Any] {
        try await send("GET", path, json: nil)
    }

    @discardableResult
    private func send(_ method: String, _ path: String, json: [String: Any]?) async throws -> [String: Any] {
        if let backoffUntil, Date() < backoffUntil {
            throw WebError.rateLimited(backoffUntil.timeIntervalSinceNow)
        }

        let token = try await auth.validAccessToken()
        var req = URLRequest(url: URL(string: path, relativeTo: base)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0

        if code == 429 {
            let retry = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 10
            backoffUntil = Date().addingTimeInterval(min(retry, 60) + 1)
            throw WebError.rateLimited(retry)
        }
        guard (200..<300).contains(code) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(140) ?? ""
            throw WebError.http(code, "\(method) \(path) — \(snippet)")
        }
        backoffUntil = nil
        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
