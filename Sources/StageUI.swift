import AppKit
import SwiftUI
import AVFoundation

final class ControlLock: ObservableObject {
    static let shared = ControlLock()
    @Published private(set) var isLocked = false
    func lock() { isLocked = true }
    @discardableResult func unlock(swipe: Double) -> Bool {
        guard swipe >= 60 else { return false }
        isLocked = false; return true
    }
    @discardableResult func unlock(heldFor seconds: Double) -> Bool {
        guard seconds >= 0.9 else { return false }
        isLocked = false; return true
    }
}

/// Bounded peak envelopes derived from decoded PCM, never a generated waveform.
@MainActor final class Waveforms: ObservableObject {
    static let shared = Waveforms()
    struct Envelope { let peaks: [Double]; let duration: Double }
    @Published private(set) var cache: [String: Envelope] = [:]
    private var pending: [String: Task<Envelope, Never>] = [:]
    func load(_ track: Track) async {
        if cache[track.id] != nil { return }
        let job: Task<Envelope, Never>
        if let existing = pending[track.id] { job = existing }
        else {
            job = Task.detached(priority: .utility) { await Self.decode(track.url) }
            pending[track.id] = job
        }
        let result = await job.value
        if cache.count >= 24, let key = cache.keys.first { cache.removeValue(forKey: key) }
        cache[track.id] = result; pending.removeValue(forKey: track.id)
    }
    nonisolated static func decode(_ url: URL) async -> Envelope {
        do {
            let asset = AVURLAsset(url: url)
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite, seconds > 0, let track = try await asset.loadTracks(withMediaType: .audio).first else { return Envelope(peaks: [], duration: 0) }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 8000])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return Envelope(peaks: [], duration: seconds) }
            reader.add(output)
            guard reader.startReading() else { return Envelope(peaks: [], duration: seconds) }
            var peaks = [Double](repeating: 0, count: 160)
            while !Task.isCancelled, let sample = output.copyNextSampleBuffer() {
                guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
                var length = 0; var pointer: UnsafeMutablePointer<Int8>?
                guard CMBlockBufferGetDataPointer(buffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer else { continue }
                let count = length / MemoryLayout<Float>.size
                let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                let sampleDuration = CMSampleBufferGetDuration(sample).seconds
                let span = sampleDuration.isFinite && sampleDuration > 0 ? sampleDuration : Double(count) / 8000
                guard start.isFinite, count > 0 else { continue }
                pointer.withMemoryRebound(to: Float.self, capacity: count) { floats in
                    for i in stride(from: 0, to: count, by: 4) {
                        let bin = min(159, max(0, Int((start + Double(i) / Double(count) * span) / seconds * 160)))
                        let amplitude = Double(abs(floats[i]))
                        if amplitude.isFinite { peaks[bin] = max(peaks[bin], amplitude) }
                    }
                }
            }
            guard reader.status == .completed else { reader.cancelReading(); return Envelope(peaks: [], duration: seconds) }
            let maximum = peaks.max() ?? 0
            return Envelope(peaks: maximum > 0 ? peaks.map { pow($0 / maximum, 0.65) } : peaks, duration: seconds)
        } catch { return Envelope(peaks: [], duration: 0) }
    }
}

struct TapeEdge: Shape {
    func path(in r: CGRect) -> Path {
        let points: [(Double, Double)] = [(0.02,0),(0.98,0.02),(1,0.17),(0.98,0.32),(1,0.49),(0.99,0.67),(1,0.84),(0.98,1),(0.01,0.97),(0.02,0.81),(0,0.64),(0.02,0.45),(0,0.24)]
        var p = Path(); p.move(to: CGPoint(x: r.width * points[0].0, y: r.height * points[0].1))
        for point in points.dropFirst() { p.addLine(to: CGPoint(x: r.width * point.0, y: r.height * point.1)) }; p.closeSubpath(); return p
    }
}
var tapeB: Color { Color(stageHex:AppearancePreferences.shared.theme.tape) }
struct TapeLabel: View {
    var text: String
    var secondary = false
    var body: some View {
        Text(text).font(.custom("MarkerFelt-Wide", size: 14)).foregroundStyle(Color(red: 0.07, green: 0.13, blue: 0.22))
            .padding(.horizontal, 12).padding(.vertical, 5).background(secondary ? tapeB : accent, in: TapeEdge()).rotationEffect(.degrees(secondary ? 1 : -1))
    }
}

