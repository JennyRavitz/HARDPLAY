import AppKit
import SwiftUI
import AVFoundation

final class ControlLock: ObservableObject {
    static let shared = ControlLock()
    @Published private(set) var isLocked = false
    func lock() { isLocked = true }
    @discardableResult func unlock(swipe: Double) -> Bool {
        guard swipe >= 330 else { return false }
        isLocked = false; return true
    }
    @discardableResult func unlock(heldFor seconds: Double) -> Bool {
        guard seconds >= 3 else { return false }
        isLocked = false; return true
    }
}

/// Bounded peak envelopes derived from decoded PCM, never a generated waveform.
@MainActor final class Waveforms: ObservableObject {
    static let shared = Waveforms()
    struct Envelope { let peaks: [Double]; let duration: Double }
    @Published private(set) var cache: [String: Envelope] = [:]
    private var pending: [String: Task<Envelope, Never>] = [:]
    nonisolated static func key(_ track:Track)->String {track.id+"|"+track.url.path}
    func load(_ track: Track) async {
        let key=Self.key(track)
        if cache[key] != nil { return }
        let job: Task<Envelope, Never>
        if let existing = pending[key] { job = existing }
        else {
            job = Task.detached(priority: .utility) { await Self.decode(track.url) }
            pending[key] = job
        }
        let result = await job.value
        if cache.count >= 24, let key = cache.keys.first { cache.removeValue(forKey: key) }
        cache[key] = result; pending.removeValue(forKey:key)
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
        let points: [(Double, Double)] = [(0.018,0.012),(0.986,0),(1,0.1),(0.994,0.48),(1,0.9),(0.985,1),(0.012,0.988),(0,0.88),(0.006,0.5),(0,0.13)]
        var p = Path(); p.move(to: CGPoint(x: r.width * points[0].0, y: r.height * points[0].1))
        for point in points.dropFirst() { p.addLine(to: CGPoint(x: r.width * point.0, y: r.height * point.1)) }; p.closeSubpath(); return p
    }
}
var tapeB: Color { Color(stageHex:AppearancePreferences.shared.theme.tape) }
struct TapeLabel: View {
    @ObservedObject private var appearance=AppearancePreferences.shared
    var text: String
    var secondary = false
    var body: some View {
        Text(text).font(.custom(StageTypography.name, size: 14)).foregroundStyle(tapeInk)
            .padding(.horizontal, 12).padding(.vertical, 5).background(TapeSurface()).rotationEffect(.degrees(secondary ? 1 : -1))
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
    var actualDuration: Double { (right ? player.stageRightDuration : player.stageLeftDuration) > 0 ? (right ? player.stageRightDuration : player.stageLeftDuration) : (track.flatMap { waves.cache[Waveforms.key($0)]?.duration } ?? 0) }
    var elapsed: Double { right ? player.stageRightTime : player.stageLeftTime }
    var gain: Double { right ? player.stageRightGain : player.stageLeftGain }
    var seekable: Bool { track != nil && (right ? player.isCrossfading : !player.isCrossfading) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(player.queueNumber(track)).font(.custom(StageTypography.name, size: compact ? 24 : 28)).monospacedDigit()
                Spacer()
                Text(right ? (player.isCrossfading ? "INCOMING" : "NEXT") : (player.isCrossfading ? "OUTGOING" : "NOW"))
                    .font(.stage(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Color(stageHex:AppearancePreferences.shared.theme.text).opacity(0.65))
            }
            Text(track?.title ?? (right ? "End of Queue" : "Add your music"))
                .font(.stage(size: (compact ? 13 : 16) * AppearancePreferences.shared.theme.textScale, weight: .semibold)).lineLimit(2).frame(height:(compact ? 34 : 40) * AppearancePreferences.shared.theme.textScale,alignment:.topLeading).stageHint(track?.title ?? "No track selected")
            HStack { Text("\(timeLabel(elapsed)) / \(timeLabel(actualDuration))"); Spacer(); Text("\(Int(gain * 100))%") }
                .font(.stage(size: 10, design: .monospaced)).foregroundStyle(Color(stageHex:AppearancePreferences.shared.theme.text).opacity(0.7))
            StageWaveform(identity:track?.id ?? "empty",peaks:track.flatMap { waves.cache[Waveforms.key($0)]?.peaks } ?? [],duration:actualDuration,elapsed:elapsed,gain:gain,color:right ? tapeB:accent,enabled:track != nil && !ControlLock.shared.isLocked && !SetupLock.shared.playbackBlocked) { seconds,play in
                if let track {player.waveformAction(track,seconds:seconds,duration:actualDuration,play:play)}
            }.frame(height:compact ? 42:50)
                .stageHint(right && !player.isCrossfading ? "Hover: time · Click: set next start · Double-click: play here" : "Hover: time · Click or drag: seek · Double-click: play here")
            GeometryReader { g in
                Rectangle().fill(.white.opacity(0.1)).overlay(alignment: .leading) {
                    Rectangle().fill(right ? tapeB : accent).frame(width: g.size.width * gain)
                }
            }.frame(height: 3)

        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors:[Color.black.opacity(0.24),Color.white.opacity(0.035)],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:appearance.theme.radius))
        .overlay(RoundedRectangle(cornerRadius:appearance.theme.radius).stroke(.white.opacity(0.09),lineWidth:1))
        .contextMenu {
            if let track {
                Button {AppDelegate.shared.showQuickEdit(track)} label: {MarkerLabel("Edit Audio…",systemImage:"scissors")}
                    .disabled(SetupLock.shared.editsBlocked || ControlLock.shared.isLocked)
            }
        }
        .task(id: track.map(Waveforms.key)) { if let track { await waves.load(track) } }
    }
}

