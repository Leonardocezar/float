import AppKit
import CryptoKit

@MainActor
final class SpotifyAuth: ObservableObject {
    enum AuthError: LocalizedError {
        case missingClientID
        case denied(String)
        case tokenExchangeFailed
        var errorDescription: String? {
            switch self {
            case .missingClientID: return "Add your Spotify Client ID in Settings first."
            case .denied(let s): return "Spotify authorization was denied: \(s)"
            case .tokenExchangeFailed: return "Could not exchange the authorization code for a token."
            }
        }
    }

    static let redirectURI = "http://127.0.0.1:8888/callback"
    static let redirectPort: UInt16 = 8888
    static let scopes = [
        "streaming",
        "user-read-email",
        "user-read-private",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "playlist-read-private",
        "playlist-read-collaborative",
        "playlist-modify-private",
        "playlist-modify-public",
        "user-library-read",
        "user-library-modify",
        "user-follow-read",
        "user-follow-modify",
    ].joined(separator: " ")

    @Published private(set) var isAuthorized: Bool

    var clientID: String

    private let keychainAccount = "spotify-tokens"
    private var server: LoopbackServer?

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    init(clientID: String) {
        self.clientID = clientID
        self.isAuthorized = Keychain.get(account: "spotify-tokens") != nil
    }

    func signOut() {
        Keychain.delete(account: keychainAccount)
        isAuthorized = false
    }

    func authorize() async throws {
        guard !clientID.isEmpty else { throw AuthError.missingClientID }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(length: 16)

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
            .init(name: "scope", value: Self.scopes),
        ]

        let server = LoopbackServer(port: Self.redirectPort)
        self.server = server
        defer { self.server = nil }

        NSWorkspace.shared.open(comps.url!)
        let items = try await server.waitForRedirect()

        if let err = items["error"] { throw AuthError.denied(err) }
        guard items["state"] == state, let code = items["code"] else {
            throw AuthError.denied("state mismatch")
        }

        try await exchangeCode(code, verifier: verifier)
    }

    func validAccessToken() async throws -> String {
        guard var tokens = loadTokens() else { throw AuthError.tokenExchangeFailed }
        if tokens.expiresAt.timeIntervalSinceNow > 30 {
            return tokens.accessToken
        }
        tokens = try await refresh(tokens)
        return tokens.accessToken
    }

    private func exchangeCode(_ code: String, verifier: String) async throws {
        let body = Self.form([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ])
        let json = try await postToken(body)
        guard
            let access = json["access_token"] as? String,
            let refresh = json["refresh_token"] as? String,
            let expiresIn = json["expires_in"] as? Double
        else { throw AuthError.tokenExchangeFailed }

        save(Tokens(accessToken: access,
                    refreshToken: refresh,
                    expiresAt: Date().addingTimeInterval(expiresIn)))
        isAuthorized = true
    }

    private func refresh(_ tokens: Tokens) async throws -> Tokens {
        let body = Self.form([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
        ])
        let json = try await postToken(body)
        guard
            let access = json["access_token"] as? String,
            let expiresIn = json["expires_in"] as? Double
        else {
            signOut()
            throw AuthError.tokenExchangeFailed
        }
        let refreshed = Tokens(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String ?? tokens.refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
        save(refreshed)
        return refreshed
    }

    private func postToken(_ body: Data) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.tokenExchangeFailed
        }
        return json
    }

    private func loadTokens() -> Tokens? {
        guard let data = Keychain.get(account: keychainAccount) else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    private func save(_ tokens: Tokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        Keychain.set(data, account: keychainAccount)
    }

    private static func randomURLSafeString(length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded()
    }

    private static func form(_ params: [String: String]) -> Data {
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.percentEncodedQuery?.data(using: .utf8) ?? Data()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
