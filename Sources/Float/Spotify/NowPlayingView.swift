import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var spotify: SpotifyModel

    var body: some View {
        VStack(spacing: 8) {
            if let np = spotify.nowPlaying {
                HStack(spacing: 10) {
                    artwork(np.artworkURL)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(np.title).font(.caption).bold().lineLimit(1)
                        Text(np.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task { await spotify.likeCurrent() }
                    } label: {
                        Image(systemName: "heart")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                ProgressView(value: np.fraction)
                    .tint(.secondary)

                HStack(spacing: 22) {
                    Button { spotify.previous() } label: { Image(systemName: "backward.fill") }
                    Button { spotify.playPause() } label: {
                        Image(systemName: np.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    Button { spotify.next() } label: { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if spotify.isAuthorized && spotify.isPlayerReady {
                        Button("Play") { spotify.resume() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var statusText: String {
        if !spotify.isAuthorized { return "Connect Spotify in Settings" }
        if spotify.needsActivation { return "Click “Enable audio playback” below" }
        if !spotify.isPlayerReady { return "Starting Float player…" }
        return "Nothing playing"
    }

    @ViewBuilder
    private func artwork(_ url: URL?) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
