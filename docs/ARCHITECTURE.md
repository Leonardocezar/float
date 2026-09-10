# Architecture

## Entry & composition

```
FloatApp (@main, SwiftUI App)
 ├─ Settings scene → a stub view (there is no real preferences window)
 └─ @NSApplicationDelegateAdaptor AppDelegate
      └─ applicationDidFinishLaunching:
           ├─ NSApp.setActivationPolicy(.accessory)     // no Dock icon
           ├─ AppServices.shared                        // build everything
           ├─ FloatingPanel(NSPanel) hosting PanelView
           │     .environmentObject(services / settings / engine / spotify / panel)
           │     .modelContainer(services.container)
           ├─ services.panel.applyLayout = { size, leftInset in … }   // window resize
           └─ services.spotify.start()
```

`AppServices` (`@MainActor`, `static let shared`) is the single owner of all
long-lived state:

| property | type | role |
| --- | --- | --- |
| `container` | `ModelContainer` | SwiftData store for `TaskItem`, `PomodoroSession` |
| `settings` | `AppSettings` | `UserDefaults`-backed preferences |
| `panel` | `PanelState` | compact/expanded + drawer open state, window sizing |
| `engine` | `PomodoroEngine` | the timer state machine |
| `spotify` | `SpotifyModel` | everything Spotify |
| `activeTaskID` | `UUID?` | which task completed pomodoros are credited to |

`AppServices.configureEngine()` connects the engine callbacks:

- `onPhaseStart(phase)` → notification + sound + `startMusic(phase)`
- `onPhaseComplete(phase, start, end)` → notification + insert a `PomodoroSession`
  (work phases ≥ 60 s only) + bump the active `TaskItem.completedPomodoros`
- `onPause` / `onReset` → `spotify.pause()` (if `settings.syncMusic`)
- `onResume(phase)` → resume music unless it's a break set to pause

## Modules

### `Pomodoro/`
- **`PomodoroConfig`** — durations + `sessionsBeforeLongBreak` + `autoStartNext`;
  `duration(for:)`.
- **`PomodoroEngine`** (`@MainActor ObservableObject`) — phases
  `idle / work / shortBreak / longBreak`. Countdown = `endDate.timeIntervalSince(now())`
  where `now` is an injectable `() -> Date` (tests swap it). `tick()` is called
  by a 1 s `RunLoop.main` timer *and* directly by tests. Publishes `phase`,
  `isRunning`, `remaining`, `completedWorkSessions`. Emits the callbacks listed
  above.
- **`PomodoroModels`** — `@Model TaskItem`, `@Model PomodoroSession` (stores
  `phaseRaw`, computed `minutes`).
- **`TimerView`** — circular progress ring, mm:ss, active-task label, controls.

### `Tasks/`
- **`TaskListView`** — `@Query(sort: \.order)` list; add / toggle done / delete /
  stepper for estimate; tap a row to set `AppServices.activeTaskID`.

### `Stats/`
- **`StatsService`** (pure enum) — `summary(from:)`, `streak(from:)`,
  `last7Days(from:)`; only `phase == .work` sessions count.
- **`StatsView`** — `@Query` sessions → tiles + Swift Charts bar chart.

### `Panel/`
- **`FloatingPanel<Content>`** — `NSPanel`, styleMask `[.borderless,
  .nonactivatingPanel]`, `level = .floating`, joins all Spaces,
  `isMovableByWindowBackground`. Persists only its top-left corner
  (`UserDefaults` key `panel.origin`). `canBecomeKey = true` so `TextField`s work.
- **`PanelState`** (`@MainActor ObservableObject`) — `isCompact`, `isDrawerOpen`
  (right / playlist), `isSettingsDrawerOpen` (left), all persisted. `size` and
  `leftInset` are derived; every setter calls `relayout()` →
  `applyLayout(size, leftInset)`, which `AppDelegate` uses to resize the window
  while keeping the *main column's* on-screen position fixed.
  Sizes: expanded `320×460`, compact `220×118`, drawers `+300` / `+280`.
