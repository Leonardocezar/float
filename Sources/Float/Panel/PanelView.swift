import SwiftUI
import AppKit

enum PanelTab: String, CaseIterable, Identifiable {
    case timer = "Timer"
    case tasks = "Tasks"
    case stats = "Stats"
    var id: String { rawValue }
}

struct PanelView: View {
    @EnvironmentObject private var spotify: SpotifyModel
    @EnvironmentObject private var panelState: PanelState

    var body: some View {
        HStack(spacing: 0) {
            if !panelState.isCompact && panelState.isSettingsDrawerOpen {
                SettingsDrawerView()
                    .frame(width: PanelState.settingsDrawerWidth)
                    .transition(.move(edge: .leading))
                Divider()
            }

            mainColumn
                .frame(width: panelState.isCompact ? nil : PanelState.expandedSize.width)
                .frame(maxWidth: panelState.isCompact ? .infinity : nil, maxHeight: .infinity)
                .overlay(alignment: .trailing) {
                    if !panelState.isCompact {
                        DrawerHandle().padding(.bottom, 30)
                    }
                }
                .overlay(alignment: .leading) {
                    if !panelState.isCompact {
                        SettingsHandle().padding(.bottom, 30)
                    }
                }

            if !panelState.isCompact && panelState.isDrawerOpen {
                Divider()
                SpotifyDrawerNavigationView()
                    .frame(width: PanelState.drawerWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
        .onAppear { spotify.start() }
    }

    private var mainColumn: some View {
        ZStack(alignment: .bottom) {
            Group {
                if panelState.isCompact { CompactPanelView() }
                else { ExpandedPanelView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PlayerWebView(webView: spotify.engine.webView)
                .frame(height: spotify.needsActivation ? 30 : 0)
                .padding(.horizontal, spotify.needsActivation ? 8 : 0)
                .padding(.bottom, spotify.needsActivation ? 8 : 0)
                .opacity(spotify.needsActivation ? 1 : 0)
                .allowsHitTesting(spotify.needsActivation)
        }
    }
}

struct MenuBarPreviewView: View {
    var body: some View {
        HStack(spacing: 0) {
            CompactPomodoroView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 6)

            Divider().padding(.vertical, 8)

            CompactSpotifyView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 6)
        }
        .padding(.vertical, 8)
        .frame(width: PanelState.compactSize.width, height: PanelState.compactSize.height)
        .background(.ultraThinMaterial)
    }
}

struct MinimizeButton: View {
    @EnvironmentObject private var panelState: PanelState

    var body: some View {
        Button {
            panelState.minimizeToMenuBar()
        } label: {
            Image(systemName: "minus.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .help("Minimize to menu bar")
    }
}

struct QuitButton: View {
    var body: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .help("Quit Float")
    }
}

struct LayoutToggleButton: View {
    @EnvironmentObject private var panelState: PanelState

    var body: some View {
        Button {
            panelState.toggleCompact()
        } label: {
            Image(systemName: panelState.isCompact
                  ? "arrow.up.left.and.arrow.down.right"
                  : "arrow.down.right.and.arrow.up.left")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(panelState.isCompact ? "Expand" : "Compact view")
    }
}

private struct DrawerHandle: View {
    @EnvironmentObject private var panelState: PanelState

    var body: some View {
        EdgeTab(
            systemImage: panelState.isDrawerOpen ? "chevron.right" : "chevron.left",
            edge: .trailing,
            help: panelState.isDrawerOpen ? "Hide playlist" : "Show playlist"
        ) { panelState.toggleDrawer() }
        .scaleEffect(x: -1, y: 1)
    }
}

private struct SettingsHandle: View {
    @EnvironmentObject private var panelState: PanelState

    var body: some View {
        EdgeTab(
            systemImage: panelState.isSettingsDrawerOpen ? "chevron.left" : "chevron.right",
            edge: .leading,
            help: panelState.isSettingsDrawerOpen ? "Hide settings" : "Settings"
        ) { panelState.toggleSettingsDrawer() }
        .scaleEffect(x: -1, y: 1)
    }
}

private struct EdgeTab: View {
    let systemImage: String
    let edge: HorizontalEdge
    let help: String
    let action: () -> Void

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: edge == .leading ? 8 : 0,
            bottomLeadingRadius: edge == .leading ? 8 : 0,
            bottomTrailingRadius: edge == .trailing ? 8 : 0,
            topTrailingRadius: edge == .trailing ? 8 : 0
        )
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 46)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ExpandedPanelView: View {
    @EnvironmentObject private var spotify: SpotifyModel
    @State private var tab: PanelTab = .timer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                QuitButton()
                MinimizeButton()
                Text("Float")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                LayoutToggleButton()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Picker("", selection: $tab) {
                ForEach(PanelTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Group {
                switch tab {
                case .timer: TimerView()
                case .tasks: TaskListView()
                case .stats: StatsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            NowPlayingView().padding(12)
        }
    }
}

private struct CompactPanelView: View {
    var body: some View {
        HStack(spacing: 0) {
            CompactPomodoroView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 6)

            Divider().padding(.vertical, 8)

            CompactSpotifyView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 6)
        }
        .overlay(alignment: .topTrailing) {
            LayoutToggleButton()
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .padding(.top, 7)
                .padding(.trailing, 8)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                QuitButton()
                MinimizeButton()
            }
            .font(.system(size: 8))
            .padding(.top, 7)
            .padding(.leading, 8)
        }
    }
}

private struct CompactPomodoroView: View {
    @EnvironmentObject private var engine: PomodoroEngine

    var body: some View {
        VStack(spacing: 3) {
            Text(engine.phase.title.uppercased())
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(engine.phase.isBreak ? Color.teal : Color.accentColor)

            Text(timeString)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()

            ProgressView(value: progress)
                .tint(engine.phase.isBreak ? Color.teal : Color.accentColor)
                .scaleEffect(y: 0.55)
                .frame(maxWidth: 78)

            HStack(spacing: 12) {
                Button { engine.toggle() } label: {
                    Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
                }
                .foregroundStyle(Color.accentColor)
                Button { engine.skip() } label: { Image(systemName: "forward.end.fill") }
                    .foregroundStyle(.secondary)
                    .disabled(engine.phase == .idle)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
        }
    }

    private var progress: Double {
        let total = engine.config.duration(for: engine.phase == .idle ? .work : engine.phase)
        guard total > 0 else { return 0 }
        return 1 - engine.remaining / total
    }

    private var timeString: String {
        let s = Int(engine.remaining.rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

private struct CompactSpotifyView: View {
    @EnvironmentObject private var spotify: SpotifyModel

    var body: some View {
        VStack(spacing: 4) {
            if let np = spotify.nowPlaying {
                AsyncImage(url: np.artworkURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Rectangle().fill(.quaternary) }
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(np.title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 13) {
                    Button { spotify.previous() } label: { Image(systemName: "backward.fill") }
                    Button { spotify.playPause() } label: {
                        Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                    }
                    Button { spotify.next() } label: { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            } else {
                Image(systemName: "music.note").font(.system(size: 13)).foregroundStyle(.secondary)
                Text(statusText)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if spotify.isAuthorized && spotify.isPlayerReady {
                    Button("Play") { spotify.resume() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var statusText: String {
        if !spotify.isAuthorized { return "Connect in\nSettings" }
        if spotify.needsActivation { return "Enable audio\nbelow" }
        if !spotify.isPlayerReady { return "Starting…" }
        return "Nothing\nplaying"
    }
}
