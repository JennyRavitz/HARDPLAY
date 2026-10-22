import AppKit
import SwiftUI
import AVFoundation
import MediaPlayer
import UniformTypeIdentifiers
import Carbon
import CoreMIDI
import Combine

struct Track: Identifiable, Codable, Equatable {
    var id: String { occurrenceID ?? identity ?? url.path }
    let url: URL
    var customTitle: String? = nil
    var occurrenceID: String? = nil
    var identity: String? = nil
    var title: String { customTitle ?? url.deletingPathExtension().lastPathComponent }
    var format: String { url.pathExtension.uppercased() }
}

enum StartMode: String, CaseIterable, Codable { case beginning, resume }
enum EndMode: String, CaseIterable, Codable { case next, stop }
enum FadeMode: String, CaseIterable, Codable {
    case none, short, long
    var seconds: Double { switch self { case .none: return 0; case .short: return 3; case .long: return 6 } }
    var title: String { switch self { case .none: return "Off"; case .short: return "Short"; case .long: return "Long" } }
}

final class Player: ObservableObject {
    static let shared = Player()
    @Published var tracks: [Track] = []
    @Published private(set) var playlistURL: URL?
    @Published private(set) var playlistName = "My Set"
    @Published private(set) var recentPlaylists: [URL] = []
    @Published var selectedID: String?
    @Published private(set) var activeDeckRight=false
    private var deckTrackID:String?
    @Published var currentID: String?
    @Published var playing = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 0.8 { didSet { applyMixVolumes(); persist() } }
    @Published var shuffle = false { didSet { cancelCrossfade() } }
    @Published var repeatAll = false { didSet { cancelCrossfade() } }
    @Published var error: String?
    @Published var startMode: StartMode = .beginning { didSet { persist() } }
    @Published var endMode: EndMode = .next { didSet { if endMode == .stop { cancelCrossfade() }; configureEndBoundary(); persist() } }
    @Published var stopBeforeEnd: Double = 0 { didSet { configureEndBoundary(); persist() } }
    @Published var stoppedAtBoundary = false
    @Published private(set) var transitionModes: [String: FadeMode] = [:]
    @Published private(set) var isCrossfading = false
    @Published private(set) var outgoingTrack: Track?
    private var outgoingDuration: Double = 0
    private var nextChoice: Track?
    private var outgoing: AVPlayer?
    private var fadeTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var prepared: (track: Track, player: AVPlayer, duration: Double, position: Double)?
    private var preparationID: UUID?
    private var manualPreparation = false
    private var failedPreparationSource: String?
    private var fadeLength: Double = 0
    @Published private(set) var fadeProgress: Double = 0
    private var fadeStart: Double = 0
    private var observerEngine: AVPlayer?
    private var publishNowPlaying = true
    private var restoring = true
    private let defaults: UserDefaults
    private var positions: [String: Double] = [:]
    private var endBoundary: Any?
    private(set) var isLoading = false
    private var lastCheckpoint: Double = -1
    private var engine = AVPlayer()
    private var observer: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObservation: NSKeyValueObservation?
    private var loadingTask: Task<Void, Never>?
    private var restoredTime: Double = 0
    private var accessed = Set<URL>()
    private var bookmarks: [String: Data] = [:]
    private let extensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "alac", "caf", "mp4", "ogg", "opus", "wma", "ape"]
    var current: Track? { tracks.first { $0.id == currentID } }
    var fraction: Double { duration > 0 ? min(elapsed / duration, 1) : 0 }

    private let setupLock: SetupLock
    init(defaults: UserDefaults = .standard, remoteCommands: Bool = true, setupLock: SetupLock = .shared) {
        self.setupLock = setupLock
        self.defaults = defaults
        publishNowPlaying = remoteCommands
        if let path = defaults.string(forKey: "playlistURL") { playlistURL = URL(fileURLWithPath:path) }
        playlistName = defaults.string(forKey:"playlistName") ?? "My Set"
        if playlistName == "Untitled" { playlistName="My Set" }
        recentPlaylists = (defaults.stringArray(forKey:"recentPlaylists") ?? []).map { URL(fileURLWithPath:$0) }
        if let data = defaults.data(forKey: "transitionModes"), let modes = try? JSONDecoder().decode([String: FadeMode].self, from: data) { transitionModes = modes }
        positions = defaults.dictionary(forKey: "positions") as? [String: Double] ?? [:]
        startMode = StartMode(rawValue: defaults.string(forKey: "startMode") ?? "") ?? .beginning
        endMode = EndMode(rawValue: defaults.string(forKey: "endMode") ?? "") ?? .next
        stopBeforeEnd = min(30, max(0, defaults.double(forKey: "stopBeforeEnd")))
        var restoredTrackIDs: [String: String] = [:]
        bookmarks = defaults.dictionary(forKey: "bookmarks") as? [String: Data] ?? [:]
        if let data = defaults.data(forKey: "queue"), let saved = try? JSONDecoder().decode([Track].self, from: data) {
            tracks = saved.map { track in
                guard let bookmark = bookmarks[track.id] else { return track }
                var stale = false
                guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale) else { return track }
                if url.startAccessingSecurityScopedResource() { accessed.insert(url) }
                let restored = Track(url:url,customTitle:track.customTitle,occurrenceID:track.occurrenceID,identity:track.identity)
                restoredTrackIDs[track.id] = restored.id
                if let position = positions[track.id] { positions[restored.id] = position }
                if let mode = transitionModes[track.id] { transitionModes[restored.id] = mode }
                return restored
            }
        }
        if let savedID = defaults.string(forKey: "current") { currentID = restoredTrackIDs[savedID] ?? savedID }
        activeDeckRight=defaults.bool(forKey:"activeDeckRight");deckTrackID=currentID
        selectedID = defaults.string(forKey:"selectedTrack").map { restoredTrackIDs[$0] ?? $0 } ?? currentID
        if !tracks.contains(where:{$0.id == selectedID}) { selectedID = currentID ?? tracks.first?.id }
        restoredTime = defaults.double(forKey: "elapsed")
        if defaults.object(forKey: "volume") != nil { volume = defaults.double(forKey: "volume") }
        engine.volume = Float(volume)
        installTimeObserver()
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let self, let item = note.object as? AVPlayerItem, item === self.engine.currentItem else { return }
            if self.endMode == .stop { self.pause(); self.stoppedAtBoundary = true }
            else if self.preparationTask == nil { self.next(automatic: true) }
        }
        restoring = false
        if remoteCommands { configureRemote() }
        if let id = currentID, let track = tracks.first(where: { $0.id == id }) { isLoading = true; load(track, autoplay: false, position: restoredTime) }
    }
    func installTimeObserver() {
        if let observer, let observerEngine { observerEngine.removeTimeObserver(observer) }
        let observed = engine
        observerEngine = observed
        observer = observed.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self, weak observed] time in
            guard let self, let observed, observed === self.engine, !self.isLoading else { return }
            guard self.engine.currentItem != nil else { self.elapsed = 0; self.playing = false; return }
            let currentSeconds = self.engine.currentTime().seconds
            self.elapsed = currentSeconds.isFinite ? max(0, currentSeconds) : 0
            self.playing = self.engine.rate > 0 && self.engine.currentItem?.status != .failed
            if self.playing && abs(self.elapsed - self.lastCheckpoint) >= 2 {
                self.rememberPosition(); self.persist(); self.lastCheckpoint = self.elapsed
            }
            self.checkAutomaticCrossfade()
            self.nowPlaying()
        }
    }
    private struct QueueEdit {
        var tracks:[Track];var modes:[String:FadeMode];var positions:[String:Double];var bookmarks:[String:Data];var selected:String?;var name:String;var url:URL?;var deckRight:Bool;var orderOnly:Bool
    }
    private var pastEdits:[QueueEdit] = []
    private var futureEdits:[QueueEdit] = []
    var canUndoEdit:Bool { !pastEdits.isEmpty }
    var canRedoEdit:Bool { !futureEdits.isEmpty }
    private func editSnapshot(orderOnly:Bool=false)->QueueEdit { QueueEdit(tracks:tracks,modes:transitionModes,positions:positions,bookmarks:bookmarks,selected:selectedID,name:playlistName,url:playlistURL,deckRight:activeDeckRight,orderOnly:orderOnly) }
    private func recordEdit(orderOnly:Bool=false) { pastEdits.append(editSnapshot(orderOnly:orderOnly));if pastEdits.count>30 { pastEdits.removeFirst() };futureEdits=[];objectWillChange.send() }
    func undoEdit() {
        guard !setupLock.editsBlocked,!ControlLock.shared.isLocked,let edit=pastEdits.popLast() else { return }
        futureEdits.append(editSnapshot(orderOnly:edit.orderOnly));restoreEdit(edit)
    }
    func redoEdit() {
        guard !setupLock.editsBlocked,!ControlLock.shared.isLocked,let edit=futureEdits.popLast() else { return }
        pastEdits.append(editSnapshot(orderOnly:edit.orderOnly));restoreEdit(edit)
    }
    private func restoreEdit(_ edit:QueueEdit) {
        if edit.orderOnly {invalidateQueuePreparation()}else {cancelCrossfade()}
        if !edit.tracks.contains(where:{$0.id == currentID}) || edit.tracks.first(where:{$0.id == currentID})?.url != current?.url { pause();loadingTask?.cancel();engine.replaceCurrentItem(with:nil);currentID=nil;elapsed=0;duration=0 }
        playlistURL=edit.url.flatMap {FileManager.default.fileExists(atPath:$0.path) ? $0:nil};playlistName=edit.name;tracks=edit.tracks;transitionModes=edit.modes;positions.merge(edit.positions) { current,_ in current };bookmarks=edit.bookmarks;selectedID=edit.selected
        if current == nil {activeDeckRight=edit.deckRight;deckTrackID=nil}
        if current == nil,let first=selectedTrack ?? tracks.first { load(first,autoplay:false,position:positions[first.id] ?? 0) }
        persist();nowPlaying();objectWillChange.send()
    }
    func fadeMode(after track: Track) -> FadeMode { transitionModes[track.id] ?? .none }
    func setFadeMode(_ mode: FadeMode, after track: Track) {
        guard !setupLock.editsBlocked else { return }
        guard fadeMode(after:track) != mode else { return };recordEdit()
        transitionModes[track.id] = mode
        if currentID == track.id { cancelCrossfade() }
        persist()
    }
    var uniformFadeMode: FadeMode? {
        guard let first = tracks.first else { return nil }
        let mode = fadeMode(after: first)
        return tracks.allSatisfy { fadeMode(after: $0) == mode } ? mode : nil
    }
    func setFadeModeForAll(_ mode: FadeMode) {
        guard !setupLock.editsBlocked else { return }
        guard !tracks.isEmpty else { return }
        guard uniformFadeMode != mode else { return };recordEdit()
        let currentChanges = current.map { fadeMode(after: $0) != mode } ?? false
        var updated = transitionModes
        for track in tracks { updated[track.id] = mode }
        transitionModes = updated
        if currentChanges { cancelCrossfade() }
        persist()
    }
    var mixGains: (Double, Double) { isCrossfading ? (1 - fadeProgress, fadeProgress) : (0, 1) }
    private func applyMixVolumes() {
        engine.volume = Float(volume * mixGains.1)
        outgoing?.volume = Float(volume * mixGains.0)
    }
    private func cancelCrossfade() {
        preparationTask?.cancel(); preparationTask = nil; preparationID = nil
        prepared?.player.pause(); prepared = nil; manualPreparation = false
        fadeTask?.cancel(); fadeTask = nil; outgoing?.pause(); outgoing = nil
        isCrossfading = false; outgoingTrack = nil; outgoingDuration = 0; nextChoice = nil; fadeProgress = 0; failedPreparationSource = nil
        applyMixVolumes()
    }
    var nextTrack: Track? { upcomingTrack() }
    /// Physical decks alternate only when a different queue occurrence is loaded.
    private func commitDeck(_ id:String) {
        if let previous=deckTrackID,previous != id {activeDeckRight.toggle()}
        deckTrackID=id
    }
    private func resetDecks() {activeDeckRight=false;deckTrackID=nil}
    /// Existing stageLeft/stageRight values describe outgoing/current and incoming/next roles.
    /// This mapping places those roles on the physical left/right deck without changing audio routing.
    func deckUsesNextRole(right:Bool)->Bool {isCrossfading ? right == activeDeckRight:right != activeDeckRight}
    func deckTrack(right:Bool)->Track? {deckUsesNextRole(right:right) ? stageRight:stageLeft}
    func deckTime(right:Bool)->Double {deckUsesNextRole(right:right) ? stageRightTime:stageLeftTime}
    func deckDuration(right:Bool)->Double {deckUsesNextRole(right:right) ? stageRightDuration:stageLeftDuration}
    func deckGain(right:Bool)->Double {deckUsesNextRole(right:right) ? stageRightGain:stageLeftGain}
    func deckLabel(right:Bool)->String {
        let next=deckUsesNextRole(right:right)
        return isCrossfading ? (next ? "INCOMING":"OUTGOING"):(next ? "NEXT":"NOW")
    }
    func deckIsCurrent(right:Bool)->Bool {right == activeDeckRight}
    var stageLeft: Track? { isCrossfading ? outgoingTrack.flatMap { outgoing in tracks.first { $0.id == outgoing.id } ?? outgoing } : current }
    var stageRight: Track? { isCrossfading ? current : nextTrack }
    var stageLeftTime: Double { isCrossfading ? (outgoing?.currentTime().seconds ?? 0) : elapsed }
    var stageLeftDuration: Double { isCrossfading ? outgoingDuration : duration }
    @Published private(set) var waveformCues:[String:Double] = [:]
    var stageRightTime: Double { isCrossfading ? elapsed : (nextTrack.flatMap { waveformCues[$0.id] } ?? prepared?.position ?? 0) }
    var stageRightDuration: Double { isCrossfading ? duration : (prepared?.duration ?? 0) }
    var stageLeftGain: Double { current == nil ? 0 : (isCrossfading ? 1 - fadeProgress : 1) }
    var stageRightGain: Double { isCrossfading ? fadeProgress : 0 }
    var transitionRemaining: Double { isCrossfading ? max(0, fadeLength * (1 - fadeProgress)) : 0 }
    var stageTransitionTrack: Track? { isCrossfading ? outgoingTrack : current }
    func queueNumber(_ track: Track?) -> String {
        guard let track, let index = tracks.firstIndex(where: { $0.id == track.id }) else { return "—" }
        return String(format: "%02d", index + 1)
    }
    private func upcomingTrack() -> Track? {
        if let nextChoice, let updated = tracks.first(where: { $0.id == nextChoice.id }) { return updated }
        guard let index = tracks.firstIndex(where: { $0.id == currentID }), !tracks.isEmpty else { return nil }
        if shuffle, tracks.count > 1 { nextChoice = tracks.filter { $0.id != currentID }.randomElement() }
        else if index + 1 < tracks.count { nextChoice = tracks[index + 1] }
        else if repeatAll { nextChoice = tracks.first }
        return nextChoice
    }
    var selectedTrack: Track? { tracks.first { $0.id == selectedID } }
    func selectInQueue(_ track:Track) {
        guard !setupLock.selectionBlocked,!ControlLock.shared.isLocked,tracks.contains(where:{$0.id == track.id}) else { return }
        selectedID=track.id; persist()
    }
    func playFromQueue(_ track:Track) {
        guard !setupLock.selectionBlocked,!setupLock.playbackBlocked,!ControlLock.shared.isLocked else { return }
        if currentID == track.id && playing { pause() } else { play(track) }
    }
    @discardableResult func duplicate(_ track:Track) -> Track? {
        guard !setupLock.editsBlocked,!ControlLock.shared.isLocked,let index=tracks.firstIndex(where:{$0.id == track.id}) else { return nil }
        recordEdit()
        let copy=Track(url:track.url,customTitle:track.customTitle,occurrenceID:UUID().uuidString)
        tracks.insert(copy,at:index+1); transitionModes[copy.id]=fadeMode(after:track); positions[copy.id]=0
        bookmarks[copy.id]=bookmarks[track.id]; selectedID=copy.id; nextChoice=nil
        if !isCrossfading { preparationTask?.cancel(); preparationTask=nil; preparationID=nil; prepared?.player.pause(); prepared=nil; manualPreparation=false }
        persist(); return copy
    }
    @discardableResult func applyEditedClip(_ source:Track,file:URL,replace:Bool)throws->Track {
        guard !setupLock.editsBlocked,!ControlLock.shared.isLocked,let index=tracks.firstIndex(where:{$0.id == source.id}),tracks[index].url == source.url else {throw BackupFailure("The track changed or editing is locked. The exported file is still saved.")}
        guard !replace || !((currentID == source.id || outgoingTrack?.id == source.id) && playing) else {throw BackupFailure("Pause this track before replacing it. The exported file is still saved.")}
        guard !replace || currentID != source.id || !setupLock.playbackBlocked else {throw BackupFailure("Unlock playback controls before replacing this track.")}
        recordEdit()
        let original=tracks[index]
        let edited=Track(url:file,customTitle:original.title+" · Edit",occurrenceID:replace ? original.occurrenceID:UUID().uuidString,identity:replace ? original.identity ?? (original.occurrenceID == nil ? original.id:nil):nil)
        let mode=fadeMode(after:original)
        if replace {tracks[index]=edited} else {tracks.insert(edited,at:index+1)}
        transitionModes[edited.id]=mode;positions[edited.id]=0
        bookmarks[edited.id]=try? file.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
        selectedID=edited.id;nextChoice=nil
        if !isCrossfading {preparationTask?.cancel();preparationTask=nil;preparationID=nil;prepared?.player.pause();prepared=nil;manualPreparation=false}
        if replace,currentID == original.id {load(edited,autoplay:false,position:0)}
        persist();nowPlaying();return edited
    }
    func play(_ track: Track) {
        guard !setupLock.selectionBlocked else { return }
        selectedID=track.id
        if currentID == track.id { load(track); return }
        guard playing, !isLoading, let current, fadeMode(after: current).seconds > 0, duration - elapsed > 0.15 else {
            load(track); return
        }
        cancelCrossfade()
        prepareCrossfade(to: track, manual: true)
    }
    private func checkAutomaticCrossfade() {
        guard playing, !isLoading, !isCrossfading, endMode == .next, let current, failedPreparationSource != currentID else { return }
        let length = min(fadeMode(after: current).seconds, duration / 2)
        guard length > 0 else { return }
        if let prepared, !manualPreparation, duration - elapsed <= min(length, prepared.duration / 2) {
            startCrossfade(prepared); return
        }
        if preparationTask == nil, prepared == nil, duration - elapsed <= length + 2, let next = upcomingTrack() {
            prepareCrossfade(to: next, manual: false)
        }
    }
    private func prepareCrossfade(to track: Track, manual: Bool) {
        guard let source = currentID else { return }
        let cue = waveformCues[track.id]
        let requestedPosition = cue ?? (manual && startMode == .resume ? positions[track.id, default: 0] : 0)
        let token = UUID(); preparationID = token; manualPreparation = manual
        preparationTask = Task { @MainActor [weak self] in
            do {
                guard FileManager.default.fileExists(atPath: track.url.path) else { throw CocoaError(.fileReadNoSuchFile) }
                let asset = AVURLAsset(url: track.url)
                let seconds = try await asset.load(.duration).seconds
                guard seconds.isFinite, seconds > 0, try await asset.load(.isPlayable) else { throw CocoaError(.fileReadCorruptFile) }
                let incoming = AVPlayer(playerItem: AVPlayerItem(asset: asset)); incoming.volume = 0
                // Prepare the second decoder while the current track continues playing.
                for _ in 0..<100 {
                    try Task.checkCancellation()
                    if incoming.currentItem?.status == .readyToPlay { break }
                    if incoming.currentItem?.status == .failed { throw CocoaError(.fileReadCorruptFile) }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                guard incoming.currentItem?.status == .readyToPlay else { throw CocoaError(.fileReadUnknown) }
                let position = cue != nil ? min(max(0,requestedPosition),max(0,seconds-1/600)) : (requestedPosition < seconds - 0.1 ? max(0, requestedPosition) : 0)
                await incoming.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                guard !Task.isCancelled, let self, self.preparationID == token, self.currentID == source else { incoming.pause(); return }
                self.preparationTask = nil
                let ready = (track: track, player: incoming, duration: seconds, position: position)
                self.prepared = ready
                if manual { self.startCrossfade(ready) }
                else if !self.playing && self.elapsed >= self.duration - 0.1 {
                    self.prepared = nil; self.load(track, position: ready.position, precisePosition: true)
                } else { self.checkAutomaticCrossfade() }
            } catch {
                guard !Task.isCancelled, let self, self.preparationID == token, self.currentID == source else { return }
                self.preparationTask = nil; self.prepared = nil; self.manualPreparation = false
                self.failedPreparationSource = source
                self.error = "Crossfade is unavailable for the next file. The current track will keep playing."
                if self.elapsed >= self.duration - 0.1 { self.next(automatic: true) }
            }
        }
    }
    private func startCrossfade(_ ready: (track: Track, player: AVPlayer, duration: Double, position: Double)) {
        guard let current else { return }
        let length = min(fadeMode(after: current).seconds, max(0, duration - elapsed), (ready.duration - ready.position) / 2)
        guard length > 0.05 else { prepared = nil; load(ready.track, position: ready.position, precisePosition: true); return }
        let shouldPlay = playing
        rememberPosition(); clearEndBoundary(); failureObservation = nil
        outgoingTrack = current; outgoingDuration = duration; nextChoice = nil
        outgoing = engine; engine = ready.player; prepared = nil; preparationID = nil; manualPreparation = false
        if selectedID == nil || selectedID == currentID { selectedID=ready.track.id }
        waveformCues.removeValue(forKey:ready.track.id)
        commitDeck(ready.track.id)
        currentID = ready.track.id; duration = ready.duration; elapsed = ready.position; stoppedAtBoundary = false; lastCheckpoint = -1; error = nil
        fadeLength = length; fadeStart = ready.position; fadeProgress = 0; isCrossfading = true
        installTimeObserver(); configureEndBoundary(); watchFailure(of: engine.currentItem!); applyMixVolumes()
        if shouldPlay { engine.play() } else { outgoing?.pause() }
        playing = shouldPlay; nowPlaying(); persist()
        fadeTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isCrossfading else { return }
                self.fadeProgress = min(1, max(0, (self.engine.currentTime().seconds - self.fadeStart) / self.fadeLength))
                self.applyMixVolumes()
                if self.fadeProgress >= 1 {
                    self.outgoing?.pause(); self.outgoing = nil; self.isCrossfading = false; self.outgoingTrack = nil; self.outgoingDuration = 0
                    self.fadeTask = nil; self.applyMixVolumes(); return
                }
                do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            }
        }
    }
    func persist() {
        guard !restoring else { return }
        let d = defaults
        d.set(try? JSONEncoder().encode(tracks), forKey: "queue")
        d.set(currentID, forKey: "current")
        d.set(activeDeckRight,forKey:"activeDeckRight")
        d.set(selectedID,forKey:"selectedTrack")
        d.set(elapsed, forKey: "elapsed")
        d.set(volume, forKey: "volume")
        d.set(bookmarks, forKey: "bookmarks")
        d.set(positions, forKey: "positions")
        d.set(startMode.rawValue, forKey: "startMode")
        d.set(endMode.rawValue, forKey: "endMode")
        d.set(stopBeforeEnd, forKey: "stopBeforeEnd")
        d.set(try? JSONEncoder().encode(transitionModes), forKey: "transitionModes")
        d.set(playlistURL?.path, forKey:"playlistURL")
        d.set(playlistName,forKey:"playlistName")
        d.set(recentPlaylists.map(\.path),forKey:"recentPlaylists")
    }
    func add(_ urls: [URL]) {
        guard !setupLock.editsBlocked,!ControlLock.shared.isLocked else { return }
        var files: [URL] = []
        for url in urls {
            if url.startAccessingSecurityScopedResource() { accessed.insert(url) }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    files += iterator.compactMap { $0 as? URL }.filter { extensions.contains($0.pathExtension.lowercased()) }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                }
            } else { files.append(url) }
        }
        if files.contains(where:{ url in extensions.contains(url.pathExtension.lowercased()) && !tracks.contains(where:{$0.url == url})}) { recordEdit() }
        for url in files where extensions.contains(url.pathExtension.lowercased()) && !tracks.contains(where: { $0.url == url }) {
            tracks.append(Track(url: url))
            bookmarks[url.path] = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        if current == nil, let first = tracks.first { load(first, autoplay: false) }
        if files.isEmpty { error = "No supported audio files were found." }
        persist()
    }
    func rename(_ track: Track, to title: String?) {
        guard !setupLock.editsBlocked, !ControlLock.shared.isLocked,
              let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard tracks[index].customTitle != (trimmed.isEmpty ? nil : String(trimmed.prefix(300))) else { return };recordEdit()
        tracks[index].customTitle = trimmed.isEmpty ? nil : String(trimmed.prefix(300))
        persist(); nowPlaying()
    }
    func renameSet(to title:String) {
        guard !setupLock.editsBlocked,!ControlLock.shared.isLocked else {return}
        let value=String(title.replacingOccurrences(of:"\n",with:" ").replacingOccurrences(of:"\r",with:" ").trimmingCharacters(in:.whitespacesAndNewlines).prefix(100))
        let name=value.isEmpty ? "My Set":value
        guard name != playlistName else {return};recordEdit();playlistName=name;persist()
    }
    private func notePlaylist(_ url: URL) {
        playlistURL = url
        recentPlaylists.removeAll { $0 == url }; recentPlaylists.insert(url,at:0)
        recentPlaylists = Array(recentPlaylists.prefix(8))
    }
    func writePlaylist(to url: URL) throws {
        rememberPosition()
        let file = SavedPlaylist(name:playlistName,
            tracks:tracks.map { SavedPlaylist.Entry(path:SavedPlaylist.relativePath($0.url,to:url.deletingLastPathComponent()),bookmark:bookmarks[$0.id],fade:fadeMode(after:$0),position:positions[$0.id] ?? 0,title:$0.customTitle,occurrenceID:$0.occurrenceID,identity:$0.identity) },
            selectedIndex:tracks.firstIndex { $0.id == currentID },highlightedIndex:tracks.firstIndex { $0.id == selectedID },
            options:.init(startMode:startMode,endMode:endMode,stopBeforeEnd:stopBeforeEnd,shuffle:shuffle,repeatAll:repeatAll))
        try file.write(to:url); notePlaylist(url); persist()
    }
    func readPlaylist(from url: URL) throws {
        guard !setupLock.editsBlocked else { throw NSError(domain: "HARDPLAY", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unlock setup to open another playlist."]) }
        // Decode and resolve every entry before replacing the existing queue.
        let file = try SavedPlaylist.read(from:url)
        var resolved:[Track] = [], modes:[String:FadeMode] = [:], savedPositions:[String:Double] = [:], savedBookmarks:[String:Data] = [:]
        var selected:String?, missing = 0
        for (index,entry) in file.tracks.enumerated() {
            var target = URL(fileURLWithPath:entry.path,relativeTo:url.deletingLastPathComponent()).standardizedFileURL
            if !FileManager.default.fileExists(atPath:target.path), let data = entry.bookmark {
                var stale = false
                if let bookmarked = try? URL(resolvingBookmarkData:data,options:.withSecurityScope,bookmarkDataIsStale:&stale) { target = bookmarked }
            }
            if target.startAccessingSecurityScopedResource() { accessed.insert(target) }
            var track = Track(url:target,customTitle:entry.title,occurrenceID:entry.occurrenceID,identity:entry.identity)
            if resolved.contains(where:{$0.id == track.id}) { track.occurrenceID=UUID().uuidString }
            if file.selectedIndex == index { selected = track.id }
            guard !resolved.contains(where:{$0.id == track.id}) else { continue }
            resolved.append(track); modes[track.id] = entry.fade; savedPositions[track.id] = entry.position
            savedBookmarks[track.id] = (try? target.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)) ?? entry.bookmark
            if !FileManager.default.fileExists(atPath:target.path) { missing += 1 }
        }
        pause(); loadingTask?.cancel(); failureObservation = nil; cancelCrossfade(); clearEndBoundary()
        engine.replaceCurrentItem(with:nil); isLoading = false
        restoring = true
        resetDecks();waveformCues.removeAll(); tracks = resolved; selectedID=file.highlightedIndex.flatMap { resolved.indices.contains($0) ? resolved[$0].id:nil }; currentID = nil; elapsed = 0; duration = 0; positions = savedPositions; bookmarks = savedBookmarks; transitionModes = modes
        startMode = file.options.startMode; endMode = file.options.endMode; stopBeforeEnd = file.options.stopBeforeEnd
        shuffle = file.options.shuffle; repeatAll = file.options.repeatAll
        notePlaylist(url);playlistName=file.name.isEmpty ? "My Set":String(file.name.prefix(100)); restoring = false
        let first = selected.flatMap { id in resolved.first { $0.id == id } } ?? resolved.first
        if let first { load(first,autoplay:false,position:savedPositions[first.id] ?? 0) }
        if missing > 0 { error = "\(missing) audio file(s) are missing. Their positions in the playlist have been kept." }
        persist()
    }
    var canDeletePlaylist:Bool {playlistURL != nil || !tracks.isEmpty || playlistName != "My Set"}
    func newPlaylist(named name:String = "My Set") {
        guard !setupLock.editsBlocked,!ControlLock.shared.isLocked else {return}
        rememberPosition();recordEdit();pause();loadingTask?.cancel();failureObservation=nil;cancelCrossfade();clearEndBoundary()
        engine.replaceCurrentItem(with:nil);isLoading=false;restoredTime=0;stoppedAtBoundary=false
        let clean=String(name.replacingOccurrences(of:"\n",with:" ").replacingOccurrences(of:"\r",with:" ").trimmingCharacters(in:.whitespacesAndNewlines).prefix(100))
        playlistURL=nil;playlistName=clean.isEmpty ? "My Set":clean
        resetDecks();tracks=[];selectedID=nil;currentID=nil;elapsed=0;duration=0
        waveformCues.removeAll();positions.removeAll();bookmarks.removeAll();transitionModes.removeAll();error=nil
        persist();nowPlaying()
    }
    /// Only the playlist document is trashed. Undo restores its queue as an unsaved set.
    func deletePlaylist(using trash:(URL)throws->Void = {try FileManager.default.trashItem(at:$0,resultingItemURL:nil)}) throws {
        guard !setupLock.editsBlocked,!ControlLock.shared.isLocked else {return}
        if let url=playlistURL {
            try trash(url) // failure leaves the queue and document binding intact
            recentPlaylists.removeAll {$0.standardizedFileURL == url.standardizedFileURL}
            playlistURL=nil
        }
        newPlaylist()
    }
    func requestNewPlaylist() {
        guard !setupLock.editsBlocked,!ControlLock.shared.isLocked else {return}
        let alert=NSAlert();alert.messageText="New Playlist"
        alert.informativeText=tracks.isEmpty ? "Name your new set.":"Creates an empty set and stops playback. Undo restores the current queue. Saved playlists stay on disk."
        let name=NSTextField(string:"My Set");name.frame=NSRect(x:0,y:0,width:280,height:28);name.placeholderString="Set name";alert.accessoryView=name
        alert.addButton(withTitle:"Create");alert.addButton(withTitle:"Cancel");alert.window.initialFirstResponder=name
        if alert.runModal() == .alertFirstButtonReturn {newPlaylist(named:name.stringValue)}
    }
    func requestDeletePlaylist() {
        guard !setupLock.editsBlocked,!ControlLock.shared.isLocked else {return}
        let saved=playlistURL != nil,alert=NSAlert();alert.messageText="Delete “\(playlistName)”?"
        alert.informativeText=saved ? "Moves this playlist document to Trash and clears the queue. Audio files stay where they are. Undo restores the queue as an unsaved set.":"Clears this unsaved playlist. Audio files stay where they are. Undo restores the queue."
        alert.addButton(withTitle:saved ? "Move Playlist to Trash":"Delete Playlist");alert.addButton(withTitle:"Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            do {try deletePlaylist()}catch {self.error="Could not delete playlist: \(error.localizedDescription)"}
        }
    }
    func savePlaylist(asNew: Bool = false) {
        guard !ControlLock.shared.isLocked else { return }
        if !asNew, let playlistURL {
            do { try writePlaylist(to:playlistURL) } catch { self.error = "Could not save playlist: \(error.localizedDescription)" }
            return
        }
        let panel = NSSavePanel(); panel.title = "Save Playlist"; panel.prompt = "Save"
        panel.message = "Saves track references, order, positions and transitions. Audio files stay where they are."
        panel.allowedContentTypes = [UTType(exportedAs:"local.hardplay.playlist",conformingTo:.json)]
        panel.canCreateDirectories = true; panel.isExtensionHidden = false
        panel.nameFieldStringValue = playlistName == "Untitled" ? "My Set.hardplay" : "\(playlistName).hardplay"
        if let playlistURL { panel.directoryURL = playlistURL.deletingLastPathComponent() }
        NSApp.activate(ignoringOtherApps:true)
        if panel.runModal() == .OK, let url = panel.url, !ControlLock.shared.isLocked {
            do { try writePlaylist(to:url) } catch { self.error = "Could not save playlist: \(error.localizedDescription)" }
        }
    }
    func openPlaylist(_ url: URL? = nil) {
        guard !setupLock.editsBlocked, !ControlLock.shared.isLocked else { return }
        if let url {
            do { try readPlaylist(from:url) } catch { self.error = "Could not open playlist: \(error.localizedDescription)" }
            return
        }
        let panel = NSOpenPanel(); panel.title = "Open Playlist"; panel.prompt = "Open"
        panel.allowedContentTypes = [UTType(exportedAs:"local.hardplay.playlist",conformingTo:.json),.json]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps:true)
        if panel.runModal() == .OK, let url = panel.url, !ControlLock.shared.isLocked { openPlaylist(url) }
    }
    func openFiles() {
        let panel = NSOpenPanel()
        guard !setupLock.editsBlocked, !ControlLock.shared.isLocked else { NSSound.beep(); return }
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = "Add"; panel.message = "Choose audio files or a music folder"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, !ControlLock.shared.isLocked { add(panel.urls) }
    }
    private func watchFailure(of item: AVPlayerItem) {
        failureObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            DispatchQueue.main.async {
                guard let self, let item, item === self.engine.currentItem, item.status == .failed else { return }
                self.loadingTask?.cancel(); self.isLoading = false
                self.cancelCrossfade(); self.pause()
                self.error = "Unable to decode this audio file. " + (item.error?.localizedDescription ?? "Check that the file is complete and uses a supported audio format.")
            }
        }
    }
    var crossfadeDiagnostics: (outgoingRate: Float, incomingRate: Float, outgoingVolume: Float, incomingVolume: Float, length: Double) {
        (outgoing?.rate ?? 0, engine.rate, outgoing?.volume ?? 0, engine.volume, fadeLength)
    }
    func load(_ track: Track, autoplay: Bool = true, position: Double? = nil, precisePosition:Bool = false) {
        rememberPosition()
        cancelCrossfade()
        let cue = waveformCues.removeValue(forKey:track.id)
        let exact = precisePosition || cue != nil
        let startOffset = position ?? cue ?? (startMode == .resume ? positions[track.id, default: 0] : 0)
        loadingTask?.cancel(); failureObservation = nil
        clearEndBoundary(); isLoading = true; stoppedAtBoundary = false; lastCheckpoint = -1
        if selectedID == nil || selectedID == currentID { selectedID=track.id }
        commitDeck(track.id)
        engine.pause(); playing = false; elapsed = 0; duration = 0; currentID = track.id; error = nil
        let attributes = try? FileManager.default.attributesOfItem(atPath: track.url.path)
        let fileIssue: String?
        if attributes == nil { fileIssue = "File unavailable: \(track.url.lastPathComponent)" }
        else if (attributes?[.size] as? NSNumber)?.int64Value == 0 { fileIssue = "This audio file is empty (0 bytes). Replace it with a complete audio file." }
        else if !FileManager.default.isReadableFile(atPath: track.url.path) { fileIssue = "This audio file cannot be read. Check its access permissions." }
        else { fileIssue = nil }
        if let fileIssue {
            isLoading = false; error = fileIssue; engine.replaceCurrentItem(with: nil); nowPlaying(); persist(); return
        }
        let asset = AVURLAsset(url: track.url)
        let item = AVPlayerItem(asset: asset)
        engine.replaceCurrentItem(with: item)
        watchFailure(of: item)
        loadingTask = Task { @MainActor [weak self] in
            do {
                let seconds = try await asset.load(.duration).seconds
                guard !Task.isCancelled, let self, self.currentID == track.id else { return }
                let playable = try await asset.load(.isPlayable)
                guard !Task.isCancelled, item === self.engine.currentItem else { return }
                guard playable, seconds.isFinite, seconds > 0, item.status != .failed else {
                    self.engine.pause(); self.engine.replaceCurrentItem(with: nil)
                    self.isLoading = false; self.playing = false
                    self.error = "Unable to decode this audio file. Check that it is complete and uses a supported audio format."
                    self.nowPlaying(); self.persist(); return
                }
                self.duration = seconds
                let target = exact ? min(max(0,startOffset),max(0,self.duration-1/600)) : (startOffset < self.duration - 0.1 ? max(0, startOffset) : 0)
                await self.engine.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                guard !Task.isCancelled else { return }
                self.isLoading = false; self.elapsed = target
                self.configureEndBoundary()
                if autoplay, item.status != .failed { self.engine.play(); self.playing = self.engine.rate > 0 }
                self.nowPlaying(); self.persist()
            } catch {
                guard !Task.isCancelled else { return }
                guard let self, item === self.engine.currentItem else { return }
                self.engine.pause(); self.engine.replaceCurrentItem(with: nil); self.isLoading = false
                self.error = "Unable to read this audio file. " + error.localizedDescription; self.playing = false
                self.nowPlaying(); self.persist()
            }
        }
        persist()
    }
    func toggle() {
        guard !setupLock.playbackBlocked else { return }
        guard !isLoading else { return }
        if !playing, let selected=selectedTrack, selected.id != currentID { play(selected); return }
        if engine.currentItem == nil || engine.currentItem?.status == .failed { if let track = current ?? tracks.first { load(track) }; return }
        if playing { pause() } else {
            if duration > 0 && elapsed >= duration - 0.1 { seek(0) }
            stoppedAtBoundary = false; engine.play(); outgoing?.play(); playing = engine.rate > 0
        }
        rememberPosition(); nowPlaying(); persist()
    }
    func backupPosition(_ track:Track)->Double { positions[track.id] ?? 0 }
    func rememberPosition() {
        guard !isLoading, let id = currentID else { return }
        positions[id] = elapsed
    }
    func pause() {
        engine.pause(); outgoing?.pause(); playing = false; rememberPosition(); nowPlaying(); persist()
    }
    func restart() {
        guard !setupLock.playbackBlocked else { return }
        guard let track = current else { return }
        load(track, autoplay: true, position: 0)
    }
    func resumeSaved() {
        guard !setupLock.playbackBlocked else { return }
        rememberPosition()
        guard let track = current else { return }
        load(track, autoplay: true, position: positions[track.id] ?? elapsed)
    }
    /// NEXT gestures set a one-shot cue; only an explicit double-click starts that deck.
    func waveformAction(_ track:Track,seconds:Double,duration knownDuration:Double,play:Bool) {
        guard !ControlLock.shared.isLocked,!setupLock.playbackBlocked,
              seconds.isFinite,knownDuration.isFinite,knownDuration>0,
              tracks.contains(where:{$0.id == track.id && $0.url == track.url}) else {return}
        let target=min(max(0,seconds),max(0,knownDuration-1/600))
        if play {
            guard !setupLock.selectionBlocked else {return}
            selectedID=track.id
            load(track,autoplay:true,position:target,precisePosition:true)
        }else if track.id == currentID {seek(target)}
        else if isCrossfading,track.id == outgoingTrack?.id {
            outgoing?.seek(to:CMTime(seconds:target,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
        }else {
            guard !setupLock.selectionBlocked,track.id == nextTrack?.id else {return}
            waveformCues[track.id]=target
            preparationTask?.cancel();preparationTask=nil;preparationID=nil
            prepared?.player.pause();prepared=nil;manualPreparation=false;failedPreparationSource=nil
        }
    }
    func seek(_ seconds: Double) {
        guard !setupLock.playbackBlocked else { return }
        guard !isLoading else { return }
        cancelCrossfade()
        elapsed = max(0, min(seconds, duration)); stoppedAtBoundary = false
        engine.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        rememberPosition(); configureEndBoundary(); nowPlaying(); persist()
    }
    func clearEndBoundary() {
        if let endBoundary { engine.removeTimeObserver(endBoundary); self.endBoundary = nil }
    }
    func configureEndBoundary() {
        clearEndBoundary()
        guard endMode == .stop, duration > 0, !isLoading else { return }
        // Short tracks retain their first half when the chosen tail exceeds their length.
        let cutoff = max(duration / 2, duration - max(0, stopBeforeEnd))
        guard cutoff > elapsed + 0.01, cutoff < duration else { return }
        endBoundary = engine.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: cutoff, preferredTimescale: 600))], queue: .main) { [weak self] in
            guard let self, self.endMode == .stop else { return }
            self.elapsed = cutoff; self.pause(); self.stoppedAtBoundary = true
        }
    }
    func next(automatic: Bool = false) {
        guard automatic || !setupLock.selectionBlocked else { return }
        guard !tracks.isEmpty else { return }
        if let target = upcomingTrack() {
            if automatic { load(target, position: waveformCues[target.id] ?? 0, precisePosition:waveformCues[target.id] != nil) } else { play(target) }
        } else if !automatic { play(tracks[0]) }
        else { pause() }
    }
    func previous() {
        guard !setupLock.selectionBlocked else { return }
        if elapsed > 3 { seek(0); return }
        guard !tracks.isEmpty else { return }
        let index = tracks.firstIndex { $0.id == currentID } ?? 0
        play(tracks[max(0, index - 1)])
    }
    private func invalidateQueuePreparation() {
        nextChoice=nil
        // Reordering and its Undo must not interrupt either engine during a live fade.
        if !isCrossfading {
            preparationTask?.cancel();preparationTask=nil;preparationID=nil;prepared?.player.pause();prepared=nil;manualPreparation=false;failedPreparationSource=nil
        }
    }
    @discardableResult func moveTrack(_ id:String,to index:Int)->Bool {
        guard !setupLock.editsBlocked,!ControlLock.shared.isLocked,tracks.indices.contains(index),let source=tracks.firstIndex(where:{$0.id==id}),source != index else {return false}
        recordEdit(orderOnly:true);var reordered=tracks;let track=reordered.remove(at:source);reordered.insert(track,at:index);tracks=reordered
        invalidateQueuePreparation();persist();return true
    }
    @discardableResult func moveTrack(_ id:String,relativeTo target:String,after:Bool)->Bool {
        guard id != target,tracks.contains(where:{$0.id==id}) else {return false}
        let others=tracks.filter {$0.id != id}
        guard let index=others.firstIndex(where:{$0.id==target}) else {return false}
        return moveTrack(id,to:index+(after ? 1:0))
    }
    func moveTrack(_ id:String,by offset:Int) {
        guard let index=tracks.firstIndex(where:{$0.id==id}) else {return};moveTrack(id,to:index+offset)
    }
    func remove(_ track: Track) {
        guard !setupLock.editsBlocked,tracks.contains(where:{$0.id == track.id}) else { return }
        recordEdit()
        if track.id == currentID {
            cancelCrossfade(); clearEndBoundary(); isLoading = false
            loadingTask?.cancel(); engine.pause(); engine.replaceCurrentItem(with: nil); playing = false; currentID = nil; elapsed = 0; duration = 0
        }
        waveformCues.removeValue(forKey:track.id); tracks.removeAll { $0.id == track.id }; if selectedID == track.id { selectedID=currentID ?? tracks.first?.id }; bookmarks.removeValue(forKey: track.id); positions.removeValue(forKey: track.id); transitionModes.removeValue(forKey: track.id); cancelCrossfade(); persist(); nowPlaying()
    }
    func nowPlaying() {
        guard publishNowPlaying else { return }
        guard let current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: current.title, MPMediaItemPropertyArtist: "HARDPLAY", MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed, MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0]
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }
    func configureRemote() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in DispatchQueue.main.async { if !ControlLock.shared.isLocked { self?.toggle() } }; return .success }
        center.playCommand.addTarget { [weak self] _ in DispatchQueue.main.async { if !ControlLock.shared.isLocked, self?.playing == false { self?.toggle() } }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in DispatchQueue.main.async { if !ControlLock.shared.isLocked, self?.playing == true { self?.toggle() } }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in DispatchQueue.main.async { if !ControlLock.shared.isLocked { self?.next() } }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in DispatchQueue.main.async { if !ControlLock.shared.isLocked { self?.previous() } }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            DispatchQueue.main.async { if !ControlLock.shared.isLocked { self?.seek(event.positionTime) } }; return .success
        }
    }
}