- **`PanelView`** — root. `HStack { [settings drawer] | mainColumn | [playlist
  drawer] }`. `mainColumn` = compact or expanded layout in a `ZStack` with the
  always-mounted (usually zero-height) `PlayerWebView`. Also defines the edge
  "handle" tabs and the layout toggle buttons.

### `Settings/`
- **`AppSettings`** (`@MainActor ObservableObject`) — hand-rolled
  `UserDefaults` accessors (no `@AppStorage`). `pomodoro: PomodoroConfig` getter
  /setter fans out to individual keys and calls `onPomodoroConfigChange`.
  `binding(\.keyPath)` helper produces SwiftUI `Binding`s. Music-sync keys:
  `syncMusic`, `breakBehavior` (`pause` / `keepPlaying`).
- **`SettingsDrawerView`** — the left drawer: timer steppers, sound/notification
  toggles, Spotify connect + player status, sync toggle + break behavior, launch
  at login, version, Quit.

### `Spotify/`
See `docs/SPOTIFY.md` for the full picture. Files:

| file | role |
| --- | --- |
| `SpotifyAuth` | OAuth Authorization Code + PKCE, loopback redirect, Keychain tokens, refresh |
| `LoopbackServer` | one-shot `NWListener` that catches the OAuth redirect |
| `LocalWebServer` | persistent loopback HTTP server that serves the player page |
| `PlayerHTML` | the served HTML/JS: loads the Web Playback SDK, bridges events |
| `PlayerWebView` | `NSViewRepresentable` wrapper for the engine's `WKWebView` |
| `SpotifyPlaybackEngine` | owns the hidden `WKWebView`; JS↔native bridge; parses `player_state_changed` into `NowPlaying` |
| `NowPlaying` | value type; `interpolatedPosition(now:)` smooths the progress bar |
| `Keychain` | generic-password wrapper (service `com.leonardocezar.Float`) |
| `SpotifyWebClient` | Web API wrapper + 429 backoff; parses JSON to typed models |
| `PlaylistStore` | `actor`; on-disk JSON cache of playlist track listings |
| `PlaylistSyncService` | `@MainActor` background job that fills/refreshes the store |
| `SpotifyModel` | `@MainActor ObservableObject`; the facade the UI binds to |
| `NowPlayingView` | the now-playing bar |
| `SpotifyDrawerNavigationView` | the right drawer (Playing / Search / Library, playlist detail) |

## Data flow: "what's playing" → drawer

```
Web Playback SDK  ──player_state_changed──►  SpotifyPlaybackEngine.applyState
                                                   │ sets @Published nowPlaying
                                                   ▼
SpotifyModel (sinks engine.$nowPlaying)
   │ track changed? → syncPlaybackSnapshot(force:false)
   │      └─ GET /me/player  → apiContextURI / apiTrackURI   (SDK context is unreliable)
   │ reloadContextIfNeeded(currentContextURI)
   │      ├─ playlist → contextPlaylistID set; read PlaylistStore (instant);
   │      │             kick PlaylistSyncService.syncPlaylist(id)
   │      └─ album/artist → SpotifyWebClient.contextTracks (single request)
   ▼
@Published contextTracks / contextName / contextComplete / contextTotal
   ▼
SpotifyDrawerNavigationView "Playing" tab
```

`PlaylistStore.onChange(id)` → `SpotifyModel.storeEntryChanged(id)` re-applies the
entry to `contextTracks` / `openedListTracks` as the sync job pages through it,
so an open list grows live and shows a "Syncing… X of Y" footer until complete.

## Concurrency notes

- Everything user-facing is `@MainActor`.
- `PlaylistStore` is an `actor`; all access is `await`ed. Its `onChange` closure
  is `@Sendable` and hops back to `@MainActor` itself.
- `SpotifyWebClient` is a plain `final class` used from the main actor via `await`;
  it does no locking of its own.
- `Timer` callbacks: `MainActor.assumeIsolated { … }` inside the body.
