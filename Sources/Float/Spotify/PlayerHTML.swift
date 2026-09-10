import Foundation

enum PlayerHTML {
    static let deviceName = "Float"

    static let source = """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        html, body { margin: 0; height: 100%;
          font: 13px -apple-system, system-ui, sans-serif;
          background: transparent; color: #888;
          display: flex; align-items: center; justify-content: center; }
        #activate { appearance: none; border: 0; border-radius: 8px;
          padding: 8px 14px; font: inherit; font-weight: 600;
          background: #1ed760; color: #06210f; cursor: pointer; }
        #activate[hidden] { display: none; }
      </style>
    </head>
    <body>
      <button id="activate">Enable audio playback</button>
      <script src="https://sdk.scdn.co/spotify-player.js"></script>
      <script>
        function send(name, body) {
          try { window.webkit.messageHandlers[name].postMessage(body); } catch (e) {}
        }

        window.onSpotifyWebPlaybackSDKReady = () => {
          const player = new Spotify.Player({
            name: "\(deviceName)",
            volume: 0.8,
            getOAuthToken: (cb) => {
              window.webkit.messageHandlers.needToken.postMessage(null)
                .then((t) => cb(t))
                .catch(() => send("log", "token request failed"));
            }
          });
          window._player = player;

          player.addListener("ready", ({ device_id }) => send("ready", device_id));
          player.addListener("not_ready", ({ device_id }) => send("notReady", device_id));
          player.addListener("player_state_changed", (state) => {
            send("state", state ? JSON.stringify(state) : null);
          });
          player.addListener("autoplay_failed", () => send("log", "autoplay failed - needs activation"));
          ["initialization_error", "authentication_error", "account_error", "playback_error"]
            .forEach((evt) => player.addListener(evt, ({ message }) => send("log", evt + ": " + message)));

          player.connect().then((ok) => send("log", "connect: " + ok));

          document.getElementById("activate").addEventListener("click", () => {
            player.activateElement();
            send("activated", null);
          });
        };

        // Callable from Swift via evaluateJavaScript.
        window.floatToggle   = () => window._player && window._player.togglePlay();
        window.floatNext     = () => window._player && window._player.nextTrack();
        window.floatPrev     = () => window._player && window._player.previousTrack();
        window.floatSeek     = (ms) => window._player && window._player.seek(ms);
        window.floatVolume   = (v) => window._player && window._player.setVolume(v);
        window.floatActivate = () => { if (window._player) { window._player.activateElement(); send("activated", null); } };
        window.floatHideButton = () => { document.getElementById("activate").hidden = true; };
      </script>
    </body>
    </html>
    """
}
