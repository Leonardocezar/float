import SwiftUI
import AppKit

struct SettingsDrawerView: View {
    @EnvironmentObject private var panelState: PanelState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var spotify: SpotifyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Form {
                timerSection
                musicSection
                aboutSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Dracula.currentLine.opacity(0.3))
    }

    private var header: some View {
        HStack {
            Text("Settings").font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                panelState.isSettingsDrawerOpen = false
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var timerSection: some View {
        Section("Timer") {
            Stepper(value: settings.binding(\.workMinutes), in: 1...120) {
                Text("Focus  \(settings.workMinutes) min")
            }
            Stepper(value: settings.binding(\.shortBreakMinutes), in: 1...60) {
                Text("Short break  \(settings.shortBreakMinutes) min")
            }
            Stepper(value: settings.binding(\.longBreakMinutes), in: 1...60) {
                Text("Long break  \(settings.longBreakMinutes) min")
            }
            Stepper(value: settings.binding(\.sessionsBeforeLongBreak), in: 2...10) {
                Text("Long break after  \(settings.sessionsBeforeLongBreak)")
            }
            Toggle("Auto-start next", isOn: settings.binding(\.autoStartNext))
            Toggle("Sound on phase change", isOn: settings.binding(\.playSound))
            Toggle("Notifications", isOn: settings.binding(\.showNotifications))
        }
    }

    @ViewBuilder
    private var musicSection: some View {
        Section("Spotify") {
            if spotify.isAuthorized {
                HStack {
                    Label("Connected", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Dracula.green)
                    Spacer()
                    Button("Disconnect") { spotify.disconnect() }
                        .controlSize(.small)
                }
                LabeledContent("Player") {
                    if spotify.needsActivation {
                        Text("needs activation").foregroundStyle(Dracula.orange)
                    } else if spotify.isPlayerReady {
                        Text("ready").foregroundStyle(Dracula.green)
                    } else {
                        Text("starting…").foregroundStyle(.secondary)
                    }
                }
            } else {
                TextField("Client ID", text: settings.binding(\.spotifyClientID))
                Text("developer.spotify.com → redirect `\(SpotifyAuth.redirectURI)`. Playback needs Premium.")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("Connect Spotify") { Task { await spotify.connect() } }
                    .disabled(settings.spotifyClientID.isEmpty)
            }
        }

        Section("Pomodoro sync") {
            Toggle("Control Spotify in sessions", isOn: settings.binding(\.syncMusic))
            Picker("On breaks", selection: settings.binding(\.breakBehavior)) {
                ForEach(BreakMusicBehavior.allCases) { Text($0.label).tag($0) }
            }
            Text("Resumes your music when a focus interval starts.")
                .font(.caption2).foregroundStyle(.secondary)
        }

        if let err = spotify.lastError {
            Text(err).font(.caption2).foregroundStyle(Dracula.red)
        }
    }

    private var aboutSection: some View {
        Section {
            LaunchAtLoginToggle()
            LabeledContent("Version",
                           value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            Button("Quit Float") { NSApp.terminate(nil) }
        }
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var on = LaunchAtLogin.isEnabled
    var body: some View {
        Toggle("Launch at login", isOn: $on)
            .onChange(of: on) { _, v in LaunchAtLogin.set(v) }
    }
}
