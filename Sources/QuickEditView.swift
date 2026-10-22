import AppKit
import SwiftUI
import AVFoundation
import Combine
import UniformTypeIdentifiers

final class QuickEditModel:ObservableObject {
    let track:Track
    @Published var duration:Double=0
    @Published var sampleRate:Double=48000
    @Published var start:Double=0
    @Published var end:Double=0
    @Published var inText="0:00.000"
    @Published var outText="0:00.000"
    @Published var position:Double=0
    @Published var playing=false
    @Published var busy=false
    @Published var message="Reading audio…"
    @Published var viewport=TimelineViewport(duration:0)
    @Published var wavePeaks:[Double]=[]
    @Published var waveBusy=false
    @Published var waveHeight:Double=160
    @Published var auditioning=false
    @Published var clipSelection=EditorClipSelection()
    private var previewRanges:[ClipRange]=[]
    private var previewRangeIndex=0
    var exportRanges:[ClipRange] {clipSelection.ranges}
    var selectedDuration:Double {exportRanges.reduce(0){$0+$1.duration}}
    var selectionCount:Int {exportRanges.count}
    var hasSelection:Bool {!exportRanges.isEmpty}
    var hoverTime:Double?
    weak var timelineWindow:NSWindow?
    private var lastAuditionTarget:Double?
    private var previewGeneration=0
    var viewportKey:String {"\(viewport.start):\(viewport.length)"}
    var canEdit:Bool {!busy && !ControlLock.shared.isLocked && !SetupLock.shared.editsBlocked && duration>0}
    var canPreview:Bool {!busy && !ControlLock.shared.isLocked && !SetupLock.shared.playbackBlocked && !SetupLock.shared.editsBlocked && !mainIsPlaying() && duration>0}

    private let preview=AVPlayer()
    @Published var previewVolume:Double=0.8 {didSet {preview.volume=Float(previewVolume)}}
    private let mainIsPlaying:()->Bool
    private var clock:AnyCancellable?
    private var exportTask:Task<Void,Never>?
    var range:ClipRange {ClipRange(start:start,end:end)}
    init(_ track:Track,mainIsPlaying:@escaping ()->Bool = {Player.shared.playing}){self.track=track;self.mainIsPlaying=mainIsPlaying}
    func prepare() async {
        if duration>0 {startClock();return}
        do {
            let url=track.url;let info=try await Task.detached(priority:.utility) {try ClipExport.inspect(url)}.value
            duration=info.duration;sampleRate=info.sampleRate;viewport=TimelineViewport(duration:duration);end=duration;clipSelection=EditorClipSelection(clips:[EditorClip(range:.init(start:0,end:duration))]);updateText();message="\(Int(info.sampleRate)) Hz · \(info.channels) channels · WAV export"
            preview.replaceCurrentItem(with:AVPlayerItem(url:track.url));preview.volume=Float(previewVolume)
            startClock()

        } catch {message="Cannot edit this file: "+error.localizedDescription}
    }
    private func startClock(){guard clock == nil else {return};clock=Timer.publish(every:0.05,on:.main,in:.common).autoconnect().sink { [weak self] _ in self?.tickPreview() }}
    func updateText(){inText=ClipRange.preciseLabel(start);outText=ClipRange.preciseLabel(end)}
    func setStart(_ value:Double){guard value.isFinite,duration>0 else {return};start=min(max(0,value),max(0,end-1/sampleRate));updateText();stopPreview()}
    func setEnd(_ value:Double){guard value.isFinite,duration>0 else {return};end=max(min(duration,value),min(duration,start+1/sampleRate));updateText();stopPreview()}
    @discardableResult func commitText(preserveSelection:Bool=false)->Bool {
        guard let a=ClipRange.parse(inText),let b=ClipRange.parse(outText),b<=duration+0.00051 else {message="Enter a valid In / Out range, for example 0:15.250.";return false}
        let changed=inText != ClipRange.preciseLabel(start) || outText != ClipRange.preciseLabel(end)
        let resolvedStart=inText == ClipRange.preciseLabel(start) ? start:a
        let resolvedEnd=outText == ClipRange.preciseLabel(end) ? end:min(b,duration)
        guard ClipRange(start:resolvedStart,end:resolvedEnd).valid else {message="Out must be after In.";return false}
        start=resolvedStart;end=resolvedEnd;updateText();stopPreview();if !preserveSelection || changed {commitRegion(add:false)};return true
    }

