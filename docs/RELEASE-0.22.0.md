# Hard Play 0.22.0 — Window Controls Preview

- Raised hardware-style buttons and transport, with bevels, light/shadow and press depth. Hint text is enlarged from 11 to 16.5 points with room for three lines.
- Workspace Mode toggles nearby separate panels and one tabbed main window (Settings, Themes, MIDI/Keys, Backup, Viewer, Audio Edit). A compact transport remains visible in tabs. Editor preparation is idempotent so changing tabs preserves the working selection.
- Nearby panel placement uses available space around the main window and follows its moves; crowded displays use an accessible cascade.
- Dedicated hand-drawn Mini, Nano and Full Screen buttons in the main header. Highlighting follows actual window visibility; repeated clicks hide Mini/Nano or leave full screen.
- Auto Fit switch follows measured player/playlist content, removes spare space and preserves the top edge and width. Long queues scroll and the window stays within the visible display; manual sizing remains available with the mode off.
- Separate Auto Nano switch in the header and Settings: choose whether minimizing/closing a player opens the desktop companion above ordinary windows. Manual Nano remains available with this mode off.
- The question-mark button reveals or collapses the fixed hint strip above the player. Hover descriptions stay in that strip.
- Removed the graphic app icon from the player header; a new engraved shield wordmark sits slightly to the right.
- Refined tape edges and new Speaker Grille / Road Case themes with perforated metal, hardware controls and road-case rails. Existing Flightcase gains the hardware finish.
- A single icon-only playlist button switches between an embedded list and a separate window. Its icon, state and accessible name change with the presentation; the separate window also has a direct embed button. Docking remains available.
- Edit Audio is available by right-clicking either deck card or a playlist row, including the mini and separate playlist views. Existing edit locks are respected.

macOS 14+, Apple Silicon. Ad-hoc signed; not notarized. This native update does not redeploy the hosted web player.