struct DeckWave: View {
    let peaks: [Double]
    let fraction: Double
    let color: Color
    let gain: Double
    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let bins = min(peaks.count, max(1, Int(size.width / 4)))
            for i in 0..<bins {
                let from = i * peaks.count / bins, end = max(from + 1, (i + 1) * peaks.count / bins)
                let amplitude = peaks[from..<min(end, peaks.count)].max() ?? 0
                let h = max(1, amplitude * (size.height - 4))
                let x = Double(i) / Double(bins) * size.width
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: max(1.3, size.width / Double(bins) - 1.6), height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity((Double(i) / Double(bins) <= fraction ? 1 : 0.45) * (0.35 + gain * 0.65))))
            }
            let x = min(size.width - 1, max(0, fraction * size.width))
            var cursor = Path(); cursor.move(to: CGPoint(x: x, y: 0)); cursor.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(cursor, with: .color(.white.opacity(0.85)), lineWidth: 1)
        }.accessibilityLabel("Audio Waveform").allowsHitTesting(false)
    }
}

struct StageDeck: View {
    @ObservedObject var appearance = AppearancePreferences.shared
    @ObservedObject var player: Player
    @ObservedObject var waves = Waveforms.shared
    let track: Track?
    let right: Bool
    let compact: Bool
    var actualDuration: Double { (right ? player.stageRightDuration : player.stageLeftDuration) > 0 ? (right ? player.stageRightDuration : player.stageLeftDuration) : (track.flatMap { waves.cache[$0.id]?.duration } ?? 0) }
    var elapsed: Double { right ? player.stageRightTime : player.stageLeftTime }
    var gain: Double { right ? player.stageRightGain : player.stageLeftGain }
    var seekable: Bool { track != nil && (right ? player.isCrossfading : !player.isCrossfading) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(player.queueNumber(track)).font(.custom("MarkerFelt-Thin", size: compact ? 24 : 28)).monospacedDigit()
                Spacer()
                Text(right ? (player.isCrossfading ? "INCOMING" : "NEXT") : (player.isCrossfading ? "OUTGOING" : "NOW"))
                    .font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Color(stageHex:AppearancePreferences.shared.theme.text).opacity(0.65))
            }
            Text(track?.title ?? (right ? "End of Queue" : "Add your music"))
                .font(.system(size: (compact ? 13 : 16) * AppearancePreferences.shared.theme.textScale, weight: .semibold)).lineLimit(2).frame(height:(compact ? 34 : 40) * AppearancePreferences.shared.theme.textScale,alignment:.topLeading).help(track?.title ?? "")
            HStack { Text("\(timeLabel(elapsed)) / \(timeLabel(actualDuration))"); Spacer(); Text("\(Int(gain * 100))%") }
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(stageHex:AppearancePreferences.shared.theme.text).opacity(0.7))
            ZStack {
                if let track, let envelope = waves.cache[track.id] {
                    if envelope.peaks.isEmpty { Text("Waveform unavailable").font(.system(size: 10)).foregroundStyle(Color(stageHex:AppearancePreferences.shared.theme.text).opacity(0.55)) }
                    else { DeckWave(peaks: envelope.peaks, fraction: actualDuration > 0 ? elapsed / actualDuration : 0, color: right ? tapeB : accent, gain: gain) }
                } else if track != nil { ProgressView().controlSize(.small) }
            }.frame(height: compact ? 30 : 36)
            GeometryReader { g in
                Rectangle().fill(.white.opacity(0.1)).overlay(alignment: .leading) {
                    Rectangle().fill(right ? tapeB : accent).frame(width: g.size.width * gain)
                }
            }.frame(height: 3)

        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((right ? tapeB : accent).opacity(0.065), in: RoundedRectangle(cornerRadius: appearance.theme.radius))
        .task(id: track?.id) { if let track { await waves.load(track) } }
    }
}

