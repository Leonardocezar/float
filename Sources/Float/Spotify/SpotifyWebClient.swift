import Foundation

struct SpotifyPlaylist: Identifiable, Equatable, Hashable, Codable {
    var id: String
    var name: String
    var uri: String
    var ownerID: String? = nil
    var collaborative: Bool = false
    var imageURL: URL? = nil
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
    var artworkURL: URL? = nil
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
    var imageURL: URL? = nil
}

struct SpotifyArtist: Identifiable, Equatable, Hashable, Codable {
    var id: String
    var name: String
    var uri: String
    var imageURL: URL? = nil
    var genres: [String] = []
    var followers: Int? = nil
}

struct SpotifySearchResults: Equatable {
    var tracks: [SpotifyTrack] = []
    var playlists: [SpotifyBrowseItem] = []
    var albums: [SpotifyBrowseItem] = []
    var artists: [SpotifyArtist] = []
    var isEmpty: Bool { tracks.isEmpty && playlists.isEmpty && albums.isEmpty && artists.isEmpty }
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
                collaborative: item["collaborative"] as? Bool ?? false,
                imageURL: Self.thumbnail(item["images"] as? [[String: Any]])
            )
        }
    }

    func search(_ query: String, limit: Int = 10) async throws -> SpotifySearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SpotifySearchResults() }
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        var path = "search?q=\(q)&type=track,playlist,album,artist&limit=\(min(limit, 10))"
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
        if let items = (json["artists"] as? [String: Any])?["items"] as? [[String: Any]] {
            r.artists = items.compactMap { Self.artist(from: $0) }
        }
        return r
    }

    static func artist(from obj: [String: Any]?) -> SpotifyArtist? {
        guard let obj,
              let id = obj["id"] as? String,
              let name = obj["name"] as? String,
              let uri = obj["uri"] as? String else { return nil }
        return SpotifyArtist(
            id: id, name: name, uri: uri,
            imageURL: Self.largestImage(obj["images"] as? [[String: Any]]),
            genres: obj["genres"] as? [String] ?? [],
            followers: (obj["followers"] as? [String: Any])?["total"] as? Int
        )
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
            collaborative: obj["collaborative"] as? Bool ?? false,
            imageURL: Self.thumbnail(obj["images"] as? [[String: Any]])
        )
    }

    /// Picks the smallest image Spotify offers — plenty for a drawer row.
    private static func thumbnail(_ images: [[String: Any]]?) -> URL? {
        guard let images, !images.isEmpty else { return nil }
        let smallestFirst = images.sorted {
            (($0["width"] as? Int) ?? .max) < (($1["width"] as? Int) ?? .max)
        }
        guard let urlString = smallestFirst.first?["url"] as? String else { return nil }
        return URL(string: urlString)
    }

    /// Picks the largest image Spotify offers — for a bigger, non-drawer-row preview.
    private static func largestImage(_ images: [[String: Any]]?) -> URL? {
        guard let images, !images.isEmpty else { return nil }
        let largestFirst = images.sorted {
            (($0["width"] as? Int) ?? 0) > (($1["width"] as? Int) ?? 0)
        }
        guard let urlString = largestFirst.first?["url"] as? String else { return nil }
        return URL(string: urlString)
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

    struct PlaylistHeader { var name: String; var total: Int }

    /// Cheap check: the playlist's name and current track count, without
    /// paging through its tracks. One request when the API returns
    /// `tracks.total` inline, two otherwise.
    func playlistHeader(id: String) async throws -> PlaylistHeader {
        let json = try await get("playlists/\(id)?fields=name,tracks.total")
        let name = json["name"] as? String ?? "Playlist"
        if let total = (json["tracks"] as? [String: Any])?["total"] as? Int {
            return PlaylistHeader(name: name, total: total)
        }
        let countJson = try await get("playlists/\(id)/items?limit=1&fields=total")
        return PlaylistHeader(name: name, total: countJson["total"] as? Int ?? 0)
    }

    struct PlaylistDetails: Equatable {
        var name: String
        var description: String?
        var ownerName: String?
        var followers: Int?
        var total: Int
        var imageURL: URL?
        var isPublic: Bool?
        var collaborative: Bool
    }

    /// Metadata only — works for any playlist, owned or not. Only the track
    /// listing itself (`playlistPage`) is restricted to owner/collaborator.
    func playlistDetails(id: String) async throws -> PlaylistDetails {
        let json = try await get("playlists/\(id)?fields=name,description,owner(display_name),followers.total,images,public,collaborative,tracks.total")
        let owner = json["owner"] as? [String: Any]
        let description = (json["description"] as? String)
            .map(Self.decodeHTMLEntities)
            .flatMap { $0.isEmpty ? nil : $0 }
        return PlaylistDetails(
            name: json["name"] as? String ?? "Playlist",
            description: description,
            ownerName: owner?["display_name"] as? String,
            followers: (json["followers"] as? [String: Any])?["total"] as? Int,
            total: (json["tracks"] as? [String: Any])?["total"] as? Int ?? 0,
            imageURL: Self.largestImage(json["images"] as? [[String: Any]]),
            isPublic: json["public"] as? Bool,
            collaborative: json["collaborative"] as? Bool ?? false
        )
    }

    /// Playlist descriptions come back with HTML entities and the occasional
    /// `<a href="…">` mention link — strip both for plain-text display.
    private static func decodeHTMLEntities(_ s: String) -> String {
        var result = s
        for (entity, replacement) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">"] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        while let range = result.range(of: "<[^>]+>", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let albumArt = Self.thumbnail(json["images"] as? [[String: Any]])
        let items = (json["tracks"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
        let tracks = items.compactMap { item -> SpotifyTrack? in
            guard var track = Self.track(from: item) else { return nil }
            // Album track items don't nest their own `album` object.
            if track.artworkURL == nil { track.artworkURL = albumArt }
            return track
        }
        return SpotifyContextTracks(name: name, tracks: tracks)
    }

    /// `GET /artists/{id}`, `/artists/{id}/albums` and `/artists/{id}/top-tracks`
    /// were all removed for Development Mode apps in Spotify's February 2026
    /// API changes — permanently 403 for a personal, non-extended-quota app
    /// like this one. `/search` is not on that list, so an artist's albums and
    /// tracks are approximated with a scoped `artist:"…"` search instead.
    func searchAlbumsByArtist(_ artistName: String, limit: Int = 10) async throws -> [SpotifyBrowseItem] {
        let raw = "artist:\"\(artistName)\""
        let q = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
        var path = "search?q=\(q)&type=album&limit=\(min(limit, 10))"
        if let market = try? await currentUserCountry() { path += "&market=\(market)" }
        let json = try await get(path)
        let items = (json["albums"] as? [String: Any])?["items"] as? [Any] ?? []
        var seenNames = Set<String>()
        var out: [SpotifyBrowseItem] = []
        for entry in items {
            guard let album = Self.browseItem(entry as? [String: Any], kind: .album) else { continue }
            // Spotify often lists the same album multiple times (regional
            // re-releases, deluxe/remaster duplicates) — keep the first.
            guard seenNames.insert(album.name.lowercased()).inserted else { continue }
            out.append(album)
        }
        return out
    }

    func searchTracksByArtist(_ artistName: String, limit: Int = 10) async throws -> [SpotifyTrack] {
        let raw = "artist:\"\(artistName)\""
        let q = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
        var path = "search?q=\(q)&type=track&limit=\(min(limit, 10))"
        if let market = try? await currentUserCountry() { path += "&market=\(market)" }
        let json = try await get(path)
        let items = (json["tracks"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
        return items.compactMap { Self.track(from: $0) }
    }

    struct FollowedArtistsPage { var artists: [SpotifyArtist]; var nextAfter: String? }

    /// Cursor-paginated, unlike everything else here (Spotify's `/me/following`
    /// has no `offset`) — walk `cursors.after` until it stops appearing.
    func followedArtists(after: String? = nil, limit: Int = 50) async throws -> FollowedArtistsPage {
        var path = "me/following?type=artist&limit=\(min(limit, 50))"
        if let after { path += "&after=\(after)" }
        let json = try await get(path)
        let artists = json["artists"] as? [String: Any] ?? [:]
        let items = artists["items"] as? [[String: Any]] ?? []
        let cursors = artists["cursors"] as? [String: Any]
        return FollowedArtistsPage(
            artists: items.compactMap { Self.artist(from: $0) },
            nextAfter: cursors?["after"] as? String
        )
    }

    func allFollowedArtists(max: Int = 500) async throws -> [SpotifyArtist] {
        var out: [SpotifyArtist] = []
        var after: String?
        while out.count < max {
            let page = try await followedArtists(after: after)
            out += page.artists
            guard let next = page.nextAfter, !page.artists.isEmpty else { break }
            after = next
        }
        return out
    }

    func followArtist(id: String) async throws {
        _ = try await send("PUT", "me/following?type=artist&ids=\(id)", json: nil)
    }

    func unfollowArtist(id: String) async throws {
        _ = try await send("DELETE", "me/following?type=artist&ids=\(id)", json: nil)
    }

    private static func track(from obj: [String: Any]?) -> SpotifyTrack? {
        guard let obj,
              let id = obj["id"] as? String,
              let uri = obj["uri"] as? String,
              let name = obj["name"] as? String else { return nil }
        let artist = (obj["artists"] as? [[String: Any]])?
            .compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
        let album = obj["album"] as? [String: Any]
        return SpotifyTrack(id: id, uri: uri, name: name, artist: artist,
                            durationMs: obj["duration_ms"] as? Double ?? 0,
                            artworkURL: Self.thumbnail(album?["images"] as? [[String: Any]]))
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
            let wait = min(max(retry, 1), 120) + 1
            backoffUntil = Date().addingTimeInterval(wait)
            throw WebError.rateLimited(wait)
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