var accent: Color { Color(stageHex:AppearancePreferences.shared.theme.accent) }
func timeLabel(_ seconds: Double) -> String { let n = Int(max(0, seconds.isFinite ? seconds : 0)); return String(format: "%d:%02d", n / 60, n % 60) }

final class PlayerViewState: ObservableObject {
    @Published var patchOpen=false
    @Published var queueContentHeight:CGFloat=0
    @Published var search = ""
    @Published var targeted = false
    @Published var scrub: Double = 0
    @Published var scrubbing = false
    @Published var settings = false
    @Published var playlist = false
    @Published var protection = false
}

struct GlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

enum ControlOutline: Shape {
    case circle, rounded, capsule, hardware
    func path(in rect: CGRect) -> Path {
        switch self {
        case .circle: return Circle().path(in: rect)
        case .rounded: return RoundedRectangle(cornerRadius:8).path(in:rect)
        case .capsule: return Capsule().path(in: rect)
        case .hardware:return RoundedRectangle(cornerRadius:6).path(in:rect)
        }
    }
}

struct PlayerControlStyle: ButtonStyle {
    @ObservedObject var appearance = AppearancePreferences.shared
    var outline: ControlOutline = .rounded
    var active = false
    var primary = false
    @Environment(\.isEnabled) private var enabled
    private var surface:ControlOutline {
        if case .rounded=outline,["Road Case","Flightcase","Speaker Grille","FOH","Stage Crew","Stagehand"].contains(appearance.theme.preset) {return .hardware}
        return outline
    }
    func makeBody(configuration: Configuration) -> some View {
        let pressed=configuration.isPressed,lit=active || primary
        return configuration.label
            .foregroundStyle(Color(stageHex:appearance.theme.text).opacity(enabled ? 0.94:0.52))
            .background {
                surface.fill(Color(stageHex:appearance.theme.background))
                    .overlay(surface.fill(lit ? accent.opacity(pressed ? 0.20:0.13):.white.opacity(pressed ? 0.075:0.035)))
            }
            .overlay(surface.stroke(lit ? accent.opacity(0.38):.white.opacity(0.11),lineWidth:0.8))
            .shadow(color:.black.opacity(0.10),radius:1,y:0.5)
            .contentShape(surface).opacity(enabled ? 1:0.55)
            .scaleEffect(pressed ? 0.99:1)
            .animation(.easeOut(duration:0.12),value:pressed)
    }
}