/// Accumulates continuous clockwise movement; straight drags and jumps never unlock.
struct CircularUnlockProgress {
    private(set) var degrees:Double=0
    private var previous:Double?
    mutating func begin(_ point:CGPoint,center:CGPoint) {
        degrees=0;previous=angle(point,center:center)
    }
    private func angle(_ point:CGPoint,center:CGPoint)->Double? {
        let dx=point.x-center.x,dy=point.y-center.y,r=hypot(dx,dy)
        guard (36...84).contains(r) else {return nil}
        return atan2(dy,dx)*180 / .pi
    }
    mutating func move(_ point:CGPoint,center:CGPoint)->Bool {
        guard let next=angle(point,center:center),let prior=previous else {degrees=0;previous=nil;return false}
        var delta=prior-next
        if delta > 180 {delta-=360};if delta < -180 {delta+=360}
        guard abs(delta)<=65 else {degrees=0;previous=nil;return false}
        degrees=min(360,max(0,degrees+delta));previous=next
        return degrees>=330
    }
}
struct NativeUnlockControl:NSViewRepresentable {
    final class UnlockView:NSView {
        private var progress=CircularUnlockProgress()
        private var timer:Timer?
        private var heldAt:Date?
        private var holdProgress:Double=0
        override var acceptsFirstResponder:Bool {true}
        override var mouseDownCanMoveWindow:Bool {false}
        private var center:CGPoint {CGPoint(x:bounds.midX,y:bounds.midY)}
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {window.makeFirstResponder(self)} else {cleanUp()}
        }
        override func draw(_ dirtyRect:NSRect) {
            let c=center,r:CGFloat=60
            let circle=NSBezierPath(ovalIn:NSRect(x:c.x-r,y:c.y-r,width:r*2,height:r*2))
            NSColor.white.withAlphaComponent(0.14).setStroke();circle.lineWidth=7;circle.stroke()
            let fraction=max(progress.degrees/330,holdProgress)
            let arc=NSBezierPath();arc.appendArc(withCenter:c,radius:r,startAngle:90,endAngle:90-CGFloat(fraction)*360,clockwise:true)
            NSColor(calibratedRed:0.60,green:0.81,blue:1,alpha:1).setStroke();arc.lineWidth=7;arc.lineCapStyle = .round;arc.stroke()
            let thumbAngle=(90-CGFloat(progress.degrees)) * .pi/180
            let thumb=NSRect(x:c.x+cos(thumbAngle)*r-9,y:c.y+sin(thumbAngle)*r-9,width:18,height:18)
            NSColor(calibratedRed:0.72,green:0.87,blue:1,alpha:1).setFill();NSBezierPath(ovalIn:thumb).fill()
            let face=NSRect(x:c.x-22,y:c.y-22,width:44,height:44)
            NSColor(calibratedRed:0.12,green:0.22,blue:0.32,alpha:1).setFill();NSBezierPath(roundedRect:face,xRadius:12,yRadius:12).fill()
            if let image=NSImage(systemSymbolName:"lock.fill",accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[.white])) {image.draw(in:NSRect(x:c.x-9,y:c.y-11,width:18,height:22))}
            setAccessibilityValue("\(Int(fraction*100)) percent")
        }
        override func mouseDown(with event:NSEvent) {
            window?.makeFirstResponder(self);progress.begin(convert(event.locationInWindow,from:nil),center:center);needsDisplay=true
        }
        override func mouseDragged(with event:NSEvent) {
            if progress.move(convert(event.locationInWindow,from:nil),center:center) {_ = ControlLock.shared.unlock(swipe:progress.degrees)}
            needsDisplay=true
        }
        override func mouseUp(with event:NSEvent) {progress=CircularUnlockProgress();needsDisplay=true}
        override func keyDown(with event:NSEvent) {
            guard !event.isARepeat,event.keyCode==49 || event.keyCode==36,heldAt==nil else {return}
            heldAt=Date()
            let ticker=Timer(timeInterval:0.04,repeats:true) {[weak self] _ in
                guard let self,let started=self.heldAt else {return}
                let seconds=Date().timeIntervalSince(started);self.holdProgress=min(1,seconds/3);self.needsDisplay=true
                if seconds>=3 {self.cleanUp();_ = ControlLock.shared.unlock(heldFor:seconds)}
            };timer=ticker;RunLoop.main.add(ticker,forMode:.common)
        }
        override func keyUp(with event:NSEvent) {if event.keyCode==49 || event.keyCode==36 {cleanUp()}}
        override func resignFirstResponder()->Bool {cleanUp();return super.resignFirstResponder()}
        // VoiceOver focuses this control; Space/Return must still be held for three seconds.
        override func accessibilityPerformPress()->Bool {window?.makeFirstResponder(self);return true}
        func cleanUp() {timer?.invalidate();timer=nil;heldAt=nil;holdProgress=0;needsDisplay=true}
    }
    func makeNSView(context:Context)->UnlockView {
        let view=UnlockView();view.setAccessibilityElement(true);view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Unlock Controls");view.setAccessibilityHelp("Drag clockwise around the ring, or hold Space for three seconds")
        return view
    }
    func updateNSView(_ view:UnlockView,context:Context) {}
    static func dismantleNSView(_ view:UnlockView,coordinator:()) {view.cleanUp()}
}
struct UnlockShield:View {
    var body:some View {Color.black.opacity(0.12).allowsHitTesting(false)}
}

