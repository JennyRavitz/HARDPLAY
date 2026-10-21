# HARDPLAY Web

An English browser edition of the HARDPLAY stage player. The native Mac app and its audio library are kept separate.

## Use

1. Open the app once with a connection. Wait for **App saved** in the footer.
2. **+ → From Mac / Direct link / Google Drive / Dropbox**. Cloud files must be downloadable without signing in. Direct links require CORS permission from their server.
3. Wait for **Saved offline** on each track, or open the footer and choose **Download all cloud tracks**. A partially downloaded or unsupported file is never marked ready.
4. Keep this same browser/profile/device. Fully saved audio plays from IndexedDB blobs, without streaming from the cloud. The app shell opens through its service worker.
5. **Keep offline storage** requests persistent storage. The browser may decline. Clearing site data, private browsing, storage eviction, device loss and signing out of private hosting can affect availability. Before a live set, open the app and test your complete queue without a connection.

Install/add to Dock using the browser's own app-install menu when available. The app requires HTTPS, or localhost for development.

## Controls

- Off / Short 3 seconds / Long 6 seconds per outgoing track; **Apply to All** copies the current fade. Both tracks and their gains are shown during overlap.
- Restart, Resume, master volume, end-of-track stop and optional stop-before-end, shuffle/repeat.
- Pencil renames inline. Icons keep playlist rows compact.
- **My Set** toggles the docked playlist; the folder button opens Save/Open Playlist. The separate queue window shares the same player; its link button attaches it again. Keep the original app window open.
- Mini Player uses Document Picture-in-Picture where supported, with a compact-view fallback. Popup blockers may need allowing a playlist window. Web windows cannot reproduce every native Mac window behavior.
- Setup protection locks selected groups. The top lock protects all actions while music continues; drag the handle upwards or hold Space/Enter for about one second to unlock.
- Settings → Keyboard / MIDI, or Shift+M. Enable Map, choose an action/player button, then send a key or MIDI signal. Trigger runs an action once; Toggle switches its supported state. Save/Open control sets. MIDI CC controls continuous volume. MIDI support depends on browser/device permissions. Keyboard shortcuts require focus; they are not global macOS shortcuts.

## Storage and cloud boundaries

- Local audio is never uploaded. Cloud downloads stream through the browser; Drive/Dropbox use a restricted server proxy to avoid provider CORS limitations. The proxy stores no files and does not bypass sign-in, passwords, download restrictions or provider confirmation pages.
- Playlist JSON contains metadata, source links and settings, **not audio**. Signed links may contain access tokens: treat exported playlists as private. On another device, local files need re-adding and cloud files need downloading again.
- Browser codecs apply. An unsupported file is rejected with an explanation; this web edition cannot promise all native/FFmpeg formats.
- Up to 1 GB per file; larger files are rejected. Downloads must finish while the page is open. The app does not implement OAuth, private Drive/Dropbox account browsing, cloud uploading or cross-device library sync.
- Service worker updates wait until existing windows close, avoiding a forced reload during playback. Open once online after installing an update.

## Development

No third-party dependencies or global installs.

```
node scripts/build.mjs
node --test tests/*.test.mjs
node scripts/validate-artifact.mjs
node scripts/dev-server.mjs
```

Preview: http://localhost:4173 (PORT can override). `/qa/silence.wav` and `/qa/silence-two.wav` are 12-second generated silent WAV fixtures served **only by the dev server**. They are not deployed and contain no user audio.

Build embeds public assets in a self-contained Worker ESM. `dist/server/index.js` serves the app and allowlisted `/api/cloud` download route. `.openai/hosting.json` retains the private Site identity. Do not add cloud credentials to client files.

## Queue copies and track timing

