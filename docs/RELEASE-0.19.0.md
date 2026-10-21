# Hard Play 0.19.0 — Waveform Editor

Native Mac preview release, macOS 14+ on Apple Silicon.

- Select directly on the waveform. Command-drag adds a separate region; Command-click toggles existing clips.
- Split at Cursor, zoom, scroll, adjustable waveform height and precise In/Out fields.
- Join selected regions into one WAV with **Join & Save Copy** or **Join & Replace**, in timeline order without unselected gaps. Original audio stays unchanged.
- Option-hover audition with separate preview volume. Stops on Option release, pointer exit or focus loss; disabled while the main player plays.
- Quick Edit copy/replace supports playlist Undo/Redo.
- Resizable Pocket Player with seeking; separate playlist window toggle; inline set naming and audio drops on player surfaces.
- First-stage two-Mac backup preparation: encrypted pairing, set comparison and portable audio package. This does not synchronize playback, output timecode or switch audio.

Validation: native self/queue/playlist/mapping/button-mode/clip tests and real TLS loopback tests passed. Clip tests verify exact stereo join boundary samples, duration and source preservation. Waveform gesture model and export are tested; final pointer-driven verification of the latest editor remains pending. No physical second-Mac test is claimed. See VALIDATION.md and docs/QUICK-EDIT.ru.md.

The app is ad-hoc signed and not notarized. Download the DMG or ZIP; SHA-256 checksums are included. This preview does not change the hosted web app.
