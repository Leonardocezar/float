import AppKit
import WebKit
import Combine

@MainActor
final class SpotifyPlaybackEngine: NSObject, ObservableObject {
    @Published private(set) var deviceID: String?
    @Published private(set) var nowPlaying: NowPlaying?

    @Published private(set) var isActivated = false
    @Published var lastLog: String?
    @Published var lastError: String?

    let webView: WKWebView

    private let auth: SpotifyAuth
    private let server: LocalWebServer
    private var started = false

    init(auth: SpotifyAuth) {
        self.auth = auth
        self.server = LocalWebServer(html: PlayerHTML.source)

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let controller = WKUserContentController()
        config.userContentController = controller

        self.webView = WKWebView(frame: .init(x: 0, y: 0, width: 240, height: 60), configuration: config)
        super.init()

        controller.add(self, name: "ready")
        controller.add(self, name: "notReady")
        controller.add(self, name: "state")
        controller.add(self, name: "log")
        controller.add(self, name: "activated")
        controller.addScriptMessageHandler(self, contentWorld: .page, name: "needToken")

        webView.underPageBackgroundColor = .clear
    }

    func startIfNeeded() {
        guard !started, auth.isAuthorized else { return }
        started = true
        Task {
            do {
                let url = try await server.start()
                webView.load(URLRequest(url: url))
            } catch {
                lastLog = "player host failed: \(error.localizedDescription)"
                started = false
            }
        }
    }

    func reload() {
        started = false
        deviceID = nil
        isActivated = false
        startIfNeeded()
    }

    func togglePlay() { evaluate("floatToggle()") }
    func next() { evaluate("floatNext()") }
    func previous() { evaluate("floatPrev()") }
    func seek(toMilliseconds ms: Double) { evaluate("floatSeek(\(Int(ms)))") }
    func setVolume(_ fraction: Double) { evaluate("floatVolume(\(min(1, max(0, fraction))))") }
    func activate() { evaluate("floatActivate()") }

    func play(contextURI: String, web: SpotifyWebClient) {
        guard let deviceID else { lastError = "Float player not ready yet — open Spotify settings and reconnect."; return }
        Task {
            do {
                if !isActivated { activate() }
                try await web.transferPlayback(to: deviceID, play: false)
                try await web.play(contextURI: contextURI, deviceID: deviceID)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func playTrack(uri trackURI: String, inContext contextURI: String, web: SpotifyWebClient) {
        guard let deviceID else { lastError = "Float player not ready yet — open Spotify settings and reconnect."; return }
        Task {
            do {
                if !isActivated { activate() }
                try await web.play(contextURI: contextURI, offsetTrackURI: trackURI, deviceID: deviceID)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func play(web: SpotifyWebClient) {
        if let np = nowPlaying {
            if !np.isPlaying { togglePlay() }
        } else if let deviceID {
            Task { try? await web.transferPlayback(to: deviceID, play: true) }
        }
    }

    func pause() {
        if nowPlaying?.isPlaying == true { togglePlay() }
    }

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    fileprivate func applyState(_ json: String?) {
        guard let json,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            nowPlaying = nil
            return
        }

        let paused = obj["paused"] as? Bool ?? true
        let position = obj["position"] as? Double ?? 0
        let duration = obj["duration"] as? Double ?? 0

        let window = obj["track_window"] as? [String: Any]
        let track = window?["current_track"] as? [String: Any]
        let artists = (track?["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let album = track?["album"] as? [String: Any]
        let images = album?["images"] as? [[String: Any]]
        let artURL = (images?.first?["url"] as? String).flatMap(URL.init(string:))
        let contextURI = (obj["context"] as? [String: Any])?["uri"] as? String

        nowPlaying = NowPlaying(
            title: track?["name"] as? String ?? "—",
            artist: artists.joined(separator: ", "),
            album: album?["name"] as? String ?? "",
            artworkURL: artURL,
            duration: duration,
            position: position,
            isPlaying: !paused,
            trackURI: track?["uri"] as? String,
            trackID: track?["id"] as? String,
            contextURI: contextURI,
            albumURI: album?["uri"] as? String,
            asOf: .now
        )
        if !paused { isActivated = true }
    }
}

extension SpotifyPlaybackEngine: WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    nonisolated func userContentController(_ controller: WKUserContentController,
                                          didReceive message: WKScriptMessage) {
        let name = message.name
        let body = message.body
        Task { @MainActor in
            switch name {
            case "ready":
                self.deviceID = body as? String
                self.lastLog = "device ready"

                self.webView.evaluateJavaScript("floatActivate()")
            case "notReady":
                self.deviceID = nil
            case "state":
                self.applyState(body as? String)
            case "activated":
                self.isActivated = true
                self.webView.evaluateJavaScript("floatHideButton()")
            case "log":
                self.lastLog = body as? String
            default:
                break
            }
        }
    }

    nonisolated func userContentController(_ controller: WKUserContentController,
                                          didReceive message: WKScriptMessage,
                                          replyHandler: @escaping (Any?, String?) -> Void) {
        Task { @MainActor in
            do {
                let token = try await self.auth.validAccessToken()
                replyHandler(token, nil)
            } catch {
                replyHandler(nil, error.localizedDescription)
            }
        }
    }
}
