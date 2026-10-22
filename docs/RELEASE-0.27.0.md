# Hard Play 0.27.0 — Playlist Editing Shortcuts

- A dedicated Edit menu exposes Select All, Deselect All, Cut, Copy, Paste, Duplicate, Remove, Undo, Redo, Rename and Move Up/Down.
- Use Command-A/C/X/V/D/Z and Shift-Command-Z. Delete or Command-Delete removes queue occurrences only. Return starts inline rename; arrows select, Shift-arrows extend the range, Option-Command-arrows move selected tracks. Control aliases are available for A/C/X/V/D/Z (Control-Shift-Z redoes).
- Command-click selects separate tracks; Shift-click selects a contiguous range. Group operations use one Undo step. Selection never starts playback.
- Paste makes fresh, independent queue identities after the last selection, retaining titles and crossfades. Finder audio-file copies can be pasted too. Cut/remove leave audio files on disk.
- Standard text-field shortcuts keep editing text. Queue shortcuts respect setup/full-control locks and do not modify the queue from settings, audio-editor windows or modal sheets.

Build/model, isolated clipboard/multiselect, reorder, lifecycle and AVPlayer waveform checks pass. Native GUI verified Edit menu, Command-A/D, Command-Z/Shift-Command-Z, Command-Delete with recovery, Return rename, Command-A/Z inside the name field, and Control-D/Z. Clipboard tests use a separate named pasteboard; real system clipboard contents were not replaced for QA. Temporary queue operations were undone; playback remained paused.

macOS 14+, Apple Silicon. Ad-hoc signed, not notarized. Native update; hosted web edition unchanged.
