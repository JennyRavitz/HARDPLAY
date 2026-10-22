# Hard Play 0.25.0 — Alternating Stage Decks

- Tracks alternate between the physical left and right decks: first left, next right, then left again. The current track stays on its deck after the transition; the next queued track occupies the opposite deck.
- Soft green identifies the current deck, soft red the next deck. Colour appears in the role badge, waveform, gain bar and card rim. NOW / NEXT text and queue numbers remain visible. Empty decks are neutral.
- Crossfades work in both directions. During a fade, green INCOMING and red OUTGOING identify the primary and departing tracks; after completion the departing deck shows the next queued track.
- Waveform seeking, hover times, next-start cues and gain displays follow the correct physical deck. Selecting a playlist row, seeking or restarting the same occurrence does not swap sides. Opening a new playlist starts on the left; the active side is retained across app restarts.
- A large centre arrow is not added. The compact queue-number strip follows physical left/right placement. PATCH edge access retains the two-second hold introduced in 0.24.1.

macOS 14+, Apple Silicon. Ad-hoc signed, not notarized. Native update; hosted web edition unchanged.
