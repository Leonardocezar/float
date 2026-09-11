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
user-follow-read  user-follow-modify
```

`user-read-private` is required for `/search`. Editing/follow scopes were added
later, so a user who connected before they existed must **disconnect and
reconnect** — playlist add/create and follow/unfollow 403 otherwise.
`SpotifyModel.friendlyModifyError` / `friendlyFollowError` say so.

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
| playlist header | `GET /playlists/{id}?fields=name,tracks.total` | `total`, not `snapshot_id`, drives re-sync |
| playlist details | `GET /playlists/{id}?fields=name,description,owner(display_name),followers.total,images,public,collaborative,tracks.total` | metadata only — works for playlists you don't own |
| playlist items | `GET /playlists/{id}/items?limit=50&offset=…&additional_types=track&market=…` | see below |
| search | `GET /search?q=…&type=track,playlist,album,artist&limit=10&market=…` | |
| add to playlist | `POST /playlists/{id}/items` | `{uris:[…]}` |
| create playlist | `POST /users/{id}/playlists` | `{name, public:false}` |
| artist's albums (approx.) | `GET /search?q=artist:"…"&type=album&limit=10&market=…` | `/artists/{id}/albums` is dev-mode-dead — see below |
| artist's tracks (approx.) | `GET /search?q=artist:"…"&type=track&limit=10&market=…` | `/artists/{id}/top-tracks` is dev-mode-dead — see below |
| followed artists | `GET /me/following?type=artist&limit=50&after=…` | **cursor**-paginated, not offset — see below |
| follow / unfollow artist | `PUT` / `DELETE /me/following?type=artist&ids=…` | no body |

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
- **`GET /playlists/{id}` itself has no ownership restriction** — only the
  nested track listing does. `playlistDetails` uses this to show a read-only
  preview (cover, description, owner, follower count) for playlists Float
  can't open, instead of just an error.
- **`/me/following` paginates by cursor (`cursors.after`), not `offset`** —
  the only cursor-paginated endpoint here. `allFollowedArtists` walks it until
  a page comes back without a next cursor.
- **`GET /artists/{id}/albums` and `GET /artists/{id}/top-tracks` are gone for
  Development Mode apps** (Spotify's February 2026 dev-mode changes — see
  their migration guide) — always **403**, permanently, for a personal app
  like this one; no scope or header fixes it. Same migration also stripped
  `popularity`/`followers` from artist payloads (`SpotifyArtist.followers` is
  `nil` more often than not now) and removed `GET /artists` batch, `GET
  /users/{id}`, and `GET /browse/*`. **`/search` was not on that list**, so
  `searchAlbumsByArtist` / `searchTracksByArtist` approximate the artist page
  with a scoped `artist:"…"` search instead of the dead endpoints. Before
  reaching for any new artist/browse endpoint, check whether it survived that
  migration first.
- **`openArtist` fetches albums, then tracks — never concurrently.** One
  request in flight at a time, per the Web API rate-limit guidance (lazy load,
  avoid bursts); a 250 ms gap sits between the two, same idea as the
  playlist-sync request gap.

## Local cache + manual sync

`PlaylistStore` (`actor`) → `~/Library/Application Support/Float/playlist-cache.json`,
`{ entries: { [playlistID]: Entry }, playlists: [SpotifyPlaylist], playlistsUpdatedAt }`
where `Entry = { name, tracks[], total, complete, updatedAt }`. `total` is the
playlist's track count as of the last check — that count, not `snapshot_id`, is
what decides whether a playlist needs re-fetching.

`PlaylistSyncService` (`@MainActor`) has **no background timer** — it only runs
when asked to: the Library tab's ↻ button, right after `connect()`, or opening
a single playlist/track (which syncs just that one).

- `runFullSync()` — `GET /me` + `allUserPlaylists`, caches the list
  (`store.putPlaylists`), filters to owned/collaborative, then calls
  `syncPlaylist` on each (max 100, 280 ms gap) and reports how many changed.
- `syncPlaylist(id, force:)`:
  - `playlistHeader` — one cheap request for `{name, total}` (a second request
    only if the API didn't inline `tracks.total`)
  - if `total` matches the cached entry and it's complete, **skip** — no paging
  - otherwise page through `/items` (50 at a time, 280 ms gap), calling
    `store.put` after **each page** so the UI grows live
  - stops early on `isRateLimited`; returns whether it actually re-synced
- `store.put`/`putPlaylists` fire `onChange(id)` → `SpotifyModel.storeEntryChanged`
  updates `openedListTracks` / `contextTracks` and the "Syncing… X of Y" footer.

The drawer reads the cache first — a cached playlist opens, and the Library list
renders, with **zero** API calls; `loadPlaylists`/`search` fall back to the cache
when the API is unreachable or rate-limited. `disconnect()` clears the store.

### Favorite artists

`FavoritesStore` (`actor`) mirrors `PlaylistStore` but for followed artists →
`~/Library/Application Support/Float/favorite-artists-cache.json`,
`{ artists: [SpotifyArtist], updatedAt }`.

Same manual-only philosophy as playlists, split across two calls on
`SpotifyModel`:

- `loadFavoriteArtistsFromCache()` — local-only, no network, called once from
  `start()` so the Library tab's Artists section is never empty on launch.
- `syncFavoriteArtists()` — the actual `GET /me/following` walk
  (`web.allFollowedArtists`), replacing the cache wholesale. **No timer** —
  bound only to the Artists section's ↻ button.
- `toggleFavoriteArtist` follows/unfollows optimistically (updates
  `favoriteArtists` and the cache immediately, rolls back on API failure) so
  the star in search results and the artist detail screen respond instantly.

Search's offline fallback also checks `favoritesStore.localSearch`, so a
favorited artist's name still resolves while offline/rate-limited.

## `SpotifyModel` responsibilities

- Transport: `playPause / next / previous / play / pause / seek` → engine.
- `play(uri:)` — start a context (playlist/album/artist) on the Float device.
- `search`, `openList` (playlist → store+sync, album → `contextTracks`),
  `openArtist` (profile + top tracks), `playDrawerTrack` / `playTrack(_:inContext:)`,
  `queue`, `addTrack(_:to:)`, `createPlaylist(named:addingTrack:)`,
  `toggleFavoriteArtist`.
- `syncPlaybackSnapshot` — throttled `GET /me/player` (≥ 8 s apart, 20 s poll
  while the drawer is open) to keep `apiContextURI` fresh.
- `notice` (transient success toast), `lastError` (shown in a red bar), both
  surfaced in the drawer.
