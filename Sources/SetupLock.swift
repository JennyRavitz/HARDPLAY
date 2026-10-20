import Foundation
import Combine

/// A performance setup lock; independent of the full-screen accidental-touch shield.
final class SetupLock: ObservableObject {
    static let shared = SetupLock()
    private let defaults: UserDefaults
    @Published private(set) var isLocked = false
    @Published var protectEdits: Bool { didSet { defaults.set(protectEdits, forKey: "protectPlaylistEdits") } }
    @Published var protectSelection: Bool { didSet { defaults.set(protectSelection, forKey: "protectTrackSelection") } }
    @Published var protectPlayback: Bool { didSet { defaults.set(protectPlayback, forKey: "protectPlaybackControls") } }
    @Published var protectSettings: Bool { didSet { defaults.set(protectSettings,forKey:"protectSettings") } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        protectEdits = defaults.object(forKey: "protectPlaylistEdits") as? Bool ?? true
        protectSelection = defaults.object(forKey: "protectTrackSelection") as? Bool ?? true
        protectPlayback = defaults.bool(forKey: "protectPlaybackControls")
        protectSettings = defaults.object(forKey:"protectSettings") as? Bool ?? true
    }
    var editsBlocked: Bool { isLocked && protectEdits }
    var selectionBlocked: Bool { isLocked && (protectSelection || protectPlayback) }
    var playbackBlocked: Bool { isLocked && protectPlayback }
    var settingsBlocked: Bool { isLocked && protectSettings }
    func lockSettings() { protectSettings = true; isLocked = true }
    func lock() { isLocked = true }
    func unlock() { isLocked = false }
}
