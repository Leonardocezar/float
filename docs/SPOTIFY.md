# Spotify integration

Two independent halves that meet in `SpotifyModel`:

1. **Playback** — the Web Playback SDK in a hidden `WKWebView`. Float *is* the
   audio device. Needs Premium.
2. **Data** — the Web API (`SpotifyWebClient`) for search, playlists, queue,
   playlist edits, and the authoritative playback context.

## Setup a user must do

1. Create an app at <https://developer.spotify.com/dashboard>.
2. Redirect URI (exact): `http://127.0.0.1:8888/callback`.
3. Enable the **Web Playback SDK** for the app.
4. Paste the **Client ID** into Settings → Spotify → Connect.
5. Authorize in the browser; tokens land in the Keychain.

No client secret (PKCE). Development-mode apps: **max 5 users**, low rate limit,
owner needs Premium.

## Auth — `SpotifyAuth`

Authorization Code + PKCE.

- `code_verifier`: 64 chars from `[A-Za-z0-9-._~]`.
- `code_challenge`: `base64url(SHA256(verifier))`, no padding.
- Redirect caught by `LoopbackServer` (one-shot `NWListener` on `127.0.0.1:8888`).
- Token exchange / refresh: `POST https://accounts.spotify.com/api/token`,
  `Content-Type: application/x-www-form-urlencoded`.
- Refresh may **not** return a new refresh token — keep the old one
  (`?? tokens.refreshToken`).
- `validAccessToken()` refreshes when < 30 s from expiry. The SDK's
  `getOAuthToken` callback and every `SpotifyWebClient` request go through it.
- Storage: one JSON blob in the Keychain, account `spotify-tokens`.

Scopes requested (`SpotifyAuth.scopes`):

```
streaming
user-read-email  user-read-private
user-read-playback-state  user-modify-playback-state  user-read-currently-playing
playlist-read-private  playlist-read-collaborative
playlist-modify-private  playlist-modify-public
user-library-read  user-library-modify
```

`user-read-private` is required for `/search`. Editing scopes were added later,
so a user who connected before that must **disconnect and reconnect** — playlist
add/create 403s otherwise, and `SpotifyModel.friendlyModifyError` says so.

## Playback — Web Playback SDK

`SpotifyPlaybackEngine` owns a hidden `WKWebView`.

- `LocalWebServer` serves `PlayerHTML.source` from `http://127.0.0.1:<random>`.
  Loopback is a "potentially trustworthy" origin, so the SDK's Encrypted Media
  Extensions work **without TLS**. `project.yml` sets
  `NSAppTransportSecurity.NSAllowsLocalNetworking = true` for this.
- `WKWebViewConfiguration.mediaTypesRequiringUserActionForPlayback = []`.
- Bridge (`window.webkit.messageHandlers`):
  - `ready` → `{device_id}`; engine stores it. Also auto-calls `floatActivate()`
    (works on macOS without a gesture; a visible "Enable audio playback" button
    in the page is the fallback — `needsActivation` drives showing the webview).
  - `player_state_changed` → JSON → `applyState` → `NowPlaying`.
  - `needToken` (reply handler) → `auth.validAccessToken()`.
- Native → JS via `evaluateJavaScript`: `floatToggle/Next/Prev/Seek/Volume/Activate`.
- **The SDK's `context.uri` is very often `null`.** Don't trust it; get the real
  context from `GET /me/player`. `NowPlaying.contextURI` is best-effort;
  `SpotifyModel.currentContextURI` falls back `api → sdk → albumURI`.
- The SDK device only appears in `/me/player` after playback has been transferred
  to it. `engine.play(contextURI:)` does `transferPlayback` then `play`.

## Web API — `SpotifyWebClient`

Base `https://api.spotify.com/v1/`. `send(method, path, json:)` handles auth,
JSON, and:

- **429** → read `Retry-After`, set `backoffUntil = now + min(retry,60) + 1`,
  throw `WebError.rateLimited`. While `isRateLimited`, every request throws
  immediately without hitting the network. All background work checks this.