/// Uses AppKit pointer tracking so window dragging and SwiftUI recognizers cannot steal the swipe.
struct NativeUnlockControl: NSViewRepresentable {
    final class UnlockView: NSView {
        private var distance: CGFloat = 0
        private var originY: CGFloat?
        private var timer: Timer?
        override var acceptsFirstResponder: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { window.makeFirstResponder(self) }
            else { timer?.invalidate() }
        }
        override func draw(_ dirtyRect: NSRect) {
            let rail = NSRect(x: bounds.midX - 13, y: 6, width: 26, height: bounds.height - 12)
            NSColor.white.withAlphaComponent(0.09).setFill(); NSBezierPath(roundedRect: rail, xRadius: 13, yRadius: 13).fill()
            ("↑" as NSString).draw(at: NSPoint(x: bounds.midX - 7, y: bounds.height - 26), withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.white.withAlphaComponent(0.65)])
            let thumb = NSRect(x: bounds.midX - 34, y: 8 + distance, width: 68, height: 42)
            NSColor(calibratedRed: 0.58, green: 0.77, blue: 0.96, alpha: 1).setFill(); NSBezierPath(roundedRect: thumb, xRadius: 21, yRadius: 21).fill()
            if let image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [NSColor(calibratedRed: 0.07, green: 0.13, blue: 0.23, alpha: 1)])) {
                image.draw(in: NSRect(x: thumb.midX - 9, y: thumb.midY - 10, width: 18, height: 20))
            }
        }
        private func hold() {
            timer?.invalidate()
            let holdTimer = Timer(timeInterval: 0.92, repeats: false) { [weak self] _ in self?.unlock() }
            timer = holdTimer; RunLoop.main.add(holdTimer, forMode: .common)
        }
        private func unlock() { timer?.invalidate(); _ = ControlLock.shared.unlock(heldFor: 0.92) }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            originY = convert(event.locationInWindow, from: nil).y
            distance = 0; hold(); needsDisplay = true
        }
        override func mouseDragged(with event: NSEvent) {
            guard let originY else { return }
            distance = min(64, max(0, convert(event.locationInWindow, from: nil).y - originY))
            if distance > 5 { timer?.invalidate() }
            needsDisplay = true
            if distance >= 60 { timer?.invalidate(); self.originY = nil; _ = ControlLock.shared.unlock(swipe: Double(distance)) }
        }
        override func mouseUp(with event: NSEvent) {
            timer?.invalidate(); originY = nil; distance = 0; needsDisplay = true
        }
        override func keyDown(with event: NSEvent) { if !event.isARepeat, event.keyCode == 49 || event.keyCode == 36 { hold() } }
        override func keyUp(with event: NSEvent) { if event.keyCode == 49 || event.keyCode == 36 { timer?.invalidate() } }
        override func resignFirstResponder() -> Bool { timer?.invalidate(); return super.resignFirstResponder() }
        override func accessibilityPerformPress() -> Bool { unlock(); return true }
        func cleanUp() { timer?.invalidate() }
    }
    func makeNSView(context: Context) -> UnlockView {
        let view = UnlockView(); view.setAccessibilityElement(true); view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Unlock Controls")
        view.setAccessibilityHelp("Drag up or hold Space for one second")
        return view
    }
    func updateNSView(_ view: UnlockView, context: Context) {}
    static func dismantleNSView(_ view: UnlockView, coordinator: ()) { view.cleanUp() }
}

struct UnlockShield: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.04).contentShape(Rectangle()).onTapGesture {}
            VStack(spacing: 6) {
                Text("Controls locked · music continues").font(.system(size: 12, weight: .medium))
                NativeUnlockControl().frame(width: 110, height: 120)
                Text("Drag up or hold Space").font(.system(size: 11)).foregroundStyle(Color(stageHex:AppearancePreferences.shared.theme.text).opacity(0.7))
            }.padding(12).frame(maxWidth: .infinity)
                .background(Color(red: 0.055, green: 0.10, blue: 0.18).opacity(0.97))
        }.disabled(false)
    }
}

