import AppKit
import SwiftData
import UserNotifications
import Combine

@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let container: ModelContainer
    let settings = AppSettings()
    let panel = PanelState()
    let engine: PomodoroEngine
    let spotify: SpotifyModel

    @Published var activeTaskID: UUID?

    private var openSessionStart: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        do {
            container = try ModelContainer(for: TaskItem.self, PomodoroSession.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        engine = PomodoroEngine(config: settings.pomodoro)

        let auth = SpotifyAuth(clientID: settings.spotifyClientID)
        let store = PlaylistStore()
        let web = SpotifyWebClient(auth: auth, store: store)
        let sync = PlaylistSyncService(web: web, store: store, auth: auth)
        spotify = SpotifyModel(
            engine: SpotifyPlaybackEngine(auth: auth),
            web: web,
            auth: auth,
            store: store,
            sync: sync
        )

        settings.onPomodoroConfigChange = { [weak self] config in
            self?.engine.config = config
        }
        settings.objectWillChange
            .sink { [weak self] in
                guard let self else { return }
                self.spotify.auth.clientID = self.settings.spotifyClientID
            }
            .store(in: &cancellables)

        configureEngine()
        requestNotificationAuthorization()
    }

    private func configureEngine() {
        engine.onPhaseStart = { [weak self] phase in
            self?.handlePhaseStart(phase)
        }
        engine.onPhaseComplete = { [weak self] phase, start, end in
            self?.handlePhaseComplete(phase, start: start, end: end)
        }

        engine.onPause = { [weak self] in self?.pauseMusicIfSyncing() }
        engine.onReset = { [weak self] in self?.pauseMusicIfSyncing() }
        engine.onResume = { [weak self] phase in self?.resumeMusic(for: phase) }
    }

    private func handlePhaseStart(_ phase: PomodoroPhase) {
        if phase == .work { openSessionStart = engine.now() }
        notify(for: phase, starting: true)
        startMusic(for: phase)
    }

    private func handlePhaseComplete(_ phase: PomodoroPhase, start: Date, end: Date) {
        notify(for: phase, starting: false)

        guard phase == .work, end.timeIntervalSince(start) >= 60 else { return }
        let context = container.mainContext
        let session = PomodoroSession(startedAt: start, endedAt: end, phase: .work, taskID: activeTaskID)
        context.insert(session)

        if let id = activeTaskID,
           let task = try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first {
            task.completedPomodoros += 1
        }
        try? context.save()
    }

    private func startMusic(for phase: PomodoroPhase) {
        guard settings.syncMusic else { return }
        switch phase {
        case .work:
            spotify.play()
        case .shortBreak, .longBreak:
            switch settings.breakBehavior {
            case .pause: spotify.pause()
            case .keepPlaying: spotify.play()
            }
        case .idle:
            break
        }
    }

    private func resumeMusic(for phase: PomodoroPhase) {
        guard settings.syncMusic else { return }
        if phase.isBreak, settings.breakBehavior == .pause { return }
        spotify.play()
    }

    private func pauseMusicIfSyncing() {
        guard settings.syncMusic else { return }
        spotify.pause()
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(for phase: PomodoroPhase, starting: Bool) {
        if settings.playSound {
            NSSound(named: phase.isBreak ? "Submarine" : "Glass")?.play()
        }
        guard settings.showNotifications else { return }

        let content = UNMutableNotificationContent()
        if starting {
            content.title = phase.title
            content.body = phase == .work ? "Time to focus." : "Take a break."
        } else {
            content.title = "\(phase.title) complete"
            content.body = phase == .work ? "Nice work. Break time." : "Break over — back to it."
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
