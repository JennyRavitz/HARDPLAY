# HARDPLAY

<img src="assets/branding/hardplay-beams-icon-v1.png" width="180" alt="Hard Play blue stage-beam app icon">

Hard Play is a stage audio player for macOS, with an installable offline web edition. Blue and white translucent controls, two live decks, an independent playlist window, and quick access while working in other apps.

## Download and install on Mac

Download the latest **DMG or ZIP** from [Releases](https://github.com/JennyRavitz/HARDPLAY/releases/tag/v0.25.0). Open the DMG and drag **HARDPLAY.app** into **Applications**, or unzip and move the app there. Launch it from Applications, Spotlight or the Dock. HARDPLAY also stays accessible in the menu bar after its windows close.

- **macOS 14 Sonoma or newer.** Packaged builds are for **Apple Silicon (arm64)**. Intel Macs can build the source locally; these packages are not universal binaries.
- This development release is **ad-hoc signed, not Apple notarized**. macOS may require explicit approval in System Settings → Privacy & Security → Open Anyway after the first launch attempt. Do not disable Gatekeeper. A managed Mac may require its administrator.
- Native playback of local audio needs no network connection. Cloud-only files must first be downloaded to the Mac.
- The app displays an ordinary Dock icon and also provides a menu bar player.

## Install the offline web app

Open [HARDPLAY Web](https://hardplay-offline-stage.hardmute.chatgpt.site/) and choose **Install on Mac** in the footer.

- **Safari, macOS 14+:** File → Add to Dock → Add.
- **Chrome / Edge:** use the browser installation prompt or its app-install control. HARDPLAY offers **Install web app** when the browser makes the prompt available.
- Open the installed app online, add audio, and wait for **App saved** and **Saved offline** on every track. Request **Keep offline storage** in the offline storage panel and test the complete set without a connection.

The repository and Mac release downloads are public. The hosted web app currently requires separate access. Installing the web app does not transfer the native app’s library. Browser storage belongs to the browser profile; clearing site data removes cached tracks. Downloads must complete before offline use. See [web documentation](web/README.md) for storage and cloud limitations.

## PATCH rear panel

Hold the narrow right-hand strip beside the two audio displays for **two seconds** to slide PATCH out. Releasing early or dragging away cancels the hold. The corner **PATCH** button opens/closes the same panel immediately, including when controls are locked.

PATCH contains **Lock Controls**, the circular unlock ring, **Lock Setup**, Mini position lock, and **Open PATCH Settings**. The full PATCH settings panel still contains audio, themes, mappings, window preferences and quick buttons; **⌘,** opens it directly. Playback controls remain in the player. The toolbar now has two spaced rows so important buttons fit narrow windows.

## Main controls

- Two physical decks alternate left/right on each track change. The current deck is marked soft green, the next deck soft red, with NOW / NEXT labels, queue numbers, actual decoded waveforms, time and crossfade gains. During a fade, INCOMING / OUTGOING identify both tracks. Restarting or seeking the same track keeps its side. The active side survives restarting the app.
- **↔ / Wide Layout** switches to a wide workspace: playback left, playlist right. Resize the native main window by its edges. The web layout adapts to the available browser width.
- The changing **window icon** embeds or separates the playlist in one click. Docking remains available. Both views use the same queue.
- Selecting a title only selects it. Use the row’s **▶** to play. Right-click → **Duplicate Track** creates an independent queue occurrence.
- Inline rename, per-track transitions, global **ALL 0 / 3s / 6s**, auto-stop, restart/resume, volume, shuffle and repeat.
- **New Playlist… / Delete Playlist…** are in Playlist Files, the set-name right-click menu, and the app menu. New creates a named empty set; delete moves the saved document to Trash, or clears an unsaved set. Audio stays untouched. Undo restores the previous queue; after deleting, it restores an unsaved set. Recover the original document from Trash. **⌘N** creates a set.
- **mini hardplay** is a marker-on-tape button for the floating player. **PATCH → Themes** adds **FOH**, **Stage Crew** and **Stagehand**, using static vector casework and muted tape without added texture images.
- Save/open playlists; native `.hardplay` and web `.hardplay.json` store metadata, not audio. Web additionally supports individual play-time caps and total set timing.
- **Workspace Mode** switches between nearby separate utility windows and one tabbed window containing Settings, Themes, MIDI/Keys, Backup, Viewer and Audio Edit. The tabbed workspace keeps transport controls visible. Nearby panels are arranged relative to the main window, using a cascade when the display has insufficient free space.
- **Settings → Window opening preferences** chooses Inside Player, Nearby, Independent, Ask Each Time, or Workspace Default separately for each utility panel. Right-click a panel button for a one-time destination. Nearby panels follow the main window; independent panels keep their own position.
- **Settings → Custom quick buttons** adds up to four reassignable buttons below the toolbar. Right-click a quick button to choose an action, Trigger/Toggle mode where supported, or remove it. Window-opening actions use the same destination preferences. Keyboard/MIDI mappings include these new actions.
- Raised hardware-style controls use beveled edges, lighting and press depth; the expandable hint strip uses larger lettering. Main and Mini headers omit the wordmark and use wider button gaps.
- **Lock Controls** keeps music running. Drag clockwise around the 60-point ring to unlock. Straight drags, jumps, reverse motion and a short click do not unlock. Keyboard alternative: focus the ring and hold Space/Return for three seconds.
- New **Speaker Grille** and **Road Case** themes add perforated metal, equipment controls and flight-case trim. The main wordmark is a metal shield badge; tape labels use cleaner edges.
- Header buttons open **Mini**, **Nano** and **Full Screen**. **Auto Nano** chooses whether minimizing/closing opens the companion above ordinary desktop windows. **Auto Fit** follows content height and removes empty space. **?** expands/collapses the top hover-hint strip.
- Menu bar attach/detach (native), setup protection and full control lock. Right-click a deck or queue row → **Edit Audio…**.
- Keyboard / MIDI mapping: choose Map, select an action, send a key or MIDI signal. Supported actions have Trigger / Toggle behavior. Physical MIDI controllers require hardware verification.

Native codecs are provided by macOS; web codecs depend on the browser. Neither edition promises every audio format. The native and web editions have separate persistence and distinct platform features.

## Build from source

Native: macOS 14+, Swift 6 / Apple Command Line Tools, Python 3. No third-party packages.

```sh
zsh scripts/build.sh
open build/HARDPLAY.app
# Create DMG, ZIP and checksums for the current Mac architecture:
zsh scripts/release.sh
```

Web: Node.js 20+; no third-party dependencies or global installs.

```sh
cd web
node scripts/build.mjs
node --test tests/*.test.mjs
node scripts/validate-artifact.mjs
node scripts/dev-server.mjs
```

Open http://localhost:4173. Use `PORT=4184 node scripts/dev-server.mjs` to choose another port. HTTPS or localhost is required for offline installation. Hosted output is a self-contained Worker ESM; [web README](web/README.md) explains deployment and the allowlisted cloud proxy.

## Verification

The native build runs model/lock and queue tests automatically. Additional isolated checks:

```sh
build/HARDPLAY.app/Contents/MacOS/HARDPLAY --button-mode-test
build/HARDPLAY.app/Contents/MacOS/HARDPLAY --mapping-test
build/HARDPLAY.app/Contents/MacOS/HARDPLAY --playlist-test
codesign --verify --deep --strict build/HARDPLAY.app
```

See [validation notes](VALIDATION.md), [Russian user guide](docs/USER_GUIDE.ru.md) and [installation guide](docs/INSTALL.ru.md). GitHub Actions checks both editions and produces Mac build artifacts. Real-device MIDI, notarization and installation on a clean Mac are separate validation steps.

## Project structure

- `Sources/` — SwiftUI / AppKit player, AVPlayer engine, windows and MIDI.
- `web/` — browser player, IndexedDB audio cache, service worker and Worker proxy.
- `scripts/` — native build, release packaging and source export.
- `docs/` — usage, installation and release notes.
- `.github/workflows/` — build verification.

Personal playlists, audio, generated apps and local credentials are excluded from source publication. The repository is public; no open-source license has been assigned.

## 0.14.0 identity

Front-facing red Solo-key app icon with Hard / Play on two lines. The app artwork keeps the red physical key. Version 0.15 restores the original round blue Play/Pause transport, adjustable in Themes. The native menu bar uses a simplified red Hard / Play key and a separate playback-state badge. The remaining interface keeps its blue/white stage palette. The generated PNG masters and prompts live in `assets/branding/`.

## 0.15 — themes, pocket player, Undo

Settings opens independently of the player; Themes & Appearance opens another window for live preview. Six presets: Stage, Flightcase, Cables, Cinema, Theatre and Minimal. Adjust accent, background, text, playlist tape, opacity, Play button size, track text scale, spacing, corner radius and scenic texture. Preferences save locally.

Minimize the main/mini window to reveal **Hard Play Pocket**, a draggable floating companion with track, time, Play/Pause, previous/next and Restore. Closing the player window hides it and keeps the app/audio running; Command-Q explicitly quits. Settings and Themes have their own standard Mac minimize controls.

**Undo Playlist Edit** (↶ / Command-Z) and **Redo** (Shift-Command-Z) retain 30 queue edits during this app session: add, duplicate, rename, remove and fades. Undo does not restart live playback; restoring a removed current item loads it paused. The setup lock protects these actions. File saves and transport actions are not reversed.

Hover the seek bar to inspect the time without seeking. **My Set** toggles an attached playlist drawer without hiding the player; choose Below / Right / Left / Above or Separate Window. Docked native windows follow their owner, within the available display area.

### Pocket locks (0.15.1)

Tap the **left bezel beside the pocket display** to slide out the Locks panel; tap the same area again to hide it. There is no tiny icon to aim for. Position and Controls are separate, labelled controls: **Unlocked / Fixed** and **Available / Locked**. The display keeps a short state summary even when the panel is hidden.

Drag the pocket player anywhere using its top/body background while Position is unlocked. The position and position lock persist. The regular floating Mini Player also has its own position lock. Fixing position does not disable playback. Lock Controls disables playback/skip; swipe clockwise around the 60-point unlock ring, or hold Space for three seconds. The pocket drawer also offers a three-second hold button. The native hold control owns the entire gesture so mouse release cannot relock it.

### Desktop placement (0.15.2)

The Pocket Player heading is **HARD PLAY**, without a separator. Drag that top heading to move the desktop widget. Screen-edge constraints use the visible player face rather than the transparent lock-drawer margin, allowing placement against the left/right/top/bottom edges. Position and its lock persist. Near the left edge, the Locks panel overlays the display so it remains reachable. Position lock and playback lock stay independent.
## Timecode and redundant playback roadmap

The proposed native two-Mac workflow, timecode output and failover design are described in [the Russian implementation plan](docs/TIMECODE-BACKUP-PLAN.ru.md). This is a roadmap; timecode and automatic backup switching are not implemented yet.

## Backup preparation and resizable pocket (0.17.0)

Settings → **Timecode & Backup** opens an independent window for encrypted pairing of two Macs, local set checks and a portable backup package with audio. This first stage compares content hashes, order, fades and playback settings. It does not synchronize playback, emit timecode or switch audio. See [setup instructions in Russian](docs/BACKUP-SETUP.ru.md).

The native Pocket Player includes a seek slider with hover time. Drag its lower-right grip to resize it; the regular Mini Player is resizable too. Position lock fixes both location and size, while Controls Lock protects seeking and transport separately. Pocket size and position persist.

Double-click **My Set** to rename it inline; Enter saves and Esc cancels. The tape grows with the name. File/folder drops are handled by the main, mini, playlist and pocket surfaces.

## Quick Edit (0.18.0)

Click the scissors on a track or choose **Quick Edit…** from its context menu. Set In/Out points, preview the selection, then **Save as Copy** or **Replace in Playlist**. The editor exports a separate WAV at the original sample rate and channel count; source audio is preserved. Queue changes support Undo/Redo. See [Quick Edit instructions](docs/QUICK-EDIT.ru.md).

**Separate Window** is a toggle: click to show the playlist window, click again to hide it. Its highlighted state follows actual window visibility, including minimize and close.

## Waveform editing and joining (0.19.0)

Drag on the waveform to select audio; Command-drag adds another region and Command-click toggles existing clips. Split at Cursor, zoom, timeline scrolling, track height and precise In/Out fields support detailed editing. Hold Option over the waveform to audition; leaving the waveform or releasing Option stops auditioning. Preview has independent volume and is disabled while the main player plays.

Select two or more regions, then **Join & Save Copy** or **Join & Replace** to export one WAV in timeline order, omitting unselected gaps. Original audio is preserved. This editor joins regions within one source track; it does not combine different source files or crossfade edit seams.

## Local Web Viewer and fixed hints (0.20.0)

Settings → **Web Viewer** → **Start Web Viewer** provides a QR code and a session link for another device on the same trusted Wi-Fi or Ethernet network. The responsive, read-only page shows the live set, current and next tracks, remaining time, queue and crossfade state. Audio stays on the Mac. Stop Sharing revokes the session link; sharing never starts automatically. This is a local HTTP viewer, not internet hosting. See [setup and limitations](docs/WEB-VIEWER.ru.md).

Button hints now appear in a reserved **HINT** area at the top of each player window instead of floating over controls. The existing Show button hints switch still applies.

## Marker & Tape (0.21.0)

The blue three-beam icon, bundled marker lettering and hand-inked vector controls form the new identity. **Tape Blue / Tape White / Tape Black** presets provide live preview with automatic ink contrast. The primary wordmark reads **HARDPLAY**; the compact version stacks **HARD** over **PLAY**. Both are previewed in Themes, with six standalone SVG wordmarks under `assets/branding/wordmarks/`.

The typeface is bundled for offline use and registered only inside the Mac process. Matching web-player sources and local Web Viewer styling are included. See [the identity guide](docs/MARKER-IDENTITY.ru.md).