Endpoints in use:

| call | endpoint | notes |
| --- | --- | --- |
| profile | `GET /me` | cached: user id + `country` (market) |
| playback | `GET /me/player` | authoritative context/track; `204` = nothing active |
| devices | `GET /me/player/devices` | |
| play | `PUT /me/player/play` | `{context_uri, offset:{uri}}` + `device_id` |
| queue | `POST /me/player/queue?uri=…&device_id=…` | no body; `204` |
| transfer | `PUT /me/player` | `{device_ids:[id], play}` |
| like | `PUT /me/tracks?ids=…` | |
| playlists | `GET /me/playlists?limit=50&offset=…` | paginated in `allUserPlaylists` |
| playlist header | `GET /playlists/{id}?fields=name,snapshot_id` | plain `GET /playlists/{id}` fallback |
| playlist items | `GET /playlists/{id}/items?limit=50&offset=…&additional_types=track&market=…` | see below |
| search | `GET /search?q=…&type=track,playlist,album&limit=10&market=…` | |
| add to playlist | `POST /playlists/{id}/items` | `{uris:[…]}` |
| create playlist | `POST /users/{id}/playlists` | `{name, public:false}` |

### Playlist-endpoint rules (learned the hard way)

- **`/playlists/{id}/tracks` is deprecated** → `/items`. The item is
  `items[].item` (fall back to `items[].track`).
- **`limit` max is 50** for playlist items. `100` silently returns nothing.
- **Paginate by the page size.** Stepping `offset` by 100 with `limit=50` skips
  every other page — the bug that made playlists look half-empty.
- **403 for playlists the user doesn't own or collaborate on.** Spotify policy.
  `SpotifyModel.canBrowse` / `isOwned` gate the drawer's drill-in;
  `PlaylistSyncService` only syncs owned/collaborative playlists; non-owned rows
  just play on tap.
- `market` matters for search/items — the user token supplies the country, but
  we pass it explicitly anyway.
- Search `limit` is capped at 10 by the schema (was 20 → 400).

## Local cache + sync job

`PlaylistStore` (`actor`) → `~/Library/Application Support/Float/playlist-cache.json`,
`{ [playlistID]: Entry }` where `Entry = { name, snapshotID, tracks[], total,
complete, updatedAt }`.

`PlaylistSyncService` (`@MainActor`):

- `startPeriodic()` — first run 6 s after launch, then every 20 min.
- `runFullSync()` — `GET /me` + `allUserPlaylists`, filter to owned/collaborative,
  `store.keepOnly` the current set, then for each (max 100): `syncPlaylist`.
- `syncPlaylist(id, force:)`:
  - skip if a complete entry was updated < 5 min ago (unless `force`)
  - `playlistHeader` → skip if `snapshot_id` unchanged and entry complete
  - otherwise page through `/items` (50 at a time, 280 ms gap), calling
    `store.put` after **each page** so the UI grows live
  - stop on `isRateLimited`
- `store.put` fires `onChange(id)` → `SpotifyModel.storeEntryChanged` updates
  `openedListTracks` / `contextTracks` and the "Syncing… X of Y" footer.

The drawer reads `store.entry(for:)` first — a cached playlist opens with **zero**
API calls. `disconnect()` clears the store.

## `SpotifyModel` responsibilities

- Transport: `playPause / next / previous / play / pause / seek` → engine.
- `play(uri:)` — start a context (playlist/album) on the Float device.
- `search`, `openList` (playlist → store+sync, album → `contextTracks`),
  `playDrawerTrack` / `playTrack(_:inContext:)`, `queue`, `addTrack(_:to:)`,
  `createPlaylist(named:addingTrack:)`.
- `syncPlaybackSnapshot` — throttled `GET /me/player` (≥ 8 s apart, 20 s poll
  while the drawer is open) to keep `apiContextURI` fresh.
- `notice` (transient success toast), `lastError` (shown in a red bar), both
  surfaced in the drawer.
