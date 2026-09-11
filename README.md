# Float

A small always-on-top macOS panel that combines a Pomodoro timer (with tasks and
focus stats) and Spotify control.

- **Floating panel** — borderless `NSPanel` at floating window level, shows on all
  Spaces, drag from anywhere, remembers its position. Runs as a menu-bar-less
  agent (no Dock icon); settings open in a drawer from the gear button.
- **Pomodoro** — configurable focus / short / long break intervals, auto-cycling,
  notifications + sound, 🍅 session count.
- **Tasks** — SwiftData task list; tap a task to make it the "active" one that
  completed pomodoros are credited to.
- **Stats** — today / this-week focus minutes, day streak, last-7-days chart.
- **Spotify** — Float registers itself as a Spotify Connect device via the Web
  Playback SDK in a hidden `WKWebView`, so no other Spotify app needs to be
  open (**Premium required**). A right-side drawer searches Spotify and browses
  your playlists; playlist track listings are cached locally (works offline /
  rate-limited) and refreshed on demand — only playlists whose track count
  changed are re-fetched.
- **Music sync** — optionally resume your music when a focus interval starts and
  pause (or keep playing) on breaks.

## Requirements

- macOS 14+, Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build & run

```sh
xcodegen generate
open Float.xcodeproj      # then Run (⌘R)

# headless
xcodebuild -project Float.xcodeproj -scheme Float -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Float.xcodeproj -scheme Float -destination 'platform=macOS' test
```

`Float.xcodeproj`, `Resources/Info.plist` and `Resources/Float.entitlements` are
generated from `project.yml` and git-ignored — edit `project.yml` and re-run
`xcodegen generate`.

On first launch macOS asks for **Notifications** permission. The app is not
sandboxed.

## Spotify setup (required for music)

1. Create an app at <https://developer.spotify.com/dashboard>.
2. Add redirect URI: `http://127.0.0.1:8888/callback`.
3. Enable the **Web Playback SDK** for the app.
4. Paste the **Client ID** into Float → Settings → Spotify, then **Connect** and
   authorize in the browser.

Requires **Spotify Premium**. No client secret is stored; OAuth tokens live in
the Keychain.

## Working on the code

- **`AGENTS.md`** — start here (build/test/run, conventions, gotchas). `CLAUDE.md`
  just imports it.
- **`docs/ARCHITECTURE.md`** — module map and data flow.
- **`docs/SPOTIFY.md`** — the Spotify integration in detail.