struct TransitionControl: View {
    @ObservedObject var player: Player
    let track: Track
    var inQueue = false
    var body: some View {
        HStack(spacing: 8) {
            Text(inQueue ? "Fade →" : "Crossfade")
                .font(.stage(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Picker("Transition after \(track.title)", selection: Binding(get: { player.fadeMode(after: track) }, set: { player.setFadeMode($0, after: track) })) {
                ForEach(FadeMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
            }.pickerStyle(.segmented).labelsHidden().tint(accent)
                .stageHint("Transition after this track: Off, Short (3 s), Long (6 s)")
        }
    }
}


final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!
    var status: NSStatusItem!
    var popover: NSPopover!
    var mainWindow: NSWindow!
    var miniWindow: NSPanel!
    var playlistWindow: NSPanel!
    var mappingWindow: NSWindow!
    var settingsWindow: NSWindow!
    var themesWindow: NSWindow!
    var backupWindow: NSWindow!
    var viewerWindow:NSWindow!
    var quickEditWindow:NSWindow?
    var quickEditModel:QuickEditModel?
    private var quickEditWindowModel:QuickEditModel?
    var pocketWindow: NSPanel!
    var appearanceUpdates: AnyCancellable?
    var lockUpdates: AnyCancellable?
    var statusUpdates: AnyCancellable?
    var lastStatusBadge: MenuBarBadge?
    private var arrangingWorkspace=false
    var hotKey: EventHotKeyRef?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)
        _ = Player.shared
        makeMenu()
        status = NSStatusBar.system.statusItem(withLength: 46)
        if let button = status.button {
            button.image = MenuBarBadge.empty.image()
            button.target = self; button.action = #selector(statusClick(_:)); button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover = NSPopover(); popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PlayerView(compact: true, menuBar: true))
        makeWindows()
        if WorkspaceState.shared.mode == .single {workspaceModeChanged()}
        appearanceUpdates = AppearancePreferences.shared.objectWillChange.receive(on:RunLoop.main).sink { _ in Player.shared.objectWillChange.send() }
        statusUpdates = Player.shared.objectWillChange
            .throttle(for:.milliseconds(500),scheduler:RunLoop.main,latest:true)
            .receive(on:RunLoop.main).sink { [weak self] _ in self?.updateStatusItem() }
        lockUpdates = ControlLock.shared.objectWillChange.receive(on:RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            for window in [self.mainWindow,self.miniWindow,self.playlistWindow,self.mappingWindow,self.settingsWindow,self.themesWindow,self.backupWindow,self.viewerWindow] {
                window?.standardWindowButton(.miniaturizeButton)?.isEnabled = !ControlLock.shared.isLocked
            }
        }
        updateStatusItem()
        registerHotKey()
        _ = ControlMappings.shared
        if CommandLine.arguments.contains("--mini") { toggleMini() } else { showMain() }
        if let edge=PlaylistWindowState.shared.edge,PlaylistWindowState.shared.detached { PlaylistWindowState.shared.dock(edge) } else if PlaylistWindowState.shared.detached { showPlaylistWindow() }
    }
    func makeMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Add Audio…", action: #selector(addFiles), keyEquivalent: "o")
        appMenu.addItem(withTitle:"New Playlist…",action:#selector(newPlaylist),keyEquivalent:"n")
        appMenu.addItem(withTitle:"Delete Playlist…",action:#selector(deletePlaylist),keyEquivalent:"")
        appMenu.addItem(withTitle: "Save Playlist",action:#selector(savePlaylist),keyEquivalent:"s")
        let saveAs = appMenu.addItem(withTitle:"Save Playlist As…",action:#selector(savePlaylistAs),keyEquivalent:"s"); saveAs.keyEquivalentModifierMask = [.command,.shift]
        let open = appMenu.addItem(withTitle:"Open Playlist…",action:#selector(openPlaylist),keyEquivalent:"o"); open.keyEquivalentModifierMask = [.command,.shift]
        appMenu.addItem(withTitle:"Undo Playlist Edit",action:#selector(undoQueueEdit),keyEquivalent:"z")
        let redo=appMenu.addItem(withTitle:"Redo Playlist Edit",action:#selector(redoQueueEdit),keyEquivalent:"z");redo.keyEquivalentModifierMask=[.command,.shift]
        appMenu.addItem(withTitle:"PATCH…",action:#selector(showSettingsWindow),keyEquivalent:",")
        appMenu.addItem(withTitle:"Timecode & Backup…",action:#selector(showBackupWindow),keyEquivalent:"")
        appMenu.addItem(withTitle:"Web Viewer…",action:#selector(showWebViewer),keyEquivalent:"")
        appMenu.addItem(withTitle: "Show Hard Play", action: #selector(showMain), keyEquivalent: "1")
        appMenu.addItem(withTitle: "Mini Player", action: #selector(toggleMini), keyEquivalent: "2")
        appMenu.addItem(withTitle:"Keyboard / MIDI…",action:#selector(showMappings),keyEquivalent:"m").keyEquivalentModifierMask = [.command,.shift]
        appMenu.addItem(withTitle:"Minimize Window",action:#selector(minimizeFrontWindow),keyEquivalent:"m")
        appMenu.addItem(withTitle: "Lock Controls", action: #selector(lockControls), keyEquivalent: "l")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Hard Play", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
    }
    func makeWindows() {
        mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        mainWindow.contentMinSize = NSSize(width:600,height:620)
        mainWindow.isOpaque = false; mainWindow.backgroundColor = .clear
        mainWindow.appearance = NSAppearance(named: .darkAqua)
        mainWindow.title = "Hard Play"; mainWindow.titlebarAppearsTransparent = true
        mainWindow.titleVisibility = .hidden; mainWindow.isMovableByWindowBackground = true
        mainWindow.isReleasedWhenClosed = false; mainWindow.delegate = self
        mainWindow.contentView = NSHostingView(rootView: PlayerView().padding(.top, 20).background(ThemedBackdrop()).preferredColorScheme(.dark).font(.stage(.body)))
        mainWindow.center(); mainWindow.setFrameAutosaveName("HARDPLAY.stage.minimal.minimal.main")
        miniWindow = FloatingPanel(contentRect: NSRect(x: 100, y: 100, width: 380, height: 540), styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        miniWindow.isOpaque = false; miniWindow.backgroundColor = .clear
        miniWindow.appearance = NSAppearance(named: .darkAqua)
        miniWindow.title = "Hard Play Mini"; miniWindow.titleVisibility = .hidden; miniWindow.titlebarAppearsTransparent = true
        miniWindow.standardWindowButton(.closeButton)?.isHidden = true
        miniWindow.isMovableByWindowBackground = true;miniWindow.isMovable = !FloatingPlacement.shared.miniLocked; miniWindow.level = .floating
        miniWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        miniWindow.hidesOnDeactivate = false; miniWindow.isReleasedWhenClosed = false; miniWindow.delegate = self
        miniWindow.contentView = NSHostingView(rootView: PlayerView(compact: true).padding(.top, 8).background(ThemedBackdrop()))
        miniWindow.contentMinSize=NSSize(width:380,height:540);miniWindow.contentMaxSize=NSSize(width:760,height:1000)
        miniWindow.setFrameAutosaveName("HARDPLAY.stage.minimal.mini")
        playlistWindow = FloatingPanel(contentRect:NSRect(x:160,y:160,width:440,height:480),styleMask:[.titled,.closable,.miniaturizable,.resizable,.nonactivatingPanel,.fullSizeContentView],backing:.buffered,defer:false)
        playlistWindow.title = "Hard Play Playlist"; playlistWindow.titlebarAppearsTransparent = true
        playlistWindow.isOpaque = false; playlistWindow.backgroundColor = .clear
        playlistWindow.appearance = NSAppearance(named:.darkAqua)
        playlistWindow.level = .floating; playlistWindow.hidesOnDeactivate = false
        playlistWindow.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        playlistWindow.isReleasedWhenClosed = false; playlistWindow.delegate = self
        playlistWindow.isMovableByWindowBackground = true
        playlistWindow.contentMinSize = NSSize(width:380,height:280)
        playlistWindow.contentView = NSHostingView(rootView:PlayerView(playlistOnly:true).background(ThemedBackdrop()))
        playlistWindow.setFrameAutosaveName("HARDPLAY.playlist.detached")
        mappingWindow = NSWindow(contentRect:NSRect(x:200,y:180,width:540,height:620),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        mappingWindow.level = .floating
        mappingWindow.title = "Hard Play Keyboard / MIDI"; mappingWindow.isReleasedWhenClosed = false; mappingWindow.delegate = self
        mappingWindow.contentMinSize = NSSize(width:500,height:500)
        mappingWindow.appearance = NSAppearance(named:.darkAqua)
        mappingWindow.contentView = NSHostingView(rootView:MappingView().background(ThemedBackdrop()))
        mappingWindow.setFrameAutosaveName("HARDPLAY.mappings")
        pocketWindow = PocketPanel(contentRect:NSRect(x:100,y:100,width:344,height:320),styleMask:[.borderless,.nonactivatingPanel,.resizable],backing:.buffered,defer:false)
        pocketWindow.isOpaque=false;pocketWindow.backgroundColor = .clear;pocketWindow.level = .floating
        pocketWindow.title="Hard Play Pocket";pocketWindow.hasShadow=true;pocketWindow.isMovableByWindowBackground=true;pocketWindow.hidesOnDeactivate=false;pocketWindow.isReleasedWhenClosed=false
        pocketWindow.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        pocketWindow.contentView=NSHostingView(rootView:PocketPlayerView())
        pocketWindow.delegate=self;pocketWindow.isMovable = !FloatingPlacement.shared.pocketLocked
        pocketWindow.setFrameAutosaveName("HARDPLAY.pocket")
        if !pocketWindow.setFrameUsingName("HARDPLAY.pocket"),let frame=NSScreen.main?.visibleFrame { pocketWindow.setFrameOrigin(NSPoint(x:frame.maxX-360,y:frame.minY+24)) }
        pocketWindow.minSize=NSSize(width:344,height:320);pocketWindow.maxSize=NSSize(width:560,height:640)
        let restored=pocketWindow.frame;let limited=PocketPanel.limitedSize(restored.size)
        pocketWindow.setContentSize(limited)
        settingsWindow = utilityWindow(title:"Hard Play PATCH",width:370,height:500)
        settingsWindow.contentView = NSHostingView(rootView:PlayerView(settingsOnly:true).padding(20).background(ThemedBackdrop()).preferredColorScheme(.dark).font(.stage(.body)))
        themesWindow = utilityWindow(title:"Hard Play Themes",width:410,height:760)
        themesWindow.contentView = NSHostingView(rootView:ThemeEditorView().background(ThemedBackdrop()).preferredColorScheme(.dark).font(.stage(.body)))
    }
    func showQuickEdit(_ track:Track) {
        guard !SetupLock.shared.editsBlocked,!ControlLock.shared.isLocked else {return}
        let model:QuickEditModel
        if let existing=quickEditModel,existing.busy || existing.track.id == track.id {model=existing}
        else {quickEditModel?.close();model=QuickEditModel(track);quickEditModel=model}
        WorkspaceState.shared.editor=model
        if WorkspaceState.shared.present(.editor) {return}
        let window=quickEditWindow ?? utilityWindow(title:"Hard Play Quick Edit",width:760,height:780)
        window.contentMinSize=NSSize(width:620,height:650)
        if quickEditWindowModel !== model {
            window.contentView=NSHostingView(rootView:QuickEditView(edit:model).background(ThemedBackdrop()).preferredColorScheme(.dark).font(.stage(.body)))
            quickEditWindowModel=model
        }
        quickEditWindow=window;restore(window);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func showWebViewer() {
        if WorkspaceState.shared.present(.viewer) {return}
        guard !SetupLock.shared.settingsBlocked,!ControlLock.shared.isLocked else {return}
        if viewerWindow == nil {
            viewerWindow=utilityWindow(title:"Hard Play Web Viewer",width:420,height:720)
            viewerWindow.contentView=NSHostingView(rootView:WebViewerView().background(ThemedBackdrop()).preferredColorScheme(.dark).font(.stage(.body)))
            viewerWindow.contentMinSize=NSSize(width:380,height:500);viewerWindow.center()
        }
        restore(viewerWindow);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func showBackupWindow() {
        if WorkspaceState.shared.present(.backup) {return}
        guard !SetupLock.shared.settingsBlocked,!ControlLock.shared.isLocked else {return}
        if backupWindow == nil {
            backupWindow=utilityWindow(title:"Hard Play Timecode & Backup",width:500,height:690)
            backupWindow.contentView=NSHostingView(rootView:BackupView().background(ThemedBackdrop()).preferredColorScheme(.dark).font(.stage(.body)))
            backupWindow.contentMinSize=NSSize(width:440,height:540)
            backupWindow.center()
        }
        restore(backupWindow);NSApp.activate(ignoringOtherApps:true)
    }
    var workspaceWindows:[NSWindow] {
        var windows=[quickEditWindow,themesWindow,mappingWindow,backupWindow,viewerWindow,settingsWindow].compactMap {$0}
        if PlaylistWindowState.shared.detached,PlaylistWindowState.shared.edge == nil,let playlistWindow {windows.append(playlistWindow)}
        return windows
    }
    private func workspaceSection(for window:NSWindow)->WorkspaceSection? {
        if window === quickEditWindow {return .editor};if window === themesWindow {return .themes};if window === mappingWindow {return .mappings}
        if window === backupWindow {return .backup};if window === viewerWindow {return .viewer};if window === settingsWindow {return .settings};return nil
    }
    func hideWorkspacePanel(_ target:WorkspaceSection) {
        workspaceWindows.first(where:{workspaceSection(for:$0)==target})?.orderOut(nil)
    }
    func makeRoomForWorkspace() {
        guard let window=mainWindow,let screen=window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame,!window.styleMask.contains(.fullScreen) else {return}
        window.contentMinSize=NSSize(width:min(700,screen.width),height:min(650,max(420,screen.height-28)))
        var frame=EmbeddedPlaylistLayout.fittedFrame(current:window.frame,visible:screen,height:max(window.frame.height,800))
        frame.size.width=min(screen.width,max(700,frame.width));frame.origin.x=min(max(screen.minX,frame.minX),screen.maxX-frame.width)
        window.setFrame(frame,display:true)
    }
    func workspaceModeChanged() {
        let workspace=WorkspaceState.shared
        if workspace.mode == .single {
            let eligible=workspaceWindows.filter {window in workspaceSection(for:window).map {workspace.destination($0) == .workspace} ?? true}
            let target=eligible.first(where:{$0.isKeyWindow}).flatMap(workspaceSection) ?? eligible.first(where:{$0.isVisible}).flatMap(workspaceSection)
            workspace.editor=quickEditModel;if let target {workspace.section=target}
            quickEditModel?.hover(nil);quickEditModel?.stopPreview()
            for window in eligible {window.orderOut(nil)}
            if PlaylistWindowState.shared.detached {PlaylistWindowState.shared.attach(toMini:false)}
            showMain();if target != nil {makeRoomForWorkspace()}
        }else {
            let target=workspace.section
            if let target,workspace.destination(target) != .workspace {arrangeWorkspaceWindows();return}
            workspace.section=nil
            switch target {
            case .settings:showSettingsWindow()
            case .themes:showThemesWindow()
            case .mappings:showMappings()
            case .backup:showBackupWindow()
            case .viewer:showWebViewer()
            case .editor:if let track=quickEditModel?.track {showQuickEdit(track)}
            case nil:break
            }
            arrangeWorkspaceWindows();WindowPresentation.shared.requestFit()
        }
    }
    func arrangeWorkspaceWindows(preferred:NSWindow?=nil) {
        guard !arrangingWorkspace,let main=mainWindow,main.isVisible,!main.styleMask.contains(.fullScreen),let screen=main.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {return}
        arrangingWorkspace=true;defer {arrangingWorkspace=false}
        var windows=workspaceWindows.filter {window in
            window.isVisible && !window.isMiniaturized && (workspaceSection(for:window).map {WorkspaceState.shared.followsPlayer($0)} ?? (WorkspaceState.shared.mode == .nearby))
        }
        if let preferred,let i=windows.firstIndex(where:{$0 === preferred}) {windows.insert(windows.remove(at:i),at:0)}
        let frames=WorkspaceLayout.frames(main:main.frame,screen:screen,sizes:windows.map { $0.frame.size })
        for (window,frame) in zip(windows,frames) where window.frame != frame {window.setFrame(frame,display:true)}
    }
    func utilityWindow(title:String,width:CGFloat,height:CGFloat)->NSWindow {
        let window=NSWindow(contentRect:NSRect(x:200,y:100,width:width,height:height),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title=title;window.isReleasedWhenClosed=false;window.delegate=self
        window.contentMinSize=NSSize(width:350,height:450);window.appearance=NSAppearance(named:.darkAqua)
        window.isOpaque=false;window.backgroundColor = .clear;window.level = .floating
        window.setFrameAutosaveName(title)
        return window
    }
    @objc func showSettingsWindow() {
        if WorkspaceState.shared.present(.settings) {return}
        guard !ControlLock.shared.isLocked else { return }
        if !settingsWindow.isVisible,WorkspaceState.shared.followsPlayer(.settings) { settingsWindow.setFrameOrigin(NSPoint(x:mainWindow.frame.maxX+12,y:mainWindow.frame.maxY-settingsWindow.frame.height)); settingsWindow.setFrame(settingsWindow.constrainFrameRect(settingsWindow.frame,to:mainWindow.screen),display:true) }
        restore(settingsWindow);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func showThemesWindow() {
        if WorkspaceState.shared.present(.themes) {return}
        guard !SetupLock.shared.settingsBlocked,!ControlLock.shared.isLocked else { return }
        if !themesWindow.isVisible,WorkspaceState.shared.followsPlayer(.themes) { themesWindow.setFrameOrigin(NSPoint(x:settingsWindow.frame.maxX+12,y:settingsWindow.frame.maxY-themesWindow.frame.height)) }
        themesWindow.setFrame(themesWindow.constrainFrameRect(themesWindow.frame,to:mainWindow.screen),display:true)
        restore(themesWindow);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func statusClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Queue", action: #selector(showMain), keyEquivalent: "")
            menu.addItem(withTitle: "Show / Hide Mini Player", action: #selector(toggleMini), keyEquivalent: "")
            menu.addItem(withTitle:"Show Playlist Window",action:#selector(restorePlaylist),keyEquivalent:"")
            menu.addItem(withTitle:"Keyboard / MIDI…",action:#selector(showMappings),keyEquivalent:"")
            menu.addItem(withTitle:MenuBarPresentation.shared.attached ? "Detach Mini Player":"Attach Mini to Menu Bar",action:#selector(toggleMenuBarAttachment),keyEquivalent:"")
            menu.addItem(withTitle: "Add Audio…", action: #selector(addFiles), keyEquivalent: "")
            menu.addItem(.separator()); menu.addItem(withTitle: "Quit Hard Play", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
            status.menu = menu; status.button?.performClick(nil); status.menu = nil
        } else if !MenuBarPresentation.shared.attached { toggleMini() }
        else if popover.isShown { popover.performClose(nil) }
        else { showMenuBarPlayer() }
    }
    func toggleWideLayout() {
        guard !ControlLock.shared.isLocked else { return }
        let screen = mainWindow.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var frame = mainWindow.frame
        frame.size.width = min(frame.width >= 840 ? 600 : 1040,screen.width)
        frame.origin.x = min(max(screen.minX,frame.minX),screen.maxX-frame.width)
        mainWindow.setFrame(frame,display:true,animate:true)
    }
    func fitMainContent(_ height:CGFloat) {
        guard WindowPresentation.shared.autoFit,height>0,!ControlLock.shared.isLocked,WorkspaceState.shared.section == nil,
              let window=mainWindow,!window.styleMask.contains(.fullScreen),
              let screen=window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {return}
        let content=height+20+(HintPreferences.shared.enabled ? HintMetrics.totalHeight:0)
        let chrome=max(0,window.frame.height-window.contentLayoutRect.height)
        let targetHeight=content+chrome+4
        window.contentMinSize=NSSize(width:min(600,screen.width),height:min(420,screen.height-28))
        let frame=EmbeddedPlaylistLayout.fittedFrame(current:window.frame,visible:screen,height:targetHeight)
        if abs(frame.height-window.frame.height)>1 || abs(frame.minY-window.frame.minY)>1 {window.setFrame(frame,display:true)}
    }
    func ensureEmbeddedPlaylistRoom() {
        if WindowPresentation.shared.autoFit {WindowPresentation.shared.requestFit();return}
        guard !PlaylistWindowState.shared.detached,let window=mainWindow,!window.styleMask.contains(.fullScreen),
              let screen=window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {return}
        window.contentMinSize=NSSize(width:min(600,screen.width),height:min(740,max(620,screen.height-28)))
        let frame=EmbeddedPlaylistLayout.frame(current:window.frame,visible:screen,tracks:Player.shared.tracks.count)
        if frame != window.frame {window.setFrame(frame,display:true)}
    }
    @objc func showMain() { defer {WindowPresentation.shared.refresh()}; pocketWindow?.orderOut(nil); popover?.performClose(nil); ensureEmbeddedPlaylistRoom(); restore(mainWindow); NSApp.activate(ignoringOtherApps: true) }
    @objc func showMappings() {
        if WorkspaceState.shared.present(.mappings) {return}
        guard !ControlLock.shared.isLocked else { return }
        restore(mappingWindow); NSApp.activate(ignoringOtherApps:true)
    }
    func windowWillClose(_ notification:Notification) {
        if let window = notification.object as? NSWindow {
            if window === quickEditWindow {quickEditWindowModel?.close()}
            if window === mappingWindow { ControlMappings.shared.mapping = false }
            if window === miniWindow || window === playlistWindow { DispatchQueue.main.async { PlaylistWindowState.shared.syncVisibility();ControlMappings.shared.refreshStates() } }
        }
    }
    func showMini() { defer {WindowPresentation.shared.refresh()}; restore(miniWindow); ControlMappings.shared.refreshStates() }
    func showPlaylistWindow() { if WorkspaceState.shared.mode == .single {WorkspaceState.shared.toggle()}; restore(playlistWindow);PlaylistWindowState.shared.syncVisibility();ControlMappings.shared.refreshStates() }
    func toggleNano() {
        guard !ControlLock.shared.isLocked else {return}
        if pocketWindow.isVisible && !pocketWindow.isMiniaturized {pocketWindow.orderOut(nil)}else {showPocket()}
        WindowPresentation.shared.refresh()
    }
    func toggleStageFullScreen() {
        guard !ControlLock.shared.isLocked else {return}
        showMain();mainWindow.toggleFullScreen(nil)
    }
    func windowDidEnterFullScreen(_ notification:Notification) {WindowPresentation.shared.refresh()}
    func windowDidExitFullScreen(_ notification:Notification) {WindowPresentation.shared.refresh();WindowPresentation.shared.requestFit()}
    func windowDidBecomeKey(_ notification:Notification) {WindowPresentation.shared.refresh()}
    @objc func toggleMini() { defer {WindowPresentation.shared.refresh()}; if miniWindow.isVisible && !miniWindow.isMiniaturized { miniWindow.orderOut(nil); ControlMappings.shared.refreshStates() } else { showMini() } }
    func restore(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        if workspaceWindows.contains(where:{$0 === window}) {arrangeWorkspaceWindows(preferred:window)}
    }
    func minimize(_ window: NSWindow) {
        guard !ControlLock.shared.isLocked else { return }
        if window.styleMask.contains(.miniaturizable) { window.miniaturize(nil) } else { window.orderOut(nil) }
        ControlMappings.shared.refreshStates()
    }
    @objc func minimizeFrontWindow() {
        if popover.isShown { popover.performClose(nil) }
        else if let window = NSApp.keyWindow { minimize(window) }
    }
    @objc func restorePlaylist() { PlaylistWindowState.shared.detach() }
    func showMenuBarPlayer() {
        guard !popover.isShown, let button=status.button else { return }
        popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
    }
    func attachMiniToMenuBar(hideMain: Bool = false) {
        guard !ControlLock.shared.isLocked else { return }
        MenuBarPresentation.shared.setAttached(true)
        miniWindow.orderOut(nil)
        if hideMain { mainWindow.orderOut(nil) }
        NSApp.activate(ignoringOtherApps:true); showMenuBarPlayer()
    }
    func detachMiniFromMenuBar() {
        guard !ControlLock.shared.isLocked else { return }
        let frame=popover.isShown ? popover.contentViewController?.view.window?.frame : nil
        popover.performClose(nil); MenuBarPresentation.shared.setAttached(false)
        if let frame { miniWindow.setFrameOrigin(NSPoint(x:frame.minX,y:frame.maxY-miniWindow.frame.height)) }
        showMini(); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func toggleMenuBarAttachment() {
        if MenuBarPresentation.shared.attached { detachMiniFromMenuBar() } else { attachMiniToMenuBar() }
    }
    func updateStatusItem() {
        let player=Player.shared
        let badge=MenuBarBadge.state(hasTrack:player.current != nil,playing:player.playing,crossfading:player.isCrossfading,error:player.error)
        if lastStatusBadge != badge { status.button?.image=badge.image(); lastStatusBadge=badge }
        let details=player.current.map { " — \($0.title) · \(timeLabel(player.elapsed)) / \(timeLabel(player.duration))" } ?? ""
        status.button?.toolTip="Hard Play · \(badge.title)\(details)\nClick: player · Right-click: windows"
        status.button?.setAccessibilityLabel("Hard Play — \(badge.title)")
    }
    func windowDidMove(_ notification:Notification) {
        if notification.object as? NSWindow === mainWindow {arrangeWorkspaceWindows()}
        if let window=notification.object as? NSWindow { PlaylistWindowState.shared.ownerMoved(window);if window === pocketWindow { window.saveFrame(usingName:"HARDPLAY.pocket");updatePocketEdge() } else if window === miniWindow { window.saveFrame(usingName:"HARDPLAY.stage.minimal.mini") } }
    }
    func windowDidResize(_ notification:Notification) {
        if notification.object as? NSWindow === mainWindow {WindowPresentation.shared.requestFit();arrangeWorkspaceWindows()}
        if let window=notification.object as? NSWindow { PlaylistWindowState.shared.ownerMoved(window);if window === pocketWindow {window.saveFrame(usingName:"HARDPLAY.pocket");updatePocketEdge()} }
    }
    func windowWillResize(_ sender:NSWindow,to frameSize:NSSize)->NSSize {
        if sender === pocketWindow {return FloatingPlacement.shared.pocketLocked ? sender.frame.size:PocketPanel.limitedSize(frameSize)}
        if sender === miniWindow,FloatingPlacement.shared.miniLocked {return sender.frame.size}
        return frameSize
    }
    func windowDidMiniaturize(_ notification:Notification) {defer {WindowPresentation.shared.refresh()}; if let w=notification.object as? NSWindow,(w === mainWindow || w === miniWindow),WindowPresentation.shared.nanoOnMinimize { showPocket() };PlaylistWindowState.shared.syncVisibility();ControlMappings.shared.refreshStates() }
    func windowDidDeminiaturize(_ notification:Notification) {defer {WindowPresentation.shared.refresh()};PlaylistWindowState.shared.syncVisibility();ControlMappings.shared.refreshStates() }
    @objc func lockControls() { ControlLock.shared.lock(); showMain() }
    func updatePocketEdge() {
        let near=pocketWindow.screen.map { pocketWindow.frame.minX < $0.visibleFrame.minX } ?? false
        if FloatingPlacement.shared.pocketNearLeftEdge != near { FloatingPlacement.shared.pocketNearLeftEdge=near }
    }
    func showPocket() { defer {WindowPresentation.shared.refresh()};
        // Preserve the user's position, including when the widget is hidden and restored.
        if !NSScreen.screens.contains(where:{$0.visibleFrame.contains(pocketWindow.frame)}),let screen=NSScreen.main { pocketWindow.setFrame(pocketWindow.constrainFrameRect(pocketWindow.frame,to:screen),display:false) }
        updatePocketEdge();pocketWindow.orderFront(nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !ControlLock.shared.isLocked else { return false }
        if sender === mainWindow || sender === miniWindow { sender.orderOut(nil);if WindowPresentation.shared.nanoOnMinimize {showPocket()};WindowPresentation.shared.refresh();return false }
        return true
    }
    @objc func undoQueueEdit() { Player.shared.undoEdit() }
    @objc func redoQueueEdit() { Player.shared.redoEdit() }
    @objc func newPlaylist() {Player.shared.requestNewPlaylist()}
    @objc func deletePlaylist() {Player.shared.requestDeletePlaylist()}
    @objc func savePlaylist() { Player.shared.savePlaylist() }
    @objc func savePlaylistAs() { Player.shared.savePlaylist(asNew:true) }
    @objc func openPlaylist() { Player.shared.openPlaylist() }
    @objc func addFiles() { Player.shared.openFiles() }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard !ControlLock.shared.isLocked else { sender.reply(toOpenOrPrint:.cancel); return }
        let urls = filenames.map { URL(fileURLWithPath:$0) }
        if let playlist = urls.first(where:{$0.pathExtension.lowercased() == "hardplay"}) { Player.shared.openPlaylist(playlist) }
        let audio = urls.filter { $0.pathExtension.lowercased() != "hardplay" }
        if !audio.isEmpty { Player.shared.add(audio) }
        sender.reply(toOpenOrPrint:.success)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        if popover.isShown || (miniWindow.isVisible && !miniWindow.isMiniaturized) { return true }
        showMain(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { Player.shared.pause(); if let hotKey { UnregisterEventHotKey(hotKey) } }
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event!,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
            guard id.signature == 0x48504C59 else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { if !ControlLock.shared.isLocked, !ControlMappings.shared.mapping { Player.shared.toggle() } }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: 0x48504C59, id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
}

_ = StageTypography.name

if CommandLine.arguments.contains("--style-check") {
    precondition(StageTypography.name.lowercased().contains("balsamiq"))
    precondition(NSFont(name:StageTypography.name,size:14) != nil)
    precondition(NSFont(name:CrewMarker.name,size:18) != nil && CrewMarker.name.contains("PermanentMarker"))
    precondition(HardPlayBrand.artwork != nil)
    for name in ["Tape Blue","Tape White","Tape Black","FOH","Stage Crew","Stagehand"] {let theme=StageTheme.named(name);precondition(theme.preset == name && theme.texture)}
    print("PASS: bundled marker font registered as \(StageTypography.name), dedicated mini marker font, approved beam artwork and tape/crew presets available")
} else if CommandLine.arguments.contains("--waveform-test") {
    Task { @MainActor in do {try await runWaveformTests();exit(0)}catch {print("FAIL: \(error.localizedDescription)");exit(1)} };RunLoop.main.run()
} else if CommandLine.arguments.contains("--viewer-test") {
    Task { @MainActor in do {try await runViewerTests();exit(0)}catch {print("FAIL: \(error.localizedDescription)");exit(1)} };RunLoop.main.run()
} else if CommandLine.arguments.contains("--viewer-fixture") {
    Task { @MainActor in await runViewerFixture() };RunLoop.main.run()
} else if CommandLine.arguments.contains("--clip-test") {
    Task { @MainActor in do {try await runClipTests();exit(0)}catch {print("FAIL: \(error.localizedDescription)");exit(1)} };RunLoop.main.run()
} else if CommandLine.arguments.contains("--backup-test") || CommandLine.arguments.contains("--backup-link-test") {
    Task { @MainActor in
        do {try await runBackupTests(network:CommandLine.arguments.contains("--backup-link-test"));exit(0)}
        catch {print("FAIL: \(error.localizedDescription)");exit(1)}
    }
    RunLoop.main.run()
} else if let iconIndex = CommandLine.arguments.firstIndex(of: "--make-icon"), CommandLine.arguments.count > iconIndex + 1 {
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSColor(calibratedRed: 0.065, green: 0.11, blue: 0.19, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 45, y: 45, width: 934, height: 934), xRadius: 210, yRadius: 210).fill()
    NSColor(calibratedRed: 0.58, green: 0.77, blue: 0.96, alpha: 1).setFill()
    for (index, height) in [180.0, 340, 490, 290, 410, 180].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 222 + Double(index) * 100, y: (1024 - height) / 2, width: 56, height: height), xRadius: 28, yRadius: 28).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[iconIndex + 1]))
} else if CommandLine.arguments.contains("--button-mode-test") {
    let suite = "local.hardplay.button-mode.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName:suite)!
    let protection = SetupLock(defaults:prefs)
    let p = Player(defaults:prefs,remoteCommands:false,setupLock:protection)
    let c = ControlMappings(defaults:prefs,liveIO:false,player:p,setupLock:protection)
    func action(_ name:String) -> MappedAction { .init(rawValue:name) }
    p.shuffle = false
    c.trigger(action("shuffle"),behavior:.trigger); c.trigger(action("shuffle"),behavior:.trigger)
    precondition(p.shuffle)
    c.trigger(action("shuffle"),behavior:.toggle); precondition(!p.shuffle)
    p.shuffle = true // A direct UI change must be reflected in Toggle, not a cached latch.
    c.trigger(action("shuffle"),behavior:.toggle); precondition(!p.shuffle && c.isOn(action("shuffle")) == false)
    p.volume = 0.35
    c.trigger(action("mute"),behavior:.trigger); c.trigger(action("mute"),behavior:.trigger); precondition(p.volume == 0)
    c.trigger(action("mute"),behavior:.toggle); precondition(abs(p.volume - 0.35) < 0.0001)
    c.trigger(action("mute"),behavior:.toggle); precondition(p.volume == 0)
    let restored = ControlMappings(defaults:prefs,liveIO:false,player:p,setupLock:protection)
    restored.trigger(action("mute"),behavior:.toggle); precondition(abs(p.volume - 0.35) < 0.0001)
    p.volume = 0.65; precondition(c.isOn(action("mute")) == false)
    c.trigger(action("stopAtEnd"),behavior:.toggle); precondition(p.endMode == .stop)
    c.trigger(action("stopAtEnd"),behavior:.toggle); precondition(p.endMode == .next)
    p.add([URL(fileURLWithPath:"/tmp/hardplay-mode-\(UUID().uuidString).wav")])
    c.trigger(action("fadeShort"),behavior:.trigger); c.trigger(action("fadeShort"),behavior:.trigger)
    precondition(p.fadeMode(after:p.tracks[0]) == .short)
    c.trigger(action("fadeShort"),behavior:.toggle); precondition(p.fadeMode(after:p.tracks[0]) == .none)
    c.trigger(action("fadeShort"),behavior:.toggle); precondition(p.fadeMode(after:p.tracks[0]) == .short)
    let repeatAction = action("repeat")
    c.assign(.init(action:repeatAction,input:.midi,label:"Note 60",status:0x90,channel:0,number:60,source:12,behavior:.toggle))
    p.repeatAll = false
    c.receiveMIDI([0x90,60,127,60,127],source:12); precondition(p.repeatAll)
    c.receiveMIDI([0x80,60,0,0x90,60,127],source:12); precondition(!p.repeatAll)
    c.setBehavior(.trigger,for:repeatAction,input:.midi)
    c.receiveMIDI([0x80,60,0,0x90,60,127,0x80,60,0,0x90,60,127],source:12); precondition(p.repeatAll)
    let saved = ControlMappings(defaults:prefs,liveIO:false,player:p,setupLock:protection)
    precondition(saved.behavior(repeatAction,input:.midi) == .trigger)
    var legacy = ControlMapSet(name:"Legacy",bindings:[.init(action:action("playPause"),input:.keyboard,label:"P",key:35,modifiers:0)])
    legacy.version = 1
    let decoded = try JSONDecoder().decode(ControlMapSet.self,from:JSONEncoder().encode(legacy))
    precondition(ControlMappings.valid(decoded) && decoded.bindings[0].effectiveBehavior == .toggle)
    precondition(!ControlBinding(action:action("next"),input:.keyboard,label:"N",key:45,modifiers:0,behavior:.toggle).valid)
    precondition(!ControlBinding(action:action("lock"),input:.keyboard,label:"L",key:37,modifiers:0,behavior:.toggle).valid)
    precondition(!ControlBinding(action:action("volume"),input:.midi,label:"CC 7",status:0xB0,channel:0,number:7,source:12,behavior:.toggle).valid)
    protection.protectEdits = false; protection.protectSelection = false; protection.protectPlayback = false
    protection.lockSettings(); let before = c.bindings
    c.setBehavior(.toggle,for:repeatAction,input:.midi); c.clear(repeatAction,input:.midi)
    c.assign(.init(action:action("shuffle"),input:.keyboard,label:"S",key:1,modifiers:0)); c.learn(action("shuffle"))
    precondition(c.bindings == before && !c.mapping && protection.settingsBlocked)
    c.trigger(repeatAction,behavior:.toggle); precondition(!p.repeatAll) // Locked configuration still executes existing controls.
    c.trigger(action("lockSetup"),behavior:.toggle); precondition(!protection.settingsBlocked)
    c.setBehavior(.toggle,for:repeatAction,input:.midi); precondition(c.behavior(repeatAction,input:.midi) == .toggle)
    protection.protectPlayback = true; protection.lock()
    let volume = p.volume; c.trigger(action("mute"),behavior:.toggle); precondition(p.volume == volume)
    protection.unlock()
    prefs.removePersistentDomain(forName:suite)
    print("PASS: Trigger/Toggle, live state, mute restore, MIDI press edges, mode persistence, legacy sets, invalid modes, settings protection and unlock")
} else if CommandLine.arguments.contains("--workspace-test") {
    func verify(_ value:Bool,line:UInt = #line) {if !value {print("FAIL workspace test at line \(line)");exit(1)}}
    let suite="local.hardplay.workspace-test.\(UUID().uuidString)"
    let prefs=UserDefaults(suiteName:suite)!
    defer {prefs.removePersistentDomain(forName:suite)}
    prefs.set("nearby",forKey:"workspaceMode")
    let workspace=WorkspaceState(defaults:prefs)
    verify(workspace.resolved(.themes) == .nearby)
    workspace.setDestination(.inside,for:.themes)
    workspace.setDestination(.independent,for:.editor)
    workspace.setDestination(.ask,for:.settings)
    let restored=WorkspaceState(defaults:prefs)
    verify(restored.resolved(.themes) == .inside && restored.resolved(.editor) == .independent && restored.resolved(.settings) == .ask)
    prefs.set(["viewer":"invalid"],forKey:"windowDestinations")
    verify(WorkspaceState(defaults:prefs).destination(.viewer) == .workspace)
    let buttons=QuickActions(defaults:prefs),themes=MappedAction(rawValue:"themes")
    buttons.add(themes);let id=buttons.buttons[0].id
    verify(buttons.buttons[0].behavior == .trigger)
    buttons.behavior(.toggle,id:id);verify(buttons.buttons[0].behavior == .trigger)
    buttons.assign(MappedAction(rawValue:"mini"),to:id);verify(buttons.buttons[0].behavior == .toggle)
    buttons.add(MappedAction(rawValue:"volume"));verify(buttons.buttons.count==1)
    for _ in 0..<5 {buttons.add(themes)}
    verify(buttons.buttons.count==4 && QuickActions(defaults:prefs).buttons==buttons.buttons)
    ControlLock.shared.lock();buttons.remove(id);verify(buttons.buttons.count==4)
    workspace.setDestination(.nearby,for:.themes);verify(workspace.destination(.themes) == .inside)
    verify(!ControlLock.shared.unlock(heldFor:2.99));_ = ControlLock.shared.unlock(heldFor:3)
    var ring=CircularUnlockProgress()
    let center=CGPoint.zero
    func point(_ degrees:Double)->CGPoint {CGPoint(x:cos(degrees * .pi/180)*60,y:sin(degrees * .pi/180)*60)}
    ring.begin(point(90),center:center)
    for step in 1...32 {verify(!ring.move(point(90-Double(step)*10),center:center))}
    verify(ring.move(point(-250),center:center))
    ring.begin(point(90),center:center);verify(!ring.move(point(-90),center:center) && ring.degrees==0)
    ring.begin(point(90),center:center);verify(!ring.move(center,center:center));verify(!ring.move(point(60),center:center))
    ring.begin(point(90),center:center)
    for step in 1...36 {_ = ring.move(point(90+Double(step)*10),center:center)}
    verify(ring.degrees==0)
    ring.begin(point(90),center:center);_ = ring.move(point(40),center:center);_ = ring.move(point(70),center:center);verify(abs(ring.degrees-20)<0.001)
    buttons.remove(id);verify(buttons.buttons.count==3)
    print("PASS: window destination persistence, unknown fallback, quick assignments/modes/limits, protected edits, continuous circular unlock, rejected jumps/straight drags/reverse motion, three-second hold")
} else if CommandLine.arguments.contains("--mapping-test") {
    let suite = "local.hardplay.mapping-test.\(UUID().uuidString)"
    let isolated = UserDefaults(suiteName:suite)!
    var fired:[String] = []
    let controls = ControlMappings(defaults:isolated,liveIO:false) { fired.append($0.rawValue) }
    let storage = UnsafeMutableRawPointer.allocate(byteCount:2048,alignment:16)
    let packets = storage.bindMemory(to:MIDIPacketList.self,capacity:1)
    var packet = MIDIPacketListInit(packets)
    let a:[UInt8] = [0x90,60,127], b:[UInt8] = [0x80,60,0]
    packet = a.withUnsafeBufferPointer { MIDIPacketListAdd(packets,2048,packet,1,a.count,$0.baseAddress!) }
    packet = b.withUnsafeBufferPointer { MIDIPacketListAdd(packets,2048,packet,2,b.count,$0.baseAddress!) }
    precondition(ControlMappings.packetBytes(UnsafePointer(packets)) == a + b)
    storage.deallocate()
    let play = MappedAction(rawValue:"playPause"), next = MappedAction(rawValue:"next")
    controls.learn(play,input:.midi)
    controls.receiveMIDI([0x90,60,127],source:42)
    precondition(controls.bindings.count == 1 && fired.isEmpty)
    controls.mapping = false
    controls.receiveMIDI([0x80,60,0,0x90,60,127,60,127,0xF8,60,0,60,127],source:42)
    precondition(fired == ["playPause","playPause"])
    controls.receiveMIDI([0x80,60,0,0x90,60,127],source:99)
    precondition(fired.count == 2)
    controls.assign(.init(action:next,input:.midi,label:"CC 12",status:0xB0,channel:0,number:12,source:42))
    controls.receiveMIDI([0xB0,12,127,12,100,12,0,12,127],source:42)
    precondition(fired.suffix(2) == ["next","next"])
    controls.assign(.init(action:play,input:.keyboard,label:"⌥ P",key:35,modifiers:UInt32(optionKey)))
    controls.assign(.init(action:next,input:.keyboard,label:"⌥ P",key:35,modifiers:UInt32(optionKey)))
    precondition(controls.bindings.filter { $0.input == .keyboard }.count == 1)
    let restored = ControlMappings(defaults:isolated,liveIO:false)
    precondition(restored.bindings == controls.bindings)
    let set = ControlMapSet(name:"Stage",bindings:controls.bindings)
    let decoded = try JSONDecoder().decode(ControlMapSet.self,from:JSONEncoder().encode(set))
    precondition(ControlMappings.valid(decoded))
    var invalid = decoded; invalid.bindings.append(decoded.bindings[0]); precondition(!ControlMappings.valid(invalid))
    let volume = MappedAction(rawValue:"volume")
    controls.learn(volume,input:.keyboard); precondition(controls.input == .midi)
    controls.receiveMIDI([0xB0,7,20],source:42); controls.mapping = false
    controls.receiveMIDI([0xB0,7,0,7,64,7,127],source:42)
    precondition(fired.suffix(3) == ["volume","volume","volume"])
    controls.mapping = true; controls.trigger(play); precondition(fired.count == 7)
    controls.mapping = false; ControlLock.shared.lock(); controls.trigger(play); precondition(fired.count == 7); _ = ControlLock.shared.unlock(heldFor:3)
    isolated.removePersistentDomain(forName:suite)
    print("PASS: MIDI learn, note/CC edges, running status, source isolation, shortcut conflict replacement, persistence, set validation and lock/map suppression")
} else if CommandLine.arguments.contains("--reorder-test") {
    let suite="local.hardplay.reorder.\(UUID().uuidString)"
    let isolated=UserDefaults(suiteName:suite)!,directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer {isolated.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:directory)}
    let protection=SetupLock(defaults:isolated),p=Player(defaults:isolated,remoteCommands:false,setupLock:protection)
    let a=Track(url:directory.appendingPathComponent("a.wav")),b=Track(url:directory.appendingPathComponent("b.wav")),c=Track(url:directory.appendingPathComponent("c.wav"))
    p.tracks=[a,b,c];p.currentID=b.id;p.selectedID=c.id;p.elapsed=17;p.volume=0.35
    precondition(!p.moveTrack(a.id,to:0) && !p.canUndoEdit)
    precondition(!p.moveTrack("missing",to:1) && !p.moveTrack(a.id,to:99) && !p.canUndoEdit)
    precondition(p.moveTrack(a.id,relativeTo:c.id,after:true) && p.tracks.map(\.id)==[b.id,c.id,a.id])
    precondition(p.currentID==b.id && p.selectedID==c.id && p.elapsed==17 && p.volume==0.35)
    p.undoEdit();precondition(p.tracks.map(\.id)==[a.id,b.id,c.id] && p.currentID==b.id)
    p.redoEdit();precondition(p.tracks.map(\.id)==[b.id,c.id,a.id])
    p.moveTrack(a.id,by:-1);precondition(p.tracks.map(\.id)==[b.id,a.id,c.id])
    protection.lock();precondition(!p.moveTrack(a.id,to:0));protection.unlock()
    ControlLock.shared.lock();precondition(!p.moveTrack(a.id,to:0));_ = ControlLock.shared.unlock(heldFor:3)
    let saved=directory.appendingPathComponent("order.hardplay");try p.writePlaylist(to:saved)
    let read=try SavedPlaylist.read(from:saved);precondition(read.tracks.map(\.path)==["b.wav","a.wav","c.wav"])
    print("PASS: before/after drag positions, move steps, no-op/invalid rejection, current/selection/position/volume preservation, Undo/Redo, locks and saved order")
} else if CommandLine.arguments.contains("--playlist-lifecycle-test") {
    let suite="local.hardplay.lifecycle.\(UUID().uuidString)"
    let isolated=UserDefaults(suiteName:suite)!,directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:directory);isolated.removePersistentDomain(forName:suite)}
    let protection=SetupLock(defaults:isolated),player=Player(defaults:isolated,remoteCommands:false,setupLock:protection)
    let audio=directory.appendingPathComponent("source.wav"),document=directory.appendingPathComponent("first.hardplay"),trashed=directory.appendingPathComponent("trashed.hardplay")
    let bytes=Data("fixture source remains untouched".utf8);try bytes.write(to:audio)
    player.add([audio]);player.renameSet(to:"First");player.setFadeMode(.long,after:player.tracks[0]);try player.writePlaylist(to:document)
    let ids=player.tracks.map(\.id),original=try Data(contentsOf:document)
    player.newPlaylist(named:"  Second\nSet  ")
    precondition(player.tracks.isEmpty && player.playlistURL==nil && player.playlistName=="Second Set" && !player.playing && player.canDeletePlaylist)
    let unchanged=try Data(contentsOf:document);precondition(unchanged==original)
    player.undoEdit();precondition(player.tracks.map(\.id)==ids && player.playlistURL==document && player.playlistName=="First" && player.fadeMode(after:player.tracks[0]) == .long)
    protection.lock();player.newPlaylist();try player.deletePlaylist { _ in fatalError("Locked delete reached filesystem") };precondition(player.tracks.map(\.id)==ids)
    protection.unlock()
    do {try player.deletePlaylist {_ in throw CocoaError(.fileWriteNoPermission)};fatalError("Deletion failure hidden")}catch {}
    precondition(player.playlistURL==document && player.tracks.map(\.id)==ids)
    try player.deletePlaylist {try FileManager.default.moveItem(at:$0,to:trashed)}
    precondition(player.tracks.isEmpty && player.playlistURL==nil && !player.recentPlaylists.contains(document))
    precondition(FileManager.default.fileExists(atPath:trashed.path))
    player.undoEdit();precondition(player.tracks.map(\.id)==ids && player.playlistURL==nil && player.playlistName=="First")
    let audioAfter=try Data(contentsOf:audio);precondition(audioAfter==bytes)
    player.redoEdit();precondition(player.tracks.isEmpty)
    player.newPlaylist(named:" ");precondition(player.playlistName=="My Set" && !player.canDeletePlaylist)
    print("PASS: new named playlist, source-document preservation, Undo binding/fades, protected lifecycle, failed trash atomicity, delete recents, audio untouched and deleted-file Undo as unsaved")
} else if CommandLine.arguments.contains("--playlist-test") {
    let directory = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("hardplay-playlist-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let suite = "local.hardplay.playlist-test.\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName:suite)!
    let first = directory.appendingPathComponent("a.wav"), second = directory.appendingPathComponent("b.wav")
    // Missing audio references are intentional: playlist I/O must preserve them without playback.
    let player = Player(defaults:prefs,remoteCommands:false)
    player.add([first,second]); player.setFadeMode(.short,after:player.tracks[0]); player.setFadeMode(.long,after:player.tracks[1])
    player.startMode = .resume; player.endMode = .stop; player.stopBeforeEnd = 3
    player.rename(player.tracks[0],to:"  Opening — Live  ")
    precondition(player.tracks[0].title == "Opening — Live" && player.tracks[0].url == first)
    let restoredTitles = Player(defaults:prefs,remoteCommands:false)
    precondition(restoredTitles.tracks[0].title == "Opening — Live")
    let file = directory.appendingPathComponent("My Set.hardplay")
    try player.writePlaylist(to:file)
    let document = try SavedPlaylist.read(from:file)
    precondition(document.tracks.map(\.path) == ["a.wav","b.wav"])
    precondition(document.tracks.map(\.fade) == [.short,.long])
    precondition(document.tracks[0].title == "Opening — Live")
    let other = Player(defaults:UserDefaults(suiteName:suite+".other")!,remoteCommands:false)
    try other.readPlaylist(from:file)
    precondition(other.tracks.map(\.id) == [first.path,second.path])
    precondition(other.tracks[0].title == "Opening — Live")
    other.rename(other.tracks[0],to:" "); precondition(other.tracks[0].title == "a")
    let legacy = try JSONDecoder().decode(Track.self,from:Data("{\"url\":\"file:///tmp/Legacy.wav\"}".utf8))
    precondition(legacy.title == "Legacy" && legacy.customTitle == nil)
    precondition(other.tracks.map { other.fadeMode(after:$0) } == [.short,.long])
    precondition(other.endMode == .stop && other.stopBeforeEnd == 3 && !other.playing)
    precondition(other.playlistName == "My Set" && other.recentPlaylists.first == file)
    let broken = directory.appendingPathComponent("broken.hardplay")
    try Data("invalid".utf8).write(to:broken)
    let ids = other.tracks.map(\.id)
    do { try other.readPlaylist(from:broken); fatalError("Invalid playlist accepted") } catch { precondition(other.tracks.map(\.id) == ids) }
    var unsupported = document; unsupported.version = 99
    try unsupported.write(to:broken)
    do { _ = try SavedPlaylist.read(from:broken); fatalError("Unsupported version accepted") } catch {}
    try FileManager.default.removeItem(at:directory)
    prefs.removePersistentDomain(forName:suite); prefs.removePersistentDomain(forName:suite+".other")
    print("PASS: playlist round-trip, custom titles, legacy decoding, relative paths, fade modes, settings, missing files, recents and invalid-file preservation")
} else if let index = CommandLine.arguments.firstIndex(of: "--waveform-test"), CommandLine.arguments.count > index + 1 {
    Task {
        let envelope = await Waveforms.decode(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        guard envelope.peaks.count == 160, envelope.duration > 0 else { print("FAIL: PCM envelope decoding"); exit(1) }
        print("PASS: waveform decoded from PCM · \(envelope.peaks.count) bins · \(envelope.duration)s · peak \(envelope.peaks.max() ?? 0)")
        exit(0)
    }
    RunLoop.main.run()
} else if let testIndex = CommandLine.arguments.firstIndex(of: "--playback-test"), CommandLine.arguments.count > testIndex + 2 {
    let suite = "local.hardplay.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    Task { @MainActor in
        func waitUntil(_ condition: () -> Bool) async throws {
            for _ in 0..<100 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw NSError(domain: "HARDPLAY.TestTimeout", code: 1)
        }
        do {
            let testLock = SetupLock(defaults: defaults)
            let player = Player(defaults: defaults, remoteCommands: false, setupLock: testLock)
            player.volume = 0
            player.add([URL(fileURLWithPath: CommandLine.arguments[testIndex + 1]), URL(fileURLWithPath: CommandLine.arguments[testIndex + 2])])
            try await waitUntil { player.duration > 0 }
            let first = player.tracks[0], second = player.tracks[1]
            let buttonControls = ControlMappings(defaults:defaults,liveIO:false,player:player,setupLock:testLock)
            let transport = MappedAction(rawValue:"playPause")
            buttonControls.trigger(transport,behavior:.trigger)
            try await waitUntil { player.playing }
            buttonControls.trigger(transport,behavior:.trigger); precondition(player.playing)
            buttonControls.trigger(transport,behavior:.toggle); precondition(!player.playing)
            buttonControls.trigger(transport,behavior:.toggle)
            try await waitUntil { player.playing }
            player.pause()
            print("PASS: Trigger starts once; Toggle pauses and resumes actual audio")
            player.endMode = .stop; player.stopBeforeEnd = 1
            player.seek(player.duration - 1.5); player.toggle()
            try await waitUntil { player.stoppedAtBoundary }
            precondition(!player.playing && player.currentID == first.id)
            precondition(abs(player.elapsed - (player.duration - 1)) < 0.25)
            print("PASS: stop before end without advancing")
            player.startMode = .resume
            player.seek(1.2); player.load(second, autoplay: false)
            try await waitUntil { player.duration > 0 }
            player.load(first, autoplay: false)
            try await waitUntil { player.duration > 0 && abs(player.elapsed - 1.2) < 0.25 }
            print("PASS: per-track resume after switching")
            player.restart()
            try await waitUntil { player.duration > 0 && player.playing }
            precondition(player.elapsed < 0.5)
            player.pause()
            print("PASS: explicit restart")
            player.stopBeforeEnd = 0; player.seek(player.duration - 0.4); player.toggle()
            try await waitUntil { player.stoppedAtBoundary }
            precondition(!player.playing && player.currentID == first.id)
            print("PASS: stop at actual end without advancing")
            player.endMode = .next; player.seek(player.duration - 0.4); player.toggle()
            try await waitUntil { player.currentID == second.id && player.duration > 0 }
            player.pause()
            print("PASS: normal queue advances")
            player.seek(1.4); player.pause()
            let restored = Player(defaults: defaults, remoteCommands: false)
            try await waitUntil { restored.duration > 0 }
            precondition(abs(restored.elapsed - 1.4) < 0.25 && !restored.playing)
            precondition(restored.startMode == .resume && restored.endMode == .next)
            print("PASS: positions and modes survive restore")
            // Silent fixtures should be >= 12 seconds to distinguish 3s and 6s transitions.
            precondition(player.duration >= 12)
            player.startMode = .beginning
            player.setFadeMode(.short, after: first); player.setFadeMode(.none, after: second)
            player.load(first, autoplay: false, position: 0)
            try await waitUntil { player.duration > 0 }
            player.seek(player.duration - 3.5); player.toggle()
            try await waitUntil { player.isCrossfading && player.currentID == second.id && player.elapsed > 0.3 }
            precondition(player.stageLeft?.id == first.id && player.stageRight?.id == second.id)
            precondition(player.queueNumber(player.stageLeft) == "01" && player.queueNumber(player.stageRight) == "02")
            precondition(player.stageLeftGain > 0 && player.stageRightGain > 0 && player.transitionRemaining > 0)
            precondition(player.crossfadeDiagnostics.outgoingRate > 0 && player.crossfadeDiagnostics.incomingRate > 0)
            precondition(player.mixGains.0 > 0 && player.mixGains.1 > 0 && abs(player.mixGains.0 + player.mixGains.1 - 1) < 0.001)
            ControlLock.shared.lock()
            let lockedProgress = player.fadeProgress
            try await Task.sleep(nanoseconds: 200_000_000)
            precondition(player.playing && player.fadeProgress > lockedProgress)
            _ = ControlLock.shared.unlock(heldFor: 3)
            player.pause()
            let pausedTime = player.elapsed, pausedGain = player.mixGains.1
            try await Task.sleep(nanoseconds: 350_000_000)
            precondition(abs(player.elapsed - pausedTime) < 0.15 && abs(player.mixGains.1 - pausedGain) < 0.1)
            precondition(player.crossfadeDiagnostics.outgoingRate == 0 && player.crossfadeDiagnostics.incomingRate == 0)
            player.volume = 0.35
            precondition(abs(player.crossfadeDiagnostics.outgoingVolume + player.crossfadeDiagnostics.incomingVolume - 0.35) < 0.01)
            player.volume = 0; player.toggle()
            try await waitUntil { !player.isCrossfading }
            precondition(player.currentID == second.id && player.elapsed >= 1.7 && player.crossfadeDiagnostics.outgoingRate == 0)
            print("PASS: 3s overlap, both decoders, complementary gains, pause/resume and volume")
            player.pause(); player.setFadeMode(.long, after: second)
            player.seek(player.duration - 0.4); player.toggle()
            try await waitUntil { !player.playing }
            precondition(player.currentID == second.id && !player.isCrossfading)
            print("PASS: last track does not wrap without repeat")
            player.setFadeMode(.long, after: first)
            player.load(first, autoplay: false, position: 0)
            try await waitUntil { player.duration > 0 }
            player.seek(player.duration - 6.5); player.toggle()
            try await waitUntil { player.isCrossfading && player.elapsed > 0.3 }
            precondition(player.crossfadeDiagnostics.length > 5.5 && player.crossfadeDiagnostics.length <= 6)
            player.seek(2)
            precondition(!player.isCrossfading && player.crossfadeDiagnostics.outgoingRate == 0)
            player.pause()
            print("PASS: 6s overlap and seeking cancels outgoing audio")
            player.endMode = .stop; player.stopBeforeEnd = 1
            player.load(first, autoplay: false, position: 0)
            try await waitUntil { player.duration > 0 }
            player.seek(player.duration - 2); player.toggle()
            try await waitUntil { player.stoppedAtBoundary }
            precondition(!player.isCrossfading && player.currentID == first.id)
            print("PASS: stop mode takes priority over crossfade")
            player.endMode = .next; player.startMode = .beginning
            player.setFadeMode(.short, after: first)
            player.load(first, autoplay: false, position: 0)
            try await waitUntil { player.duration > 0 }
            player.toggle(); player.play(second)
            try await waitUntil { player.isCrossfading && player.currentID == second.id }
            player.load(first, autoplay: false, position: 0)
            try await waitUntil { player.duration > 0 }
            precondition(!player.isCrossfading && player.crossfadeDiagnostics.outgoingRate == 0)
            print("PASS: manual next crossfades; replacement cancels both transition tasks")
            player.setFadeMode(.none, after: first)
            player.seek(player.duration - 0.4); player.toggle()
            try await waitUntil { player.currentID == second.id && player.duration > 0 }
            precondition(!player.isCrossfading)
            player.pause()
            print("PASS: no-crossfade mode advances normally")
            let fadeRestored = Player(defaults: defaults, remoteCommands: false)
            try await waitUntil { fadeRestored.duration > 0 }
            precondition(fadeRestored.tracks.map { fadeRestored.fadeMode(after: $0) } == [.none, .long])
            print("PASS: independent transition modes survive restore")
            for mode in FadeMode.allCases {
                let beforeID = player.currentID, beforeElapsed = player.elapsed
                player.setFadeModeForAll(mode)
                precondition(player.tracks.allSatisfy { player.fadeMode(after: $0) == mode })
                precondition(player.uniformFadeMode == mode)
                precondition(player.currentID == beforeID && abs(player.elapsed - beforeElapsed) < 0.2 && !player.playing)
                let savedModes = try JSONDecoder().decode([String: FadeMode].self, from: defaults.data(forKey: "transitionModes")!)
                precondition(player.tracks.allSatisfy { savedModes[$0.id] == mode })
            }
            player.setFadeMode(.none, after: first)
            precondition(player.fadeMode(after: second) == .long && player.uniformFadeMode == nil)
            player.setFadeModeForAll(.short)
            let bulkRestored = Player(defaults: defaults, remoteCommands: false)
            try await waitUntil { bulkRestored.duration > 0 }
            precondition(bulkRestored.uniformFadeMode == .short && bulkRestored.tracks.count == 2)
            print("PASS: bulk apply all three modes, persistence, individual override and unchanged playback")


            let emptyURL = FileManager.default.temporaryDirectory.appendingPathComponent("hardplay-empty-\(UUID().uuidString).wav")
            try Data().write(to: emptyURL)
            defer { try? FileManager.default.removeItem(at: emptyURL) }
            let emptyTrack = Track(url: emptyURL)
            player.add([emptyURL]); player.load(emptyTrack)
            precondition(!player.playing && player.duration == 0 && player.error?.contains("0 bytes") == true)
            player.toggle()
            precondition(!player.playing && player.currentID == emptyTrack.id && player.error?.contains("0 bytes") == true)
            let emptySize = try FileManager.default.attributesOfItem(atPath: emptyURL.path)[.size] as? NSNumber
            precondition(emptySize?.intValue == 0)
            player.load(first, autoplay: false)
            try await waitUntil { player.duration > 0 }
            precondition(!player.playing && player.error == nil)
            print("PASS: empty file reports exact cause, stays paused on retry and allows recovery")
            let protectedID = player.currentID, protectedTime = player.elapsed
            let protectedTracks = player.tracks, protectedModes = player.transitionModes
            testLock.protectEdits = true; testLock.protectSelection = true; testLock.protectPlayback = true; testLock.lock()
            player.rename(first,to:"Blocked rename"); player.remove(first); player.add([first.url]); player.setFadeModeForAll(.long); player.setFadeMode(.long,after:first)
            player.toggle(); player.next(); player.previous(); player.play(second); player.restart(); player.resumeSaved(); player.seek(4)
            precondition(player.currentID == protectedID && player.elapsed == protectedTime && !player.playing)
            precondition(player.tracks == protectedTracks && player.transitionModes == protectedModes)
            player.next(automatic: true)
            try await waitUntil { player.currentID == second.id && player.duration > 0 }
            player.pause(); testLock.unlock()
            player.load(first,autoplay:false)
            try await waitUntil { player.duration > 0 }
            player.setFadeMode(.none,after:first)
            precondition(player.fadeMode(after:first) == .none)
            print("PASS: setup lock protects edits, selection and transport; automatic advance and unlock work")
            defaults.removePersistentDomain(forName: suite)
            exit(0)
        } catch { defaults.removePersistentDomain(forName: suite); print("FAIL: \(error)"); exit(1) }
    }
    RunLoop.main.run()
} else if let probeIndex = CommandLine.arguments.firstIndex(of: "--audio-probe"), CommandLine.arguments.count > probeIndex + 1 {
    let url = URL(fileURLWithPath: CommandLine.arguments[probeIndex + 1])
    Task { @MainActor in
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration > 0 else { print("FAIL: duration"); exit(1) }
            let probe = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            probe.volume = 0
            probe.play()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            guard probe.currentTime().seconds > 0, probe.currentItem?.status == .readyToPlay else { print("FAIL: playback"); exit(1) }
            await probe.seek(to: CMTime(seconds: duration / 2, preferredTimescale: 600))
            probe.pause()
            guard abs(probe.currentTime().seconds - duration / 2) < 0.2 else { print("FAIL: seek"); exit(1) }
            print("PASS: \(url.pathExtension.uppercased()) · duration \(duration)s · playback · seek · pause")
            exit(0)
        } catch { print("FAIL: \(error)"); exit(1) }
    }
    RunLoop.main.run()
 } else if CommandLine.arguments.contains("--queue-test") {
    let suite="local.hardplay.queue.\(UUID().uuidString)"
    let defaults=UserDefaults(suiteName:suite)!
    let protection=SetupLock(defaults:defaults)
    let player=Player(defaults:defaults,remoteCommands:false,setupLock:protection)
    let original=Track(url:URL(fileURLWithPath:"/tmp/HARDPLAY Missing Queue Test.wav"),customTitle:"Original")
    let other=Track(url:URL(fileURLWithPath:"/tmp/HARDPLAY Other Queue Test.wav"))
    player.tracks=[original,other]; player.currentID=original.id; player.selectedID=original.id
    player.selectInQueue(other)
    precondition(player.currentID == original.id && player.selectedID == other.id && !player.playing)
    player.setFadeMode(.short,after:original)
    let copy=player.duplicate(original)!
    precondition(copy.id != original.id && copy.url == original.url && player.tracks[1].id == copy.id)
    precondition(player.fadeMode(after:copy) == .short && FadeMode.short.seconds == 3)
    player.rename(copy,to:"Independent copy"); player.setFadeMode(.long,after:copy)
    precondition(player.tracks[0].title == "Original" && player.tracks[1].title == "Independent copy")
    precondition(player.fadeMode(after:original) == .short && player.fadeMode(after:copy) == .long)
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let file=folder.appendingPathComponent("Test.hardplay")
    player.renameSet(to:"Evening theatre set")
    try player.writePlaylist(to:file)
    let decoded=try SavedPlaylist.read(from:file)
    precondition(decoded.name == "Evening theatre set" && player.playlistName == decoded.name)
    precondition(decoded.tracks.count == 3 && decoded.tracks[1].occurrenceID == copy.occurrenceID)
    try player.readPlaylist(from:file)
    precondition(player.tracks.count == 3 && Set(player.tracks.map(\.id)).count == 3 && !player.playing)
    precondition(player.tracks[0].url == player.tracks[1].url && player.fadeMode(after:player.tracks[1]) == .long)
    player.remove(player.tracks[0]); precondition(player.tracks.contains(where:{$0.id == copy.id}))
    let restored=Player(defaults:defaults,remoteCommands:false)
    precondition(restored.tracks.contains(where:{$0.id == copy.id}) && !restored.playing)
    let removedCount=player.tracks.count
    player.undoEdit();precondition(player.tracks.count == removedCount+1 && !player.playing)
    player.redoEdit();precondition(player.tracks.count == removedCount && !player.playing)
    player.undoEdit();player.rename(player.tracks[0],to:"Undo name")
    player.undoEdit();precondition(player.tracks[0].title != "Undo name")
    player.redoEdit();precondition(player.tracks[0].title == "Undo name")
    player.renameSet(to:"Set to undo");player.undoEdit();precondition(player.playlistName == "Evening theatre set")
    player.redoEdit();precondition(player.playlistName == "Set to undo")
    defaults.removePersistentDomain(forName:suite)
    try FileManager.default.removeItem(at:folder)
    print("PASS: select without Play, duplicate identities, independent names/fades, 3s mode, playlist round trip, remove original and restore copies")
} else if CommandLine.arguments.contains("--self-test") {
    let dropped=URL(fileURLWithPath:"/tmp/Set with spaces/Трек.wav")
    precondition(AudioDropURLs.decode(dropped as NSURL) == dropped)
    precondition(AudioDropURLs.decode(dropped.dataRepresentation as NSData) == dropped)
    precondition(AudioDropURLs.decode(dropped.absoluteString as NSString) == dropped)
    precondition(AudioDropURLs.decode("https://example.com/audio.wav") == nil)
    precondition(PocketPanel.limitedSize(NSSize(width:10,height:10)) == NSSize(width:344,height:320))
    precondition(PocketPanel.limitedSize(NSSize(width:900,height:900)) == NSSize(width:560,height:640))
    precondition(PlaylistWindowState.shouldHideSeparate(detached:true,docked:false,visible:true,minimized:false))
    precondition(!PlaylistWindowState.shouldHideSeparate(detached:true,docked:false,visible:true,minimized:true))
    precondition(!PlaylistWindowState.shouldHideSeparate(detached:true,docked:true,visible:true,minimized:false))
    precondition(!PlaylistWindowState.shouldHideSeparate(detached:false,docked:false,visible:false,minimized:false))
    let screenRect=NSRect(x:0,y:0,width:1440,height:900)
    let left=PocketPanel.constrainedFrame(NSRect(x:-500,y:1000,width:344,height:296),visible:screenRect)
    precondition(left.minX+158 == 0 && left.maxY-6 == 900)
    let right=PocketPanel.constrainedFrame(NSRect(x:2000,y:-500,width:344,height:296),visible:screenRect)
    precondition(right.maxX-6 == 1440 && right.minY+6 == 0)
    let track = Track(url: URL(fileURLWithPath: "/tmp/Test Track.flac"))
    precondition(track.title == "Test Track" && track.format == "FLAC")
    precondition(timeLabel(125) == "2:05" && timeLabel(.nan) == "0:00")
    let data = try JSONEncoder().encode([track])
    let decoded = try JSONDecoder().decode([Track].self, from: data)
    precondition(decoded == [track])
    let lock = ControlLock()
    lock.lock(); precondition(lock.isLocked)
    precondition(!lock.unlock(swipe: 30) && lock.isLocked)
    precondition(lock.unlock(swipe: 340) && !lock.isLocked)
    lock.lock(); precondition(!lock.unlock(heldFor: 0.3))
    precondition(lock.unlock(heldFor: 3) && !lock.isLocked)
    precondition(MenuBarBadge.state(hasTrack:false,playing:false,crossfading:false,error:nil) == .empty)
    precondition(MenuBarBadge.state(hasTrack:true,playing:false,crossfading:false,error:nil) == .paused)
    precondition(MenuBarBadge.state(hasTrack:true,playing:true,crossfading:false,error:nil) == .playing)
    precondition(MenuBarBadge.state(hasTrack:true,playing:true,crossfading:true,error:nil) == .crossfade)
    precondition(MenuBarBadge.state(hasTrack:true,playing:false,crossfading:false,error:"Decode failed") == .error)
    print("HARDPLAY self-test passed (model, queue, lock gestures, menu bar states)")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