private struct PlayerFitHeightKey:PreferenceKey {
    static var defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat) {value=max(value,nextValue())}
}
private struct QueueFitHeightKey:PreferenceKey {
    static var defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat) {value=max(value,nextValue())}
}
struct PlayerView: View {
    @ObservedObject var player = Player.shared
    @ObservedObject var lock = ControlLock.shared
    @StateObject private var ui = PlayerViewState()
    @ObservedObject var setup = SetupLock.shared
    @ObservedObject var playlistWindow = PlaylistWindowState.shared
    @ObservedObject var hints = HintPreferences.shared
    @ObservedObject var placement = FloatingPlacement.shared
    @ObservedObject var windows = WindowPresentation.shared
    @ObservedObject var workspace=WorkspaceState.shared
    var compact = false
    var settingsOnly = false
    var embedded = false
    @ObservedObject var appearance = AppearancePreferences.shared
    var playlistOnly = false
    var menuBar = false
    @ViewBuilder var body: some View {
        Group { if settingsOnly { ScrollView {settings} } else if playlistOnly { detachedPlaylist } else { playerBody } }
            .overlay(alignment:.trailing) {
                if ui.patchOpen,!settingsOnly,!playlistOnly {PatchDrawer(open:$ui.patchOpen,compact:compact).transition(.move(edge:.trailing).combined(with:.opacity)).zIndex(10)}
            }
            .audioFileDrop(enabled:!settingsOnly)
            .fixedControlHints(enabled:!embedded).font(.stage(.body))
    }
    @ViewBuilder private var playerBody: some View {
        if compact { stageBody(wide:false).frame(minWidth:380) }
        else if let section=workspace.section {workspaceBody(section)}
        else {
            GeometryReader { geometry in
                let wide=geometry.size.width >= 840
                let required:CGFloat=playlistWindow.detached ? 660:(wide ? 720:820)
                if windows.autoFit {
                    ScrollView(.vertical) {
                        stageBody(wide:wide).fixedSize(horizontal:false,vertical:true)
                            .background(GeometryReader {proxy in Color.clear.preference(key:PlayerFitHeightKey.self,value:proxy.size.height)})
                    }.onPreferenceChange(PlayerFitHeightKey.self) {windows.measure($0)}
                        .onChange(of:hints.enabled) {_,_ in windows.requestFit()}
                }else if geometry.size.height < required {
                    ScrollView(.vertical) {stageBody(wide:wide).frame(minHeight:required)}
                }else {stageBody(wide:wide)}
            }
                .frame(minWidth:600,minHeight:420)
        }
    }
    private func workspaceBody(_ section:WorkspaceSection)->some View {
        VStack(spacing:10) {
            header
            ScrollView(.horizontal) {
                HStack(spacing:6) {
                    Button {workspace.player()} label:{MarkerLabel("Player",systemImage:"play.fill").font(.stage(size:11)).padding(7)}.buttonStyle(PlayerControlStyle())
                    ForEach(WorkspaceSection.allCases) {tab in
                        Button {workspace.open(tab,at:.inside)} label:{Text(tab.title).font(.stage(size:11)).padding(7)}
                            .buttonStyle(PlayerControlStyle(active:section == tab)).accessibilityLabel("Workspace: "+tab.title)
                    }
                }
            }.fixedSize(horizontal:false,vertical:true).disabled(lock.isLocked)
            WorkspacePane(section:section).disabled(lock.isLocked)
            HStack(spacing:10) {
                Button {player.toggle()} label:{MarkerIcon(systemName:player.playing ? "pause.fill":"play.fill",size:20).frame(width:38,height:34)}
                    .buttonStyle(PlayerControlStyle(primary:true)).accessibilityLabel(player.playing ? "Pause":"Play").disabled(setup.playbackBlocked || player.current == nil)
                Text(player.current?.title ?? "No track").font(.stage(size:13)).lineLimit(1)
                Spacer()
                Text("\(timeLabel(player.elapsed)) / \(timeLabel(player.duration))").font(.stage(size:12)).monospacedDigit()
                Button {workspace.player()} label:{MarkerIcon(systemName:"xmark").frame(width:30,height:30)}.buttonStyle(PlayerControlStyle()).accessibilityLabel("Return to Player")
            }.disabled(lock.isLocked)
        }.padding(16).frame(minWidth:660,minHeight:500).foregroundStyle(Color(stageHex:appearance.theme.text)).preferredColorScheme(.dark)
            .overlay {if lock.isLocked {UnlockShield()}}
    }
    private func stageBody(wide:Bool) -> some View {
        VStack(spacing:appearance.theme.spacing) {
            header
            QuickActionBar()
            BackupStatusStrip()
            let layout = wide && !playlistWindow.detached ? AnyLayout(HStackLayout(alignment:.top,spacing:22)) : AnyLayout(VStackLayout(spacing:10))
            layout {
                playbackPanel.frame(maxWidth:.infinity,alignment:.top)
                playlistPanel.disabled(lock.isLocked).frame(maxWidth:.infinity,maxHeight:compact || windows.autoFit ? nil:.infinity,alignment:.top)
            }
        }
        .padding(compact ? 14 : 16).frame(maxWidth:.infinity,maxHeight:compact || windows.autoFit ? nil:.infinity,alignment:.top)
        .foregroundStyle(Color(stageHex:appearance.theme.text)).preferredColorScheme(.dark).font(.stage(.body))
        .overlay { if lock.isLocked { UnlockShield() } }
        .onChange(of:playlistWindow.detached) { _, detached in if detached { ui.playlist = false } }
        .onChange(of:lock.isLocked) { _, locked in if locked { ui.settings = false; ui.playlist = false; ui.protection = false } }
    }
    private var playbackPanel: some View {
        VStack(spacing:10) {
                HStack(alignment: .top, spacing: 10) {
                    StageDeck(player: player, track: player.stageLeft, right: false, compact: compact).disabled(lock.isLocked).allowsHitTesting(!lock.isLocked)
                    StageDeck(player: player, track: player.stageRight, right: true, compact: compact).disabled(lock.isLocked).allowsHitTesting(!lock.isLocked)
                }.padding(.trailing,16).overlay(alignment:.trailing) {
                    PatchHoldEdge {withAnimation(.easeInOut(duration:0.22)) {ui.patchOpen.toggle()}}.frame(width:14).disabled(false)
                }
                HStack(spacing: 8) {
                    Text("\(player.queueNumber(player.stageLeft)) → \(player.queueNumber(player.stageRight))").font(.stage(size: 10, design: .monospaced))
                    GeometryReader { g in
                        Capsule().fill(.white.opacity(0.1)).overlay(alignment: .leading) {
                            Capsule().fill(LinearGradient(colors: [accent,tapeB], startPoint: .leading, endPoint: .trailing)).frame(width: g.size.width * (player.isCrossfading ? player.fadeProgress : 0))
                        }
                    }.frame(height: 4)
                    Text(player.isCrossfading ? String(format: "%.1f s", player.transitionRemaining) : (player.endMode == .stop ? "STOP" : ""))
                        .font(.stage(size: 10, design: .monospaced))
                }.foregroundStyle(Color(stageHex:AppearancePreferences.shared.theme.text).opacity(0.7))
                SeekPositionSlider(value: Binding(get: { ui.scrubbing ? ui.scrub : player.elapsed }, set: { ui.scrub = $0 }), duration:player.duration, onEditingChanged: { editing in
                    if editing { ui.scrub = player.elapsed; ui.scrubbing = true } else { player.seek(ui.scrub); ui.scrubbing = false }
                }).disabled(player.current == nil || setup.playbackBlocked || lock.isLocked)
                transport
                if compact { restartButtons }
                HStack(spacing:8) {
                    MarkerIcon(systemName:player.volume == 0 ? "speaker.slash":"speaker.wave.2").font(.stage(size:12)).foregroundStyle(accent)
                    Slider(value:$player.volume,in:0...1).controlSize(.small).tint(accent).accessibilityLabel("Master Volume")
                    Text("\(Int(player.volume * 100))%").font(.stage(size:11,design:.monospaced)).frame(width:38,alignment:.trailing)
                }.disabled(setup.playbackBlocked || lock.isLocked).mapAction("volume")
                QueuePolicyControls(player:player).disabled(lock.isLocked)
                if let error = player.error { Text(error).font(.stage(size: 11)).foregroundStyle(.orange).fixedSize(horizontal:false, vertical:true) }
        }
    }
    private var playlistPanel: some View {
        VStack(spacing:10) {
                HStack {
                    playlistTape
                    Menu { playlistActions } label: { MarkerIcon(systemName:"folder").frame(width:24,height:28) }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Playlist Files")
                    Spacer()
                    if compact {
                        Button { AppDelegate.shared.showMain() } label: { MarkerLabel("Edit Queue",systemImage:"list.bullet").font(.stage(size:11)).padding(.horizontal,9).frame(height:30) }
                            .buttonStyle(PlayerControlStyle()).accessibilityLabel("Open Full Queue")
                    } else {
                        Button { ui.protection.toggle() } label: { MarkerLabel("Edit", systemImage:"slider.horizontal.3").font(.stage(size:11)).padding(.horizontal,8).frame(height:30) }
                            .buttonStyle(PlayerControlStyle()).popover(isPresented:$ui.protection) { protectionSettings }
                        setupLockButton
                        Button { player.openFiles() } label: { MarkerIcon(systemName:"plus").frame(width:30,height:30) }.buttonStyle(PlayerControlStyle()).disabled(setup.editsBlocked).accessibilityLabel("Add Audio").stageHint("Add audio files or a folder",below:true)
                    }
                }.padding(.top,3)
                if !compact {
                    HStack(spacing:6) {
                        playlistPresentationButton(toMini:false)
                        Menu {
                            ForEach(PlaylistDockEdge.allCases,id:\.rawValue) { side in
                                Button(side.title) { playlistWindow.dock(side) }
                            }
                        } label: { MarkerLabel(playlistWindow.edge?.title ?? "Dock",systemImage:"rectangle.split.2x1").font(.stage(size:11)).padding(6) }
                            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Playlist Dock Side")
                        Spacer(minLength:0)
                    }
                    if playlistWindow.detached {
                        Button { AppDelegate.shared.showPlaylistWindow() } label: {
                            MarkerLabel("Open Playlist Window",systemImage:"rectangle.on.rectangle").font(.stage(size:12)).frame(maxWidth:.infinity).padding(.vertical,16)
                        }.buttonStyle(PlayerControlStyle()).frame(maxHeight:windows.autoFit ? nil:.infinity,alignment:.top)
                    } else { queue }
                }
        }
    }
    private var playlistTape: some View {
        SetNameTape(player:player,maxWidth:compact ? 160:280,onOpen:playlistOnly ? nil:{ playlistWindow.toggleDrawer(fromMini:compact && !menuBar) })
    }
    @ViewBuilder private var playlistActions: some View {
        if !playlistOnly {
            Button(playlistWindow.detached ? "Open Playlist Window" : "Detach Playlist") { ui.playlist = false; playlistWindow.detach() }
            if playlistWindow.detached {
                Button("Attach Playlist Here") { playlistWindow.attach(toMini:compact) }
            }
            Divider()
        }
        Button("New Playlist…") {ui.playlist=false;player.requestNewPlaylist()}.disabled(setup.editsBlocked)
        Button("Delete Playlist…",role:.destructive) {ui.playlist=false;player.requestDeletePlaylist()}.disabled(setup.editsBlocked || !player.canDeletePlaylist)
        Divider()
        Button("Save Playlist") { ui.playlist = false; player.savePlaylist() }
        Button("Save Playlist As…") { ui.playlist = false; player.savePlaylist(asNew:true) }
        Button("Open Playlist…") { ui.playlist = false; player.openPlaylist() }.disabled(setup.editsBlocked)
        if !player.recentPlaylists.isEmpty {
            Menu("Recent Playlists") { ForEach(player.recentPlaylists,id:\.path) { url in Button(url.deletingPathExtension().lastPathComponent) { ui.playlist = false; player.openPlaylist(url) } } }.disabled(setup.editsBlocked)
        }
    }
    private func playlistPresentationButton(toMini:Bool)->some View {
        Button {
            ui.playlist=false
            if playlistWindow.detached {playlistWindow.attach(toMini:toMini)}else {playlistWindow.detach(fromMini:toMini)}
        } label: {
            MarkerIcon(systemName:playlistWindow.detached ? "playlist.embed":"playlist.detach",size:21).frame(width:36,height:34)
        }.buttonStyle(PlayerControlStyle(active:playlistWindow.detached))
            .accessibilityLabel(playlistWindow.detached ? "Embed Playlist":"Separate Playlist")
            .accessibilityValue(playlistWindow.detached ? "Separate window":"Inside player")
            .stageHint(playlistWindow.detached ? "Bring the playlist back inside this player":"Move the playlist into its own window")
    }
    private var miniPlaylist: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(player.playlistName).font(.stage(size:14,weight:.semibold)); Spacer()
                playlistPresentationButton(toMini:true)
            }
            if setup.isLocked { MarkerLabel("Setup locked",systemImage:"lock.fill").font(.stage(size:10)).foregroundStyle(accent) }
            queue.frame(height:min(300,max(100,CGFloat(player.tracks.count)*56)))
            Divider()
            HStack {
                Menu { playlistActions } label: { MarkerLabel("Playlist",systemImage:"folder").font(.stage(size:11)) }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Button("Full Queue") { ui.playlist = false; AppDelegate.shared.showMain() }.buttonStyle(PlayerControlStyle()).padding(3)
            }
        }.padding(14).frame(width:340).foregroundStyle(.white).preferredColorScheme(.dark).font(.stage(.body))
    }
    private var detachedPlaylist: some View {
        VStack(spacing:12) {
            HStack {
                playlistTape
                Spacer()
                Button { AppDelegate.shared.minimize(AppDelegate.shared.playlistWindow) } label: { MarkerIcon(systemName:"minus").frame(width:28,height:28) }
                    .buttonStyle(PlayerControlStyle()).accessibilityLabel("Minimize Playlist").stageHint("Minimize playlist · restore from menu bar")
                playlistPresentationButton(toMini:playlistWindow.fromMini)
                Menu {
                    ForEach(PlaylistDockEdge.allCases,id:\.rawValue) { side in Button(side.title) { playlistWindow.dock(side,fromMini:playlistWindow.fromMini) } }
                    Button("Detach Window") { playlistWindow.detach() }
                    Divider()
                    Button("Attach to Mini Player") { playlistWindow.attach(toMini:true) }
                    Button("Attach to Main Player") { playlistWindow.attach(toMini:false) }
                } label: { MarkerIcon(systemName:"link").font(.stage(size:13)).frame(width:30,height:30) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Attach Playlist")
            }
            HStack {
                Text("\(player.tracks.count) tracks").font(.stage(size:11)).foregroundStyle(.secondary)
                Spacer()
                if setup.isLocked { MarkerLabel("Setup locked",systemImage:"lock.fill").font(.stage(size:10)).foregroundStyle(accent) }
            }
            queue
            Divider()
            HStack(spacing:8) {
                Menu { playlistActions } label: { MarkerLabel("Playlist",systemImage:"folder").font(.stage(size:11)) }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Button { ui.protection.toggle() } label: { MarkerLabel("Edit",systemImage:"slider.horizontal.3").font(.stage(size:11)).padding(.horizontal,8).frame(height:30) }
                    .buttonStyle(PlayerControlStyle()).popover(isPresented:$ui.protection) { protectionSettings }
                setupLockButton
                Button { player.openFiles() } label: { MarkerIcon(systemName:"plus").frame(width:30,height:30) }.buttonStyle(PlayerControlStyle()).disabled(setup.editsBlocked).accessibilityLabel("Add Audio")
            }
        }.padding(16).padding(.top,14).frame(minWidth:380,minHeight:280)
            .foregroundStyle(Color(stageHex:appearance.theme.text)).preferredColorScheme(.dark).font(.stage(.body))
            .disabled(lock.isLocked).allowsHitTesting(!lock.isLocked)
            .overlay { if lock.isLocked { UnlockShield() } }
            .onChange(of:lock.isLocked) { _, locked in if locked { ui.protection = false } }
    }
    private var setupLockButton: some View {
        Button {
            if setup.isLocked { setup.unlock() } else { setup.lock(); ui.protection = false }
        } label: {
            MarkerIcon(systemName:setup.isLocked ? "lock.fill":"lock.open").font(.stage(size:13)).frame(width:30,height:30)
        }.buttonStyle(PlayerControlStyle(outline:.capsule,active:setup.isLocked))
            .accessibilityLabel(setup.isLocked ? "Unlock Setup":"Lock Setup")
            .stageHint(setup.isLocked ? "Unlock protected controls":"Protect your selected controls")
    }
    private var protectionSettings: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Protect your setup").font(.stage(size:14,weight:.semibold))
            Text("Choose what Lock Setup protects.").font(.stage(size:11)).foregroundStyle(.secondary)
            Toggle("Playlist edits & fades",isOn:$setup.protectEdits).disabled(setup.isLocked)
            Toggle("Track selection & skip",isOn:$setup.protectSelection).disabled(setup.isLocked)
            Toggle("Playback & seeking",isOn:$setup.protectPlayback).disabled(setup.isLocked)
            Toggle("Settings & mappings",isOn:$setup.protectSettings).disabled(setup.isLocked)
            Text("Automatic playback and transitions continue.").font(.stage(size:10)).foregroundStyle(.secondary)
            setupLockButton
        }.padding(16).frame(width:280).preferredColorScheme(.dark).font(.stage(.body))
            .disabled(lock.isLocked)
    }
    private func toolbarButton(_ title:String,_ icon:String,active:Bool=false,action:@escaping ()->Void)->some View {
        Button(action:action) {MarkerIcon(systemName:icon,size:18).frame(width:32,height:32)}
            .buttonStyle(PlayerControlStyle(active:active)).accessibilityLabel(title).stageHint(title)
    }
    private var header:some View {
        VStack(spacing:12) {
            HStack(spacing:12) {
                if !compact {
                    Button {AppDelegate.shared.toggleMini()} label:{MiniStageLabel()}
                        .buttonStyle(PlayerControlStyle(active:windows.mini)).accessibilityLabel("Mini Hardplay").accessibilityValue(windows.mini ? "Open":"Hidden")
                        .stageHint("mini hardplay · open or hide the floating player").mapAction("mini").disabled(lock.isLocked)
                    toolbarButton("Nano Player","player.nano",active:windows.nano) {AppDelegate.shared.toggleNano()}.disabled(lock.isLocked)
                    toolbarButton(windows.fullScreen ? "Exit Full Screen":"Full Screen Player",windows.fullScreen ? "player.exitfullscreen":"player.fullscreen",active:windows.fullScreen) {AppDelegate.shared.toggleStageFullScreen()}.disabled(lock.isLocked)
                }else {
                    toolbarButton("Open Main Player","player.fullscreen") {AppDelegate.shared.showMain()}
                }
                Spacer(minLength:4)
                toolbarButton("Toggle Control Hints","questionmark",active:hints.enabled) {withAnimation(.easeInOut(duration:0.18)) {hints.enabled.toggle()}}
                Button {withAnimation(.easeInOut(duration:0.22)) {ui.patchOpen.toggle()}} label:{MarkerLabel("PATCH",systemImage:lock.isLocked ? "lock.fill":"slider.horizontal.3").font(.stage(size:12,weight:.bold)).padding(.horizontal,10).frame(height:32)}
                    .buttonStyle(PlayerControlStyle(active:ui.patchOpen || lock.isLocked)).accessibilityLabel("PATCH Rear Panel").accessibilityValue(ui.patchOpen ? "Open":"Closed")
                    .stageHint("PATCH · rear panel: settings and locks. Or hold the right edge beside the audio display for 2 seconds.")
            }
            HStack(spacing:12) {
                if !compact {
                    toolbarButton("Workspace Mode",workspace.mode == .single ? "workspace.single":"workspace.nearby",active:workspace.mode == .single) {workspace.toggle()}
                    toolbarButton("Auto Fit Window","window.fit",active:windows.autoFit) {windows.autoFit.toggle()}
                    toolbarButton("Toggle Wide Layout","arrow.left.and.right") {AppDelegate.shared.toggleWideLayout()}
                    toolbarButton("Undo Playlist Edit","arrow.uturn.backward") {player.undoEdit()}.disabled(!player.canUndoEdit || setup.editsBlocked)
                    toolbarButton("Nano on Minimize","player.autoNano",active:windows.nanoOnMinimize) {windows.nanoOnMinimize.toggle()}
                }else if !menuBar {
                    toolbarButton(placement.miniLocked ? "Unlock Window Position":"Lock Window Position",placement.miniLocked ? "lock.rectangle.fill":"lock.rectangle",active:placement.miniLocked) {placement.miniLocked.toggle()}
                }
                Spacer(minLength:0)
                toolbarButton("Minimize Window","minus") {
                    if menuBar {AppDelegate.shared.popover.performClose(nil)}else {AppDelegate.shared.minimize(compact ? AppDelegate.shared.miniWindow:AppDelegate.shared.mainWindow)}
                }
                toolbarButton(menuBar ? "Detach from Menu Bar":"Attach to Menu Bar",menuBar ? "pin.slash":"pin",active:menuBar) {
                    if menuBar {AppDelegate.shared.detachMiniFromMenuBar()}else {AppDelegate.shared.attachMiniToMenuBar(hideMain:!compact)}
                }
            }.disabled(lock.isLocked)
            if ["FOH","Stage Crew","Stagehand"].contains(appearance.theme.preset) {
                HStack {
                    Text(appearance.theme.preset == "FOH" ? "FOH / PLAYBACK":"STAGE CREW / AUDIO").font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(1.4)
                    Spacer()
                    Text("HP—01  /  PATCH →").font(.system(size:9,weight:.medium,design:.monospaced))
                }.foregroundStyle(accent.opacity(0.55)).accessibilityHidden(true)
            }
        }
    }
    private var transport: some View {
        HStack(spacing:compact ? 20 : 10) {
            Button { player.previous() } label: { MarkerIcon(systemName:"backward.end.fill").frame(width:42,height:42) }.buttonStyle(PlayerControlStyle()).accessibilityLabel("Previous Track").disabled(setup.selectionBlocked).stageHint("Previous track").mapAction("previous")
            Button { player.toggle() } label: { HardPlayTransport(playing:player.playing,compact:compact) }.buttonStyle(HardPlayPressStyle()).accessibilityLabel(player.playing ? "Pause":"Play").disabled(setup.playbackBlocked).stageHint(player.playing ? "Pause playback" : "Play · ⌥⌘ Space").mapAction("playPause")
            Button { player.next() } label: { MarkerIcon(systemName:"forward.end.fill").frame(width:42,height:42) }.buttonStyle(PlayerControlStyle()).accessibilityLabel("Next Track").disabled(setup.selectionBlocked).stageHint("Next track").mapAction("next")
            if !compact { Spacer(minLength:0); restartButtons }
        }.disabled(player.current == nil || lock.isLocked)
    }
    private var restartButtons: some View {
        HStack(spacing:12) {
            Button { player.restart() } label: { MarkerLabel("Restart",systemImage:"arrow.counterclockwise").font(.stage(size:11)).padding(.horizontal,9).frame(height:34) }.buttonStyle(PlayerControlStyle(outline:.capsule)).stageHint("Restart from 0:00").mapAction("restart")
            Button { player.resumeSaved() } label: { MarkerLabel("Resume",systemImage:"play.fill").font(.stage(size:11)).padding(.horizontal,9).frame(height:34) }.buttonStyle(PlayerControlStyle(active:true)).stageHint("Resume track").mapAction("resume")
        }.disabled(player.current == nil || setup.playbackBlocked || lock.isLocked)
    }
    private var settings: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("Audio & Playback").font(.stage(size:14,weight:.semibold))
                Spacer()
                Button { if setup.settingsBlocked { setup.unlock() } else { setup.lockSettings() } } label: { MarkerIcon(systemName:setup.settingsBlocked ? "lock.fill":"lock.open").frame(width:28,height:28) }
                    .buttonStyle(PlayerControlStyle(active:setup.settingsBlocked)).accessibilityLabel(setup.settingsBlocked ? "Unlock Settings":"Lock Settings").stageHint(setup.settingsBlocked ? "Unlock settings":"Protect settings")
            }
            Group {
            Button { AppDelegate.shared.showThemesWindow() } label: { MarkerLabel("Themes & Appearance…",systemImage:"paintpalette").font(.stage(size:12)).padding(8) }.buttonStyle(PlayerControlStyle()).windowDestinationMenu(.themes)
            Button { AppDelegate.shared.showMappings() } label: { MarkerLabel("Keyboard / MIDI…",systemImage:"pianokeys").font(.stage(size:12)).padding(8) }.buttonStyle(PlayerControlStyle()).windowDestinationMenu(.mappings)
            Button { AppDelegate.shared.showBackupWindow() } label: { MarkerLabel("Timecode & Backup…",systemImage:"network").font(.stage(size:12)).padding(8) }.buttonStyle(PlayerControlStyle()).windowDestinationMenu(.backup)
            Button {AppDelegate.shared.showWebViewer()} label: {MarkerLabel("Web Viewer…",systemImage:"iphone").font(.stage(size:12)).padding(8)}.buttonStyle(PlayerControlStyle()).windowDestinationMenu(.viewer)
            Button {workspace.toggle()} label:{MarkerLabel("Workspace: "+workspace.title,systemImage:workspace.mode == .single ? "workspace.single":"workspace.nearby").padding(7)}.buttonStyle(PlayerControlStyle())
            WindowDestinationSettings()
            QuickActionSettings()
            Toggle("Auto fit player height",isOn:$windows.autoFit)
            Toggle("Nano on minimize / close",isOn:$windows.nanoOnMinimize)
            Toggle("Show button hints",isOn:$hints.enabled)
            Text("Turn off for a distraction-free live set.").font(.stage(size:10)).foregroundStyle(.secondary)
            Divider()
            HStack { MarkerIcon(systemName:"speaker.wave.2"); Slider(value:$player.volume,in:0...1).tint(accent).accessibilityLabel("Volume") }
            Toggle("Shuffle",isOn:$player.shuffle)
            Toggle("Repeat Queue",isOn:$player.repeatAll)
            Picker("On Play",selection:$player.startMode) { Text("Restart").tag(StartMode.beginning);Text("Resume").tag(StartMode.resume) }
            Picker("At End",selection:$player.endMode) { Text("Next Track").tag(EndMode.next);Text("Stop").tag(EndMode.stop) }
            if player.endMode == .stop {
                Picker("Before End",selection:$player.stopBeforeEnd) { Text("0 s").tag(0.0);ForEach([1.0,2,3,5,10,15,30],id:\.self) { Text("\(Int($0)) s").tag($0) } }
            }
            Text("⌥⌘ Space — play/pause · ⌘L — lock").font(.stage(size:10)).foregroundStyle(.secondary)
            }.disabled(setup.settingsBlocked)
        }.disabled(lock.isLocked)
    }
    private func fadeTitle(_ mode:FadeMode)->String { mode == .none ? "Off" : "\(mode.title) · \(Int(mode.seconds)) s" }
    private var queue: some View {
        ScrollView {
            LazyVStack(spacing:3) {
                if player.tracks.isEmpty { Text("Drop your music here").font(.stage(size:12)).foregroundStyle(Color(stageHex:AppearancePreferences.shared.theme.text).opacity(0.65)).frame(maxWidth:.infinity).padding(.vertical,25) }
                ForEach(player.tracks) { track in
                    QueueTrackRow(player:player,track:track)
                }
            }.background(GeometryReader {proxy in Color.clear.preference(key:QueueFitHeightKey.self,value:proxy.size.height)})
        }.frame(height:windows.autoFit && !compact && !playlistOnly ? min(360,max(54,ui.queueContentHeight>0 ? ui.queueContentHeight:CGFloat(player.tracks.count)*55)):nil)
            .frame(minHeight:windows.autoFit && !compact && !playlistOnly ? 54:(compact ? 100:160),maxHeight:windows.autoFit && !compact && !playlistOnly ? nil:.infinity)
            .onPreferenceChange(QueueFitHeightKey.self) {height in if abs(ui.queueContentHeight-height)>0.5 {ui.queueContentHeight=height}}
    }
}
