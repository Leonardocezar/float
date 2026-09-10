# Float

A small always-on-top macOS panel that combines a Pomodoro timer (with tasks and
focus stats) and Spotify control.

- **Floating panel** — borderless `NSPanel` at floating window level, shows on all
  Spaces, drag from anywhere, remembers its position. Runs as a menu-bar-less
  agent (no Dock icon); open settings from the gear icon.
- **Pomodoro** — configurable focus / short / long break intervals, auto-cycling,
  notifications + sound, `🍅` session count.
- **Tasks** — SwiftData task list; tap a task to make it the "active" one that
  completed Pomodoros are credited to.
- **Stats** — today / this-week focus minutes, day streak, last-7-days chart.
- **Spotify (Web API + Web Playback SDK)** — Float registers itself as a Spotify
  Connect device via the Web Playback SDK running in a hidden `WKWebView`, so no
  other Spotify app needs to be open. Requires **Spotify Premium**. The Web API
  (OAuth PKCE) drives what to play, playlist pickers and "save to Liked Songs".
- **Music sync** — optionally start a focus playlist when a work interval begins
  and pause / switch on breaks.

## Requirements

- macOS 14+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build & run

```sh
xcodegen generate
open Float.xcodeproj      # then Run (⌘R)
# or headless:
xcodebuild -scheme Float -configuration Debug build
xcodebuild -scheme Float test
```

`Float.xcodeproj` is generated and git-ignored — edit `project.yml` instead.

On first launch macOS will ask for **Notifications** permission. The app is not
sandboxed.

## Spotify setup (required for music)

1. Create an app at <https://developer.spotify.com/dashboard>.
2. Add redirect URI: `http://127.0.0.1:8888/callback`.
3. Enable the **Web Playback SDK** for the app (Web API is on by default).
4. Copy the **Client ID** into Float → Settings → Music → Client ID, then
   **Connect Spotify** and authorize in the browser.
5. Back in the panel, click **Enable audio playback** once (a browser autoplay
   gate) — after that Float appears as a "Float" device in any Spotify client and
   plays audio itself.

Requires **Spotify Premium** (Web Playback SDK requirement). No client secret is
stored; OAuth tokens live in the Keychain. Scopes requested: `streaming`,
`user-read-email/private`, `user-read/modify-playback-state`,
`user-read-currently-playing`, `playlist-read-private`, `user-library-read/modify`.

### How playback works

- `Spotify/PlayerHTML.swift` is served by `LocalWebServer` from
  `http://127.0.0.1:<port>` (loopback = secure context, so the SDK's EME works
  without TLS) into a hidden `WKWebView` owned by `SpotifyPlaybackEngine`.
- Transport (play/pause/seek/next/volume) calls the SDK directly via
  `evaluateJavaScript`; picking a playlist/album calls the Web API
  `PUT /me/player/play` targeting Float's `device_id`.
- State comes back through `player_state_changed` → `window.webkit.messageHandlers`
  → `NowPlaying`; a 1 s timer interpolates the progress bar between events.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/Float/Pomodoro/` | `PomodoroEngine` state machine, config, SwiftData models |
| `Sources/Float/Stats/` | `StatsService` aggregation + chart view |
| `Sources/Float/Spotify/` | Web Playback SDK engine (`WKWebView`), local page server, Web API client, OAuth (PKCE), view model |
| `Sources/Float/Panel/` | `FloatingPanel` (`NSPanel`) + root `PanelView` |
| `Sources/Float/Settings/` | `AppSettings` + settings window |
| `Sources/Float/AppServices.swift` | composition root; wires engine → notifications / persistence / Spotify |
| `Tests/FloatTests/` | engine + stats unit tests |
# float
