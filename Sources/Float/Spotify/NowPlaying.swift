import Foundation

struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?

    var duration: Double

    var position: Double
    var isPlaying: Bool
    var trackURI: String?
    var trackID: String?

    var contextURI: String?

    var albumURI: String?

    var asOf: Date = .now

    func interpolatedPosition(now: Date = .now) -> Double {
        guard isPlaying else { return position }
        let elapsed = now.timeIntervalSince(asOf) * 1000
        return min(duration, position + elapsed)
    }

    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, interpolatedPosition() / duration))
    }
}
