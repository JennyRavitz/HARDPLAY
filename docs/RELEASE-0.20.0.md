# Hard Play 0.20.0 — Web Viewer & Fixed Hints Preview

- A compact, read-only live set page: current/next tracks, queue numbers, elapsed/remaining time and crossfade state.
- Settings → Web Viewer offers Start / Stop Sharing, a QR code and a session link. Uses local HTTP on a trusted Wi-Fi/Ethernet network; audio stays on the Mac.
- Stop Sharing revokes the link; new sessions use new keys. No playback, editing or audio-file endpoints are exposed.
- Button hints use a reserved, readable area at the top of the main/mini player, playlist and mapping windows. Show button hints remains optional.

Native model/export and real loopback HTTP tests passed. Browser layout, real player state on localhost, QR/link UI and connection-loss state were verified. A physical phone/second-device connection is not verified: direct LAN-IP probes on the development Mac timed out despite a permitted app firewall state. Treat remote LAN viewing as a preview pending network validation. See VALIDATION.md and docs/WEB-VIEWER.ru.md.

macOS 14+, Apple Silicon. DMG, ZIP and SHA-256 checksums included. Ad-hoc signed, not notarized. Hosted offline web player unchanged.