    func seekPreview(_ value:Double){guard duration>0,value.isFinite else {return};position=min(duration,max(0,value));preview.seek(to:CMTime(seconds:position,preferredTimescale:48000),toleranceBefore:.zero,toleranceAfter:.zero)}
    func togglePreview(){
        guard canPreview else {return}
        if playing {stopPreview();return}
        previewRanges=hasSelection ? exportRanges:[range];previewRangeIndex=0
        startPreview(at:previewRanges[0].start,audition:false)
    }
    private func startPreview(at seconds:Double,audition:Bool) {
        guard canPreview,seconds.isFinite else {return}
        previewGeneration += 1;let generation=previewGeneration
        position=min(duration,max(0,seconds));auditioning=audition;playing=true;preview.volume=Float(previewVolume)
        preview.seek(to:CMTime(seconds:position,preferredTimescale:48000),toleranceBefore:audition ? CMTime(seconds:0.01,preferredTimescale:48000):.zero,toleranceAfter:audition ? CMTime(seconds:0.01,preferredTimescale:48000):.zero) { [weak self] completed in
            DispatchQueue.main.async {guard let self,completed,self.previewGeneration == generation,self.playing,self.canPreview else {return};if self.auditioning && !NSEvent.modifierFlags.contains(.option) {self.stopPreview();return};self.preview.play()}
        }
    }
    func hover(_ time:Double?){hoverTime=time;if time == nil && auditioning {stopPreview()}}
    func tickPreview(option suppliedOption:Bool?=nil,focused:Bool?=nil,active:Bool?=nil) {
        let option=suppliedOption ?? (NSEvent.modifierFlags.contains(.option) && !NSEvent.modifierFlags.contains(.command))
        if option,let target=hoverTime,focused ?? (timelineWindow?.isKeyWindow == true),active ?? NSApp.isActive,canPreview {
            if !auditioning || lastAuditionTarget.map({abs($0-target)>0.015}) ?? true {lastAuditionTarget=target;startPreview(at:target,audition:true)}
        } else if auditioning {stopPreview()}
        guard playing else {return}
        guard canPreview else {stopPreview();return}
        let seconds=preview.currentTime().seconds
        if seconds.isFinite {position=seconds}
        if preview.currentItem?.status == .failed {hoverTime=nil;stopPreview();return}
        if !auditioning,previewRangeIndex<previewRanges.count,seconds>=previewRanges[previewRangeIndex].end {
            previewRangeIndex += 1
            if previewRangeIndex<previewRanges.count {startPreview(at:previewRanges[previewRangeIndex].start,audition:false)}else {stopPreview()}
        } else if auditioning,seconds>=duration {hoverTime=nil;stopPreview()}
    }
    func stopPreview(){previewGeneration += 1;preview.pause();playing=false;auditioning=false;lastAuditionTarget=nil}
    func selectRegion(_ a:Double,_ b:Double){guard canEdit,a.isFinite,b.isFinite else {return};let first=max(0,min(a,b)),last=min(duration,max(a,b));guard last>first else {return};start=first;end=last;updateText();stopPreview()}
    func commitRegion(add:Bool) {
        guard canEdit,range.valid else {return}
        if clipSelection.clips.isEmpty {clipSelection.clips=[EditorClip(range:.init(start:0,end:duration))]}
        clipSelection.select(range,add:add)
    }
    func selectClip(at time:Double,add:Bool) {
        guard canEdit else {return}
        if let region=clipSelection.choose(at:time,add:add) {start=region.start;end=region.end;updateText()}
        stopPreview()
    }
    func splitAtCursor(){guard canEdit,position>0,position<duration else {return};clipSelection.cut(at:position);selectClip(at:position,add:false)}
    func selectWhole(){guard canEdit else {return};start=0;end=duration;updateText();clipSelection.select(range,add:false);stopPreview()}
    func clearSelection(){clipSelection.selected=[];stopPreview()}
    func nudgeCursor(_ delta:Double){seekPreview(position+delta)}
    func zoom(_ factor:Double,at fraction:Double=0.5){viewport.setZoom(viewport.zoom*factor,anchorFraction:fraction)}
    func fitSelection(){guard range.valid,duration>0 else {return};viewport.setZoom(duration/(range.duration*1.15));viewport.pan(start-range.duration*0.075)}
    @MainActor func loadWaveform() async {
        guard duration>0,viewport.length>0 else {return};let key=viewportKey;waveBusy=true
        let url=track.url,region=ClipRange(start:viewport.start,end:min(duration,viewport.start+viewport.length))
        let worker=Task.detached(priority:.utility) {try EditorWaveform.peaks(url:url,range:region)}
        do {let peaks=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});guard !Task.isCancelled,viewportKey == key else {return};wavePeaks=peaks;waveBusy=false}
        catch {guard viewportKey == key else {return};waveBusy=false;if !(error is CancellationError) {message=error.localizedDescription}}
    }
    func close(){stopPreview();clock?.cancel();clock=nil;exportTask?.cancel()}
    func save(replace:Bool){
        guard !busy,!SetupLock.shared.editsBlocked,!ControlLock.shared.isLocked,duration>0 else {return}
        guard commitText(preserveSelection:true),hasSelection else {return}
        if replace,Player.shared.playing,(Player.shared.currentID == track.id || Player.shared.outgoingTrack?.id == track.id) {message="Pause this track before replacing it. Save as Copy is available.";return}
        stopPreview()
        let panel=NSSavePanel();panel.title=replace ? "Save Edit & Replace in Playlist":"Save Edit as Copy";panel.allowedContentTypes=[.wav];panel.canCreateDirectories=true;panel.nameFieldStringValue=track.url.deletingPathExtension().lastPathComponent+" - Edit.wav"
        panel.message="Exports a separate WAV. The original audio file stays unchanged."
        guard panel.runModal() == .OK,let destination=panel.url,!ControlLock.shared.isLocked,!SetupLock.shared.editsBlocked else {return}
        let selection=exportRanges,source=track;busy=true;message="Exporting selected audio…"
        exportTask=Task { @MainActor [weak self] in
            let worker=Task.detached(priority:.utility) {try ClipExport.write(source:source.url,ranges:selection,to:destination)}
            do {
                try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                guard let self else {return};guard !Task.isCancelled else {self.busy=false;self.message="WAV saved; playlist unchanged.";return}
                _=try Player.shared.applyEditedClip(source,file:destination,replace:replace)
                self.message=replace ? "Saved · replaced in playlist. Undo restores the original.":"Saved · added as a separate track after the original."
                self.busy=false
            } catch {guard let self else {return};self.message=error is CancellationError ? "Export cancelled.":error.localizedDescription;self.busy=false}
        }
    }
    func cancelExport(){exportTask?.cancel()}
}