- The two-sheet icon duplicates a queue item immediately after it. Press it again for more copies. Copies have separate names, saved positions, fades and playback limits. Downloaded audio is copied locally, without another network download; removing either item leaves the other playable. Each copy can use browser storage.
- The clock in each row shows its play duration. Click it to choose **Full track** or a time in `m:ss` / seconds, then **Save time**. The time is an end point measured from the start of that queue item, not an additional countdown on top of its Resume position. It cannot exceed the actual source length; duplicate a track to play it again.
- The queue summary includes copies and subtracts crossfade overlap. Stop mode shows audio total with manual stops; shuffle is an estimate; repeat has no fixed end. Items awaiting audio metadata are marked as pending duration.
- Time caps follow the existing Next/Stop end mode. Resume can hear the tail after a stop-before-end point, up to the configured time cap. Timing and copies are included in playlist JSON and survive reopening the app.

Single-click a queue title to select it without starting or switching playback. Use the separate play button to play (or pause the playing item). Right-click a row for Duplicate Track, Play, Rename and Timing. Global icon buttons choose Next / Auto Stop and Restart / Resume on Play; ALL 0 / 3s / 6s assigns crossfades to the whole queue. Individual row fades remain available.

Drop files onto either the main player or the detached playlist window. Both add to the same queue; dropping inside an attached queue adds each file once. A blue outline marks the accepted drop area. Playlist edit protection blocks both drop targets.

## Window layouts and installation

**Wide Layout** in the header arranges playback left and playlist right when the browser is at least 850 px wide. The preference is saved on this device. Narrow windows keep a vertical layout; the compact player stays compact. **In Player / Separate Window** switches the playlist placement without copying the queue or starting audio.

**Install on Mac** in the footer opens installation instructions and offers the browser’s install prompt when available. Safari on macOS 14+ supports File → Add to Dock. Open the installed app online once and cache every audio file before relying on offline use. The standalone window and icon are supplied by the browser; installation does not grant native menu bar or global keyboard access.

The original round Play/Pause transport is restored, with configurable color and size. The Hard / Play wordmark remains on the app icon and header. Both artwork files are included in the service worker shell cache.

## Appearance and compact companion (0.15)

Settings and Themes & Appearance are independent modeless panels, so the main player remains usable. The ↗ button detaches each panel into a browser window when popups are allowed. Choose Stage, Flightcase, Cables, Cinema, Theatre or Minimal; adjust colors, opacity, Play size, track text, spacing, radius and textures with a live preview. Preferences persist on this browser/device and work offline.

The − player button folds it into a draggable **Pocket Player** inside the page. Restore / OPEN returns the same player without interrupting audio. Browser tabs cannot turn into an OS desktop companion or stay running after their host browser quits: use the native Mac app for a floating desktop widget. Close/minimize of a settings panel affects that panel only. Keep the host page running for audio.

Undo Playlist Edit (↶ / Command-Z or Ctrl-Z) and Redo (Shift-Command-Z) retain 30 session edits. Queue edits and playback-policy settings can be restored; deletion Undo restores cached audio for the item. History resets when reloading. Transport and disk exports are not undone. Appearance can be reset to Stage independently.

My Set toggles a playlist drawer, with Below / Right / Left / Above placement and explicit Separate Window. Narrow screens stack the panels. Hover the seek bar for time inspection; only clicking/dragging seeks.

### Pocket position and lock panel (0.15.1)

Tap the left bezel beside the display to open/close the side panel. Position and Controls have explicit labels and states; the display also reports whether position is fixed and buttons are available. Drag the top grip while Position is Unlocked. Fixed prevents dragging and persists with the position after reload. Lock Controls blocks transport; hold its button for one second to unlock. A completed unlock consumes the release click so it cannot immediately relock. At the left viewport edge the panel moves over the bezel to stay reachable.

### Updating an older offline installation

The `/app/` entrypoint serves the same player with its own shell URL paths. Use it when an older offline service worker keeps showing the previous interface. Audio and playlists remain in the same origin's IndexedDB; no site data needs to be cleared. Relative shell assets and cloud download routes work under either entrypoint.
