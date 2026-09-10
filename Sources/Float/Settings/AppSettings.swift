import Foundation
import Combine
import SwiftUI

enum BreakMusicBehavior: String, CaseIterable, Identifiable {
    case pause
    case keepPlaying
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pause: return "Pause music"
        case .keepPlaying: return "Keep playing"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    var onPomodoroConfigChange: ((PomodoroConfig) -> Void)?

    var pomodoro: PomodoroConfig {
        get {
            PomodoroConfig(
                workMinutes: int("pomodoro.work", 25),
                shortBreakMinutes: int("pomodoro.short", 5),
                longBreakMinutes: int("pomodoro.long", 15),
                sessionsBeforeLongBreak: int("pomodoro.cycle", 4),
                autoStartNext: bool("pomodoro.autostart", true)
            )
        }
        set {
            d.set(newValue.workMinutes, forKey: "pomodoro.work")
            d.set(newValue.shortBreakMinutes, forKey: "pomodoro.short")
            d.set(newValue.longBreakMinutes, forKey: "pomodoro.long")
            d.set(newValue.sessionsBeforeLongBreak, forKey: "pomodoro.cycle")
            d.set(newValue.autoStartNext, forKey: "pomodoro.autostart")
            objectWillChange.send()
            onPomodoroConfigChange?(newValue)
        }
    }

    var workMinutes: Int {
        get { pomodoro.workMinutes }
        set { var c = pomodoro; c.workMinutes = newValue; pomodoro = c }
    }
    var shortBreakMinutes: Int {
        get { pomodoro.shortBreakMinutes }
        set { var c = pomodoro; c.shortBreakMinutes = newValue; pomodoro = c }
    }
    var longBreakMinutes: Int {
        get { pomodoro.longBreakMinutes }
        set { var c = pomodoro; c.longBreakMinutes = newValue; pomodoro = c }
    }
    var sessionsBeforeLongBreak: Int {
        get { pomodoro.sessionsBeforeLongBreak }
        set { var c = pomodoro; c.sessionsBeforeLongBreak = newValue; pomodoro = c }
    }
    var autoStartNext: Bool {
        get { pomodoro.autoStartNext }
        set { var c = pomodoro; c.autoStartNext = newValue; pomodoro = c }
    }

    var playSound: Bool {
        get { bool("alert.sound", true) }
        set { d.set(newValue, forKey: "alert.sound"); objectWillChange.send() }
    }
    var showNotifications: Bool {
        get { bool("alert.notify", true) }
        set { d.set(newValue, forKey: "alert.notify"); objectWillChange.send() }
    }

    var syncMusic: Bool {
        get { bool("music.sync", false) }
        set { d.set(newValue, forKey: "music.sync"); objectWillChange.send() }
    }
    var breakBehavior: BreakMusicBehavior {
        get { BreakMusicBehavior(rawValue: d.string(forKey: "music.breakBehavior") ?? "") ?? .pause }
        set { d.set(newValue.rawValue, forKey: "music.breakBehavior"); objectWillChange.send() }
    }
    var spotifyClientID: String {
        get { d.string(forKey: "spotify.clientID") ?? "" }
        set { d.set(newValue, forKey: "spotify.clientID"); objectWillChange.send() }
    }

    func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }

    private func int(_ key: String, _ fallback: Int) -> Int {
        d.object(forKey: key) == nil ? fallback : d.integer(forKey: key)
    }
    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
    }
}
