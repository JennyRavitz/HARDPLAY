# HARDPLAY

A stage audio player for macOS, with an installable offline web edition. Blue and white translucent controls, two live decks, an independent playlist window, and quick access while working in other apps.

## Download and install on Mac

Download the latest **DMG or ZIP** from [Releases](../../releases/latest). Open the DMG and drag **HARDPLAY.app** into **Applications**, or unzip and move the app there. Launch it from Applications, Spotlight or the Dock. HARDPLAY also stays accessible in the menu bar after its windows close.

- **macOS 14 Sonoma or newer.** The downloadable 0.13.0 build is for **Apple Silicon (arm64)**. Intel Macs can build the source locally; this release is not a universal binary.
- This development release is **ad-hoc signed, not Apple notarized**. macOS may require explicit approval in System Settings → Privacy & Security → Open Anyway after the first launch attempt. Do not disable Gatekeeper. A managed Mac may require its administrator.
- Native playback of local audio needs no network connection. Cloud-only files must first be downloaded to the Mac.
- The app displays an ordinary Dock icon and also provides a menu bar player.

## Install the offline web app

Open [HARDPLAY Web](https://hardplay-offline-stage.hardmute.chatgpt.site/) and choose **Install on Mac** in the footer.

- **Safari, macOS 14+:** File → Add to Dock → Add.
- **Chrome / Edge:** use the browser installation prompt or its app-install control. HARDPLAY offers **Install web app** when the browser makes the prompt available.
- Open the installed app online, add audio, and wait for **App saved** and **Saved offline** on every track. Request **Keep offline storage** in the offline storage panel and test the complete set without a connection.

The hosted web app and repository are private and require access. Installing the web app does not transfer the native app’s library. Browser storage belongs to the browser profile; clearing site data removes cached tracks. Downloads must complete before offline use. See [web documentation](web/README.md) for storage and cloud limitations.

## Main controls

- Two decks show NOW / NEXT, queue numbers, actual decoded waveforms, time and crossfade gains.
- **↔ / Wide Layout** switches to a wide workspace: playback left, playlist right. Resize the native main window by its edges. The web layout adapts to the available browser width.
- **In Player / Separate Window** places the playlist inside the player or in an independent window. Both use the same queue. The chain icon attaches it again.
- Selecting a title only selects it. Use the row’s **▶** to play. Right-click → **Duplicate Track** creates an independent queue occurrence.
- Inline rename, per-track transitions, global **ALL 0 / 3s / 6s**, auto-stop, restart/resume, volume, shuffle and repeat.
- Save/open playlists; native `.hardplay` and web `.hardplay.json` store metadata, not audio. Web additionally supports individual play-time caps and total set timing.
- Floating mini player, menu bar attach/detach (native), setup protection, full control lock, optional hover hints.
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

Personal playlists, audio, generated apps and local credentials are excluded from source publication. No open-source license has been assigned; the repository is private.
