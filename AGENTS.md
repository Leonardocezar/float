# Float — agent guide

Context for any LLM/agent working on this repo. Read this first, then
`docs/ARCHITECTURE.md` and `docs/SPOTIFY.md` as needed.

## What this is

A native **macOS** menu-bar-less agent app: a small, always-on-top floating
panel that combines a **Pomodoro timer** (with tasks and focus stats) and
**Spotify** control/browsing. Personal-use project, not sandboxed, not on the
App Store.

- Language: **Swift**, `SWIFT_VERSION = 5.0` (Swift 5 language mode, built with
  the Xcode 16 / Swift 6 toolchain — do not turn on Swift 6 strict concurrency).
- UI: **SwiftUI** for content, **AppKit** for the window (`NSPanel`).
- Min target: **macOS 14.0**. Dev machine is Intel (`x86_64`).
- Persistence: **SwiftData** (tasks + sessions), Keychain (Spotify tokens),
  a JSON file cache (playlist listings), `UserDefaults` (preferences, panel state).

## Build / test / run

The Xcode project is **generated** by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`. `Float.xcodeproj/`, `Resources/Info.plist` and
`Resources/Float.entitlements` are all git-ignored and regenerated.

```sh
brew install xcodegen              # once
xcodegen generate                  # after cloning or editing project.yml

xcodebuild -project Float.xcodeproj -scheme Float -configuration Debug \
  -destination 'platform=macOS' build

xcodebuild -project Float.xcodeproj -scheme Float \
  -destination 'platform=macOS' test
```

Always `xcodegen generate` after changing `project.yml`, adding/removing/renaming
source files, or changing entitlements/Info.plist keys.

`Scripts/make-dmg.sh` builds Release, ad-hoc signs and packages
`dist/Float-<version>.dmg` (not notarized — other Macs need right-click → Open
on first launch).

### Running the app for manual verification

There is no Dock icon and no menu bar, so normal automation is awkward.

```sh
APP=$(find ~/Library/Developer/Xcode/DerivedData/Float-*/Build/Products/Debug \
  -name Float.app -maxdepth 1 | head -1)
pkill -f "Float.app/Contents/MacOS/Float"; open "$APP"
```

To screenshot just the panel (works even when the rest of the screen can't be
captured), get its CoreGraphics window id and use `screencapture -l<id>`:

```swift
// swift script: print Float's on-screen window ids
import CoreGraphics; import Foundation
let opts = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
for w in (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String:Any]] ?? [])
where (w[kCGWindowOwnerName as String] as? String) == "Float" {
    print(w[kCGWindowNumber as String] as? Int ?? -1)
}
```

Panel layout/state can be forced for a screenshot via `defaults`:
`defaults write com.leonardocezar.Float panel.compact -bool true` (and
`panel.drawer`, `panel.settingsDrawer`). **`killall cfprefsd` after `defaults
write`** or the app may not see the change.

`cliclick` (`brew install cliclick`) moves the real cursor and is more reliable
than AppleScript for clicking SwiftUI controls, but coordinates shift when a
drawer opens/closes — read the window frame again between clicks.

## Testing reality

- Unit tests cover the pure logic only: `PomodoroEngine` (phase cycling,
  clock-jump math, callbacks) and `StatsService` (rollups, streak, buckets).
  Keep these green.
- There are **no UI tests** and **no Spotify tests** — the Spotify paths need a
  live Premium account, a registered app Client ID, and a granted OAuth session.
  Verify Spotify changes by running the app and reading the drawer / the
  `~/Library/Application Support/Float/playlist-cache.json` file.

## Architecture in one paragraph

`AppServices.shared` is the composition root (`@MainActor`, singleton). It owns
the SwiftData `ModelContainer`, `AppSettings`, `PanelState`, the `PomodoroEngine`
and the `SpotifyModel`, and wires the engine's phase callbacks to notifications,
SwiftData session logging and Spotify. `AppDelegate` builds one borderless
`FloatingPanel` (`NSPanel`) hosting `PanelView`. Everything the UI needs is
injected as `@EnvironmentObject`. See `docs/ARCHITECTURE.md`.

## Conventions

- **The codebase is comment-free by choice.** Doc comments were intentionally
  stripped; put narrative in these `.md` files. Match the surrounding style — no
  `//` unless a line genuinely needs a warning.
- Observable state objects are `@MainActor final class … : ObservableObject` with
  `@Published private(set)` and explicit mutation methods.
- Timers: `Timer(timeInterval:repeats:)` added to `RunLoop.main` in `.common`
  mode, body wrapped in `MainActor.assumeIsolated { }`.
- Networking returns typed models; raw `[String: Any]` JSON is parsed at the
  client boundary only (`SpotifyWebClient`), never leaked upward.
- No third-party Swift packages. System frameworks only (SwiftData, Swift Charts,
  WebKit, Network, ServiceManagement, UserNotifications, Security).

## Commit convention

`type: short summary` on the first line (`feat`, `fix`, `chore`, `refactor`,
`style`, `perf`, `docs`), blank line, then a wrapped body explaining the *why*.
**No AI/assistant references anywhere** — no `Co-Authored-By`, no "generated
with" trailers. Do not push; the maintainer reviews and pushes.

## High-value gotchas

- **Spotify dev-mode quota**: the app is in development mode → max 5 users, a
  low rate limit (rolling 30 s window), and the owner needs Premium. Extended
  quota is organizations-only since May 2025. Every added API call matters.
- **`GET /playlists/{id}/items` returns 403** for any playlist the user does not
  own or collaborate on (Spotify policy, 2024/2025). Gated by
  `SpotifyModel.canBrowse` / `isOwned`; non-owned playlists only play, never open.
- **`/playlists/{id}/tracks` is deprecated** → use `/items`. Playlist item
  `limit` max is **50** (100 silently returns nothing). Paginate by stepping
  `offset` by the page size, not a fixed 100.
- **Web Playback SDK** needs a secure-context origin for its DRM; the player page
  is served over `http://127.0.0.1:<port>` (loopback is "potentially trustworthy"
  so no TLS needed). It also needs `NSAllowsLocalNetworking` (set in `project.yml`).
- **429**: `SpotifyWebClient` sets `backoffUntil` from `Retry-After` and refuses
  requests until it clears (`isRateLimited`). Respect it in any new call site.
- After `defaults write com.leonardocezar.Float …`, run `killall cfprefsd`.
