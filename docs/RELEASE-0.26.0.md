# Hard Play 0.26.0 — Quiet Controls & Queue Order

- Reorder tracks using the ≡ handle at the left of a row. A thin insertion line indicates before/after placement. Right-click or open Track Actions for Move Up, Move Down, Move to Top and Move to Bottom.
- Reordering is protected by setup/control locks, supports Undo/Redo and is retained in saved playlists. Current playback, selection, position and volume stay intact; reordering or undoing during a crossfade keeps both engines running.
- Calmer buttons use soft fills, a thin rim and minimal shadow. Raised bevels, bright highlights and heavy shadows are removed from the shared controls and transport. Active modes keep a subtle accent.
- Playlist rows show selection/title, Play, fade and one compact actions menu. Editing, renaming, duplication, ordering and removal are grouped there and in the context menu. The fade menu only contains crossfade modes.
- Set names wrap instead of truncating to an ellipsis. Detached-playlist status is a compact row with a Show button. Custom settings labels are cleaner; standard macOS file-dialog ellipses remain.

Build and model/audio integration checks pass, including real AVPlayer crossfades and reorder Undo. Native GUI verified menu-driven reordering and Undo, Main/PATCH controls and the detached playlist. Physical drag verification was blocked by the computer-use service's window-coordinate error; drag behavior remains to be manually exercised on the target desktop. Mini controls were accessibility-checked, but its screenshot capture was blank.

macOS 14+, Apple Silicon. Ad-hoc signed, not notarized. Native update; hosted web edition unchanged.
