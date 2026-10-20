import AppKit
import SwiftUI

/// One playlist shared by the main player, mini player and independent window.
final class PlaylistWindowState: ObservableObject {
    static let shared = PlaylistWindowState()
    @Published private(set) var detached = UserDefaults.standard.bool(forKey: "playlistDetached")
    func detach() {
        guard !ControlLock.shared.isLocked else { return }
        detached = true; UserDefaults.standard.set(true, forKey: "playlistDetached")
        AppDelegate.shared.showPlaylistWindow()
    }
    func attach(toMini: Bool) {
        guard !ControlLock.shared.isLocked else { return }
        detached = false; UserDefaults.standard.set(false, forKey: "playlistDetached")
        AppDelegate.shared.playlistWindow.orderOut(nil)
        if toMini { AppDelegate.shared.showMini() } else { AppDelegate.shared.showMain() }
    }
}