struct QuickEditView:View {
    @ObservedObject var edit:QuickEditModel
    var embedded=false
    @ObservedObject private var player=Player.shared
    @ObservedObject private var lock=ControlLock.shared
    @ObservedObject private var setup=SetupLock.shared
    private var protected:Bool {lock.isLocked || setup.editsBlocked}
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:12) {
            HStack {MarkerLabel("Quick Edit",systemImage:"scissors").font(.stage(.title2).bold());Spacer();Text("TRIM").font(.stage(.caption).bold()).foregroundStyle(accent)}
            Text(edit.track.title).font(.stage(.headline)).lineLimit(2)
            Text("Choose a fragment. Save a copy or replace this playlist item.").font(.stage(.callout)).foregroundStyle(.secondary)
            EditorTimeline(edit:edit).frame(height:edit.waveHeight).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:8))
            HStack(spacing:8) {
                Button {edit.zoom(0.5)} label:{MarkerIcon(systemName:"minus.magnifyingglass")}.accessibilityLabel("Zoom Out Audio")
                Text(String(format:"%.0f×",edit.viewport.zoom)).font(.stage(.caption,design:.monospaced)).frame(width:36)
                Button {edit.zoom(2)} label:{MarkerIcon(systemName:"plus.magnifyingglass")}.accessibilityLabel("Zoom In Audio")
                Button("Fit Selection") {edit.fitSelection()}
                Button("Fit All") {edit.viewport=TimelineViewport(duration:edit.duration)}
                Spacer()
                Text("Height").font(.stage(.caption))
                Slider(value:$edit.waveHeight,in:100...260).frame(width:80).accessibilityLabel("Audio Track Height")
                if edit.waveBusy {ProgressView().controlSize(.mini)}
            }.disabled(edit.busy || edit.duration<=0)
            if edit.viewport.zoom>1 {
                HStack {Text(ClipRange.label(edit.viewport.start)).font(.stage(.caption).monospacedDigit());Slider(value:Binding(get:{edit.viewport.start},set:{edit.viewport.pan($0)}),in:0...max(0.001,edit.duration-edit.viewport.length)).accessibilityLabel("Audio Timeline Scroll");Text(ClipRange.label(edit.viewport.start+edit.viewport.length)).font(.stage(.caption).monospacedDigit())}
            }
            HStack {Button("Split at Cursor") {edit.splitAtCursor()};Button("Clear Selection") {edit.clearSelection()};Spacer();Text("\(edit.selectionCount) selected · \(ClipRange.label(edit.selectedDuration))").font(.stage(.caption).monospacedDigit())}.disabled(protected || edit.busy || edit.duration<=0)
            Text("Drag to select · ⌘-drag adds a region · ⌘-click selects clips · Option-hover auditions · arrows move by one sample").font(.stage(.caption)).foregroundStyle(.secondary)
            HStack(spacing:14) {
                VStack(alignment:.leading){Text("IN").font(.stage(.caption).bold());TextField("In",text:$edit.inText).onSubmit {edit.commitText()}.accessibilityLabel("Clip In Time");Button("Mark In") {edit.setStart(edit.position);edit.commitRegion(add:false)}}
                VStack(alignment:.leading){Text("OUT").font(.stage(.caption).bold());TextField("Out",text:$edit.outText).onSubmit {edit.commitText()}.accessibilityLabel("Clip Out Time");Button("Mark Out") {edit.setEnd(edit.position);edit.commitRegion(add:false)}}
                VStack(alignment:.leading){Text("LENGTH").font(.stage(.caption).bold());Text(ClipRange.label(edit.selectedDuration)).font(.stage(.body,design:.monospaced));Button("Full Track") {edit.selectWhole()}}
            }.textFieldStyle(.roundedBorder).disabled(edit.busy || protected || edit.duration<=0)
            VStack {
                HStack {Text("In").frame(width:30,alignment:.leading);Slider(value:Binding(get:{edit.start},set:{edit.setStart($0)}),in:0...max(0.001,edit.duration),onEditingChanged:{if !$0 {edit.commitRegion(add:false)}}).accessibilityLabel("Clip In Point")}
                HStack {Text("Out").frame(width:30,alignment:.leading);Slider(value:Binding(get:{edit.end},set:{edit.setEnd($0)}),in:0...max(0.001,edit.duration),onEditingChanged:{if !$0 {edit.commitRegion(add:false)}}).accessibilityLabel("Clip Out Point")}
            }.disabled(edit.busy || protected || edit.duration<=0).tint(accent)
            HStack {
                Button {edit.togglePreview()} label: {MarkerLabel(edit.playing ? "Stop Preview":"Preview Selection",systemImage:edit.playing ? "stop.fill":"play.fill")}.disabled(protected || setup.playbackBlocked || player.playing || edit.duration<=0 || edit.busy)
                Slider(value:Binding(get:{edit.position},set:{edit.seekPreview($0)}),in:0...max(0.001,edit.duration)).accessibilityLabel("Edit Preview Position").disabled(protected || setup.playbackBlocked || edit.duration<=0 || edit.busy)
                Text(ClipRange.preciseLabel(edit.position)).font(.stage(.caption,design:.monospaced)).frame(width:100)
                MarkerIcon(systemName:"speaker.wave.1").font(.stage(.caption))
                Slider(value:$edit.previewVolume,in:0...1).frame(width:60).accessibilityLabel("Preview Volume")
            }
            if player.playing {Text("Main player is playing. Preview is available after pausing it.").font(.stage(.caption)).foregroundStyle(.secondary)}
            Spacer(minLength:0)
            Text(edit.message).font(.stage(.caption)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            if edit.busy {HStack {ProgressView().controlSize(.small);Button("Cancel Export"){edit.cancelExport()}}}
            HStack {
                Button(edit.selectionCount>1 ? "Join & Save Copy…":"Save as Copy…") {edit.save(replace:false)}.buttonStyle(.borderedProminent)
                Button(edit.selectionCount>1 ? "Join & Replace…":"Replace in Playlist…") {edit.save(replace:true)}.buttonStyle(.bordered)
                Spacer()
            }.disabled(edit.busy || protected || !edit.hasSelection)
            Text("Original file preserved · WAV 32-bit float · original sample rate & channels").font(.stage(.caption2)).foregroundStyle(.secondary)
        }.padding(22) }.frame(minWidth:620,minHeight:embedded ? 300:650).task {await edit.prepare()}
            .task(id:edit.viewportKey) {await edit.loadWaveform()}
            .onChange(of:lock.isLocked) {_,value in if value {edit.stopPreview()}}
            .onChange(of:setup.playbackBlocked) {_,value in if value {edit.stopPreview()}}
            .onChange(of:player.playing) {_,value in if value {edit.stopPreview()}}
            .onDisappear {if embedded || WorkspaceState.shared.section == .editor {edit.hover(nil);edit.stopPreview()}else {edit.close()}}
    }
}