struct PlayerView: View {
    @ObservedObject var player = Player.shared
    @ObservedObject var lock = ControlLock.shared
    @StateObject private var ui = PlayerViewState()
    @ObservedObject var setup = SetupLock.shared
    @ObservedObject var playlistWindow = PlaylistWindowState.shared
    @ObservedObject var hints = HintPreferences.shared
    @ObservedObject var placement = FloatingPlacement.shared
    var compact = false
    var settingsOnly = false
    @ObservedObject var appearance = AppearancePreferences.shared
    var playlistOnly = false
    var menuBar = false
    @ViewBuilder var body: some View {
        Group { if settingsOnly { settings } else if playlistOnly { detachedPlaylist } else { playerBody } }
            .overlay(RoundedRectangle(cornerRadius:14).stroke(ui.targeted ? accent.opacity(0.8):.clear,lineWidth:2).allowsHitTesting(false))
            .onDrop(of:[UTType.fileURL],isTargeted:$ui.targeted) { providers in
                guard !lock.isLocked,!setup.editsBlocked else { return false }
                for provider in providers {
                    _ = provider.loadObject(ofClass:URL.self) { url,_ in
                        if let url { DispatchQueue.main.async { if !lock.isLocked,!setup.editsBlocked { player.add([url]) } } }
                    }
                }
                return !providers.isEmpty
            }
    }
    @ViewBuilder private var playerBody: some View {
        if compact { stageBody(wide:false).frame(width:380) }
        else {
            GeometryReader { geometry in stageBody(wide:geometry.size.width >= 840) }
                .frame(minWidth:520,minHeight:600)
        }
    }
    private func stageBody(wide:Bool) -> some View {
        VStack(spacing:appearance.theme.spacing) {
            header
            let layout = wide && !playlistWindow.detached ? AnyLayout(HStackLayout(alignment:.top,spacing:22)) : AnyLayout(VStackLayout(spacing:10))
            layout {
                playbackPanel.frame(maxWidth:.infinity,alignment:.top)
                playlistPanel.frame(maxWidth:.infinity,maxHeight:compact ? nil:.infinity,alignment:.top)
            }.disabled(lock.isLocked).allowsHitTesting(!lock.isLocked)
        }
        .padding(compact ? 14 : 16).frame(maxWidth:.infinity,maxHeight:compact ? nil:.infinity,alignment:.top)
        .foregroundStyle(Color(stageHex:appearance.theme.text)).preferredColorScheme(.dark)
        .overlay { if lock.isLocked { UnlockShield() } }
        .onChange(of:playlistWindow.detached) { _, detached in if detached { ui.playlist = false } }
        .onChange(of:lock.isLocked) { _, locked in if locked { ui.settings = false; ui.playlist = false; ui.protection = false } }
    }
    private var playbackPanel: some View {
        VStack(spacing:10) {
                HStack(alignment: .top, spacing: 10) {
                    StageDeck(player: player, track: player.stageLeft, right: false, compact: compact)
                    StageDeck(player: player, track: player.stageRight, right: true, compact: compact)
                }
                HStack(spacing: 8) {
                    Text("\(player.queueNumber(player.stageLeft)) → \(player.queueNumber(player.stageRight))").font(.system(size: 10, design: .monospaced))
                    GeometryReader { g in
                        Capsule().fill(.white.opacity(0.1)).overlay(alignment: .leading) {
                            Capsule().fill(LinearGradient(colors: [accent,tapeB], startPoint: .leading, endPoint: .trailing)).frame(width: g.size.width * (player.isCrossfading ? player.fadeProgress : 0))
                        }
                    }.frame(height: 4)
                    Text(player.isCrossfading ? String(format: "%.1f s", player.transitionRemaining) : (player.endMode == .stop ? "STOP" : ""))
                        .font(.system(size: 10, design: .monospaced))
                }.foregroundStyle(Color(stageHex:AppearancePreferences.shared.theme.text).opacity(0.7))
                SeekPositionSlider(value: Binding(get: { ui.scrubbing ? ui.scrub : player.elapsed }, set: { ui.scrub = $0 }), duration:player.duration, onEditingChanged: { editing in
                    if editing { ui.scrub = player.elapsed; ui.scrubbing = true } else { player.seek(ui.scrub); ui.scrubbing = false }
                }).disabled(player.current == nil || setup.playbackBlocked)
                transport
                if compact { restartButtons }
                HStack(spacing:8) {
                    Image(systemName:player.volume == 0 ? "speaker.slash":"speaker.wave.2").font(.system(size:12)).foregroundStyle(accent)
                    Slider(value:$player.volume,in:0...1).controlSize(.small).tint(accent).accessibilityLabel("Master Volume")
                    Text("\(Int(player.volume * 100))%").font(.system(size:11,design:.monospaced)).frame(width:38,alignment:.trailing)
                }.disabled(setup.playbackBlocked).mapAction("volume")
                QueuePolicyControls(player:player)
                if let error = player.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal:false, vertical:true) }
        }
    }
    private var playlistPanel: some View {
        VStack(spacing:10) {
                HStack {
                    Button { playlistWindow.toggleDrawer(fromMini:compact && !menuBar) } label: {
                        HStack(spacing:4) { playlistTape;Image(systemName:"chevron.down").font(.system(size:9,weight:.bold)).foregroundStyle(Color(red:0.07,green:0.13,blue:0.22)) }
                            .padding(.horizontal,8).padding(.vertical,5).background(tapeB,in:TapeEdge())
                    }.buttonStyle(.plain).accessibilityLabel("Playlist: \(player.playlistName)").stageHint("Show or hide docked playlist")
                    Menu { playlistActions } label: { Image(systemName:"folder").frame(width:24,height:28) }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Playlist Files")
                    Spacer()
                    if compact {
                        Button { AppDelegate.shared.showMain() } label: { Label("Edit Queue",systemImage:"list.bullet").font(.system(size:11)).padding(.horizontal,9).frame(height:30) }
                            .buttonStyle(PlayerControlStyle()).accessibilityLabel("Open Full Queue")
                    } else {
                        Button { ui.protection.toggle() } label: { Label("Edit", systemImage:"slider.horizontal.3").font(.system(size:11)).padding(.horizontal,8).frame(height:30) }
                            .buttonStyle(PlayerControlStyle()).popover(isPresented:$ui.protection) { protectionSettings }
                        setupLockButton
                        Button { player.openFiles() } label: { Image(systemName:"plus").frame(width:30,height:30) }.buttonStyle(PlayerControlStyle()).disabled(setup.editsBlocked).accessibilityLabel("Add Audio").stageHint("Add audio files or a folder",below:true)
                    }
                }.padding(.top,3)
                if !compact {
                    HStack(spacing:6) {
                        Button { playlistWindow.attach(toMini:false) } label: { Label("In Player",systemImage:"rectangle.split.2x1").font(.system(size:11)).padding(6) }
                            .buttonStyle(PlayerControlStyle(active:!playlistWindow.detached)).accessibilityLabel("Playlist In Player")
                        Menu {
                            ForEach(PlaylistDockEdge.allCases,id:\.rawValue) { side in
                                Button(side.title) { playlistWindow.dock(side) }
                            }
                        } label: { Label(playlistWindow.edge?.title ?? "Dock",systemImage:"rectangle.split.2x1").font(.system(size:11)).padding(6) }
                            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Playlist Dock Side")
                        Button { playlistWindow.detach() } label: { Label("Separate Window",systemImage:"arrow.up.right.square").font(.system(size:11)).padding(6) }
                            .buttonStyle(PlayerControlStyle(active:playlistWindow.detached)).accessibilityLabel("Playlist Separate Window")
                        Spacer(minLength:0)
                    }
                    if playlistWindow.detached {
                        Button { AppDelegate.shared.showPlaylistWindow() } label: {
                            Label("Open Playlist Window",systemImage:"rectangle.on.rectangle").font(.system(size:12)).frame(maxWidth:.infinity).padding(.vertical,16)
                        }.buttonStyle(PlayerControlStyle()).frame(maxHeight:.infinity,alignment:.top)
                    } else { queue }
                }
        }
    }
    private var playlistTape: some View {
        TapeLabel(text: player.playlistName == "Untitled" ? String(format:"PLAYLIST / %02d",player.tracks.count) : String(player.playlistName.prefix(22)), secondary:true)
    }
    @ViewBuilder private var playlistActions: some View {
        if !playlistOnly {
            Button(playlistWindow.detached ? "Open Playlist Window" : "Detach Playlist") { ui.playlist = false; playlistWindow.detach() }
            if playlistWindow.detached {
                Button("Attach Playlist Here") { playlistWindow.attach(toMini:compact) }
            }
            Divider()
        }
        Button("Save Playlist") { ui.playlist = false; player.savePlaylist() }
        Button("Save Playlist As…") { ui.playlist = false; player.savePlaylist(asNew:true) }
        Button("Open Playlist…") { ui.playlist = false; player.openPlaylist() }.disabled(setup.editsBlocked)
        if !player.recentPlaylists.isEmpty {
            Menu("Recent Playlists") { ForEach(player.recentPlaylists,id:\.path) { url in Button(url.deletingPathExtension().lastPathComponent) { ui.playlist = false; player.openPlaylist(url) } } }.disabled(setup.editsBlocked)
        }
    }
    private var miniPlaylist: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(player.playlistName).font(.system(size:14,weight:.semibold)); Spacer()
                Button { ui.playlist = false; playlistWindow.detach() } label: { Image(systemName:"arrow.up.right.square").font(.system(size:13)).frame(width:30,height:30) }
                    .buttonStyle(PlayerControlStyle()).accessibilityLabel("Detach Playlist").stageHint("Detach playlist")
            }
            if setup.isLocked { Label("Setup locked",systemImage:"lock.fill").font(.system(size:10)).foregroundStyle(accent) }
            queue.frame(height:min(300,max(100,CGFloat(player.tracks.count)*56)))
            Divider()
            HStack {
                Menu { playlistActions } label: { Label("Playlist",systemImage:"folder").font(.system(size:11)) }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Button("Full Queue") { ui.playlist = false; AppDelegate.shared.showMain() }.buttonStyle(PlayerControlStyle()).padding(3)
            }
        }.padding(14).frame(width:340).foregroundStyle(.white).preferredColorScheme(.dark)
    }
    private var detachedPlaylist: some View {
        VStack(spacing:12) {
            HStack {
                playlistTape
                Spacer()
                Button { AppDelegate.shared.minimize(AppDelegate.shared.playlistWindow) } label: { Image(systemName:"minus").frame(width:28,height:28) }
                    .buttonStyle(PlayerControlStyle()).accessibilityLabel("Minimize Playlist").stageHint("Minimize playlist · restore from menu bar")
                Menu {
                    ForEach(PlaylistDockEdge.allCases,id:\.rawValue) { side in Button(side.title) { playlistWindow.dock(side,fromMini:playlistWindow.fromMini) } }
                    Button("Detach Window") { playlistWindow.detach() }
                    Divider()
                    Button("Attach to Mini Player") { playlistWindow.attach(toMini:true) }
                    Button("Attach to Main Player") { playlistWindow.attach(toMini:false) }
                } label: { Image(systemName:"link").font(.system(size:13)).frame(width:30,height:30) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Attach Playlist")
            }
            HStack {
                Text("\(player.tracks.count) tracks").font(.system(size:11)).foregroundStyle(.secondary)
                Spacer()
                if setup.isLocked { Label("Setup locked",systemImage:"lock.fill").font(.system(size:10)).foregroundStyle(accent) }
            }
            queue
            Divider()
            HStack(spacing:8) {
                Menu { playlistActions } label: { Label("Playlist",systemImage:"folder").font(.system(size:11)) }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Button { ui.protection.toggle() } label: { Label("Edit",systemImage:"slider.horizontal.3").font(.system(size:11)).padding(.horizontal,8).frame(height:30) }
                    .buttonStyle(PlayerControlStyle()).popover(isPresented:$ui.protection) { protectionSettings }
                setupLockButton
                Button { player.openFiles() } label: { Image(systemName:"plus").frame(width:30,height:30) }.buttonStyle(PlayerControlStyle()).disabled(setup.editsBlocked).accessibilityLabel("Add Audio")
            }
        }.padding(16).padding(.top,14).frame(minWidth:380,minHeight:280)
            .foregroundStyle(Color(stageHex:appearance.theme.text)).preferredColorScheme(.dark)
            .disabled(lock.isLocked).allowsHitTesting(!lock.isLocked)
            .overlay { if lock.isLocked { UnlockShield() } }
            .onChange(of:lock.isLocked) { _, locked in if locked { ui.protection = false } }
    }
    private var setupLockButton: some View {
        Button {
            if setup.isLocked { setup.unlock() } else { setup.lock(); ui.protection = false }
        } label: {
            Image(systemName:setup.isLocked ? "lock.fill":"lock.open").font(.system(size:13)).frame(width:30,height:30)
        }.buttonStyle(PlayerControlStyle(outline:.capsule,active:setup.isLocked))
            .accessibilityLabel(setup.isLocked ? "Unlock Setup":"Lock Setup")
            .stageHint(setup.isLocked ? "Unlock protected controls":"Protect your selected controls")
    }
    private var protectionSettings: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Protect your setup").font(.system(size:14,weight:.semibold))
            Text("Choose what Lock Setup protects.").font(.system(size:11)).foregroundStyle(.secondary)
            Toggle("Playlist edits & fades",isOn:$setup.protectEdits).disabled(setup.isLocked)
            Toggle("Track selection & skip",isOn:$setup.protectSelection).disabled(setup.isLocked)
            Toggle("Playback & seeking",isOn:$setup.protectPlayback).disabled(setup.isLocked)
            Toggle("Settings & mappings",isOn:$setup.protectSettings).disabled(setup.isLocked)
            Text("Automatic playback and transitions continue.").font(.system(size:10)).foregroundStyle(.secondary)
            setupLockButton
        }.padding(16).frame(width:280).preferredColorScheme(.dark)
            .disabled(lock.isLocked)
    }
    private var header: some View {
        HStack(spacing:8) {
            HStack(spacing:4) {
                HardPlayArtwork().frame(width:30,height:30)
                VStack(alignment:.leading,spacing:-2) { Text("Hard"); Text("Play") }
                    .font(.system(size:12,weight:.heavy,design:.rounded))
            }.accessibilityElement(children:.ignore).accessibilityLabel("Hard Play")
            Spacer()
            if !compact {
                Button { AppDelegate.shared.toggleWideLayout() } label: { Image(systemName:"arrow.left.and.right").frame(width:32,height:32) }
                    .buttonStyle(PlayerControlStyle()).accessibilityLabel("Toggle Wide Layout").stageHint("Wide / standard layout · drag window edges to resize").disabled(lock.isLocked)
            }
            Button {
                if menuBar { AppDelegate.shared.popover.performClose(nil) }
                else { AppDelegate.shared.minimize(compact ? AppDelegate.shared.miniWindow : AppDelegate.shared.mainWindow) }
            } label: { Image(systemName:"minus").frame(width:24,height:28) }
                .buttonStyle(PlayerControlStyle()).accessibilityLabel("Minimize Window").stageHint("Minimize · restore from menu bar").disabled(lock.isLocked)
            Button {
                if menuBar { AppDelegate.shared.detachMiniFromMenuBar() }
                else { AppDelegate.shared.attachMiniToMenuBar(hideMain:!compact) }
            } label: { Image(systemName:menuBar ? "pin.slash":"pin").frame(width:24,height:28) }
                .buttonStyle(PlayerControlStyle(active:menuBar)).accessibilityLabel(menuBar ? "Detach from Menu Bar":"Attach to Menu Bar").stageHint(menuBar ? "Detach as a floating player":"Attach player to menu bar").disabled(lock.isLocked)
            if compact && !menuBar {
                Button { placement.miniLocked.toggle() } label: { Image(systemName:placement.miniLocked ? "lock.rectangle.fill":"lock.rectangle").frame(width:24,height:28) }.buttonStyle(PlayerControlStyle(active:placement.miniLocked)).accessibilityLabel(placement.miniLocked ? "Unlock Window Position":"Lock Window Position").stageHint("Lock window position · playback stays available")
            }
            Button { player.undoEdit() } label: { Image(systemName:"arrow.uturn.backward").frame(width:24,height:28) }.buttonStyle(PlayerControlStyle()).accessibilityLabel("Undo Playlist Edit").stageHint("Undo playlist edit · ⌘Z").disabled(!player.canUndoEdit || setup.editsBlocked || lock.isLocked)
            Button { AppDelegate.shared.showSettingsWindow() } label: { Image(systemName:"slider.horizontal.3").frame(width:32,height:32) }.buttonStyle(PlayerControlStyle()).accessibilityLabel("Settings").stageHint("Audio, playback and button hints",below:true).disabled(lock.isLocked)
            Button { AppDelegate.shared.toggleMini() } label: { Image(systemName:"pip").frame(width:32,height:32) }.buttonStyle(PlayerControlStyle()).accessibilityLabel("Mini Player").stageHint("Show or hide the floating player",below:true).mapAction("mini").disabled(lock.isLocked)
            Button { lock.lock() } label: { Image(systemName:"lock").frame(width:32,height:32) }.buttonStyle(PlayerControlStyle(active:lock.isLocked)).accessibilityLabel("Lock Controls").stageHint("Lock controls · music keeps playing",below:true).mapAction("lock").disabled(lock.isLocked)
        }
    }
    private var transport: some View {
        HStack(spacing:compact ? 20 : 10) {
            Button { player.previous() } label: { Image(systemName:"backward.end.fill").frame(width:42,height:42) }.buttonStyle(PlayerControlStyle()).accessibilityLabel("Previous Track").disabled(setup.selectionBlocked).stageHint("Previous track").mapAction("previous")
            Button { player.toggle() } label: { HardPlayTransport(playing:player.playing,compact:compact) }.buttonStyle(HardPlayPressStyle()).accessibilityLabel(player.playing ? "Pause":"Play").disabled(setup.playbackBlocked).stageHint(player.playing ? "Pause playback" : "Play · ⌥⌘ Space").mapAction("playPause")
            Button { player.next() } label: { Image(systemName:"forward.end.fill").frame(width:42,height:42) }.buttonStyle(PlayerControlStyle()).accessibilityLabel("Next Track").disabled(setup.selectionBlocked).stageHint("Next track").mapAction("next")
            if !compact { Spacer(minLength:0); restartButtons }
        }.disabled(player.current == nil)
    }
    private var restartButtons: some View {
        HStack(spacing:6) {
            Button { player.restart() } label: { Label("Restart",systemImage:"arrow.counterclockwise").font(.system(size:11)).padding(.horizontal,9).frame(height:34) }.buttonStyle(PlayerControlStyle(outline:.capsule)).stageHint("Restart from 0:00").mapAction("restart")
            Button { player.resumeSaved() } label: { Label("Resume",systemImage:"play.fill").font(.system(size:11)).padding(.horizontal,9).frame(height:34) }.buttonStyle(PlayerControlStyle(active:true)).stageHint("Resume track").mapAction("resume")
        }.disabled(player.current == nil || setup.playbackBlocked)
    }
    private var settings: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("Audio & Playback").font(.system(size:14,weight:.semibold))
                Spacer()
                Button { if setup.settingsBlocked { setup.unlock() } else { setup.lockSettings() } } label: { Image(systemName:setup.settingsBlocked ? "lock.fill":"lock.open").frame(width:28,height:28) }
                    .buttonStyle(PlayerControlStyle(active:setup.settingsBlocked)).accessibilityLabel(setup.settingsBlocked ? "Unlock Settings":"Lock Settings").stageHint(setup.settingsBlocked ? "Unlock settings":"Protect settings")
            }
            Group {
            Button { AppDelegate.shared.showThemesWindow() } label: { Label("Themes & Appearance…",systemImage:"paintpalette").font(.system(size:12)).padding(8) }.buttonStyle(PlayerControlStyle())
            Button { AppDelegate.shared.showMappings() } label: { Label("Keyboard / MIDI…",systemImage:"pianokeys").font(.system(size:12)).padding(8) }.buttonStyle(PlayerControlStyle())
            Toggle("Show button hints",isOn:$hints.enabled)
            Text("Turn off for a distraction-free live set.").font(.system(size:10)).foregroundStyle(.secondary)
            Divider()
            HStack { Image(systemName:"speaker.wave.2"); Slider(value:$player.volume,in:0...1).tint(accent).accessibilityLabel("Volume") }
            Toggle("Shuffle",isOn:$player.shuffle)
            Toggle("Repeat Queue",isOn:$player.repeatAll)
            Picker("On Play",selection:$player.startMode) { Text("Restart").tag(StartMode.beginning);Text("Resume").tag(StartMode.resume) }
            Picker("At End",selection:$player.endMode) { Text("Next Track").tag(EndMode.next);Text("Stop").tag(EndMode.stop) }
            if player.endMode == .stop {
                Picker("Before End",selection:$player.stopBeforeEnd) { Text("0 s").tag(0.0);ForEach([1.0,2,3,5,10,15,30],id:\.self) { Text("\(Int($0)) s").tag($0) } }
            }
            Text("⌥⌘ Space — play/pause · ⌘L — lock").font(.system(size:10)).foregroundStyle(.secondary)
            }.disabled(setup.settingsBlocked)
        }.disabled(lock.isLocked)
    }
    private func fadeTitle(_ mode:FadeMode)->String { mode == .none ? "Off" : "\(mode.title) · \(Int(mode.seconds)) s" }
    private var queue: some View {
        ScrollView {
            LazyVStack(spacing:3) {
                if player.tracks.isEmpty { Text("Drop your music here").font(.system(size:12)).foregroundStyle(Color(stageHex:AppearancePreferences.shared.theme.text).opacity(0.65)).frame(maxWidth:.infinity).padding(.vertical,25) }
                ForEach(player.tracks) { track in
                    QueueTrackRow(player:player,track:track)
                }
            }
        }.frame(minHeight:100,maxHeight:.infinity)
    }
}
