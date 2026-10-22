import SwiftUI

final class TrackRowEdit:ObservableObject {
    @Published var editing=false
    @Published var draft=""
    @Published var hovering=false
    @Published var targeted=false
    @Published var dropAfter=false
    @Published var height:CGFloat=52
}
struct QueueTrackRow:View {
    @ObservedObject var appearance=AppearancePreferences.shared
    @ObservedObject var player:Player
    let track:Track
    @ObservedObject private var setup=SetupLock.shared
    @ObservedObject private var lock=ControlLock.shared
    @StateObject private var row=TrackRowEdit()
    @FocusState private var nameFocused:Bool
    private var index:Int {player.tracks.firstIndex(where:{$0.id==track.id}) ?? 0}
    private var editBlocked:Bool {setup.editsBlocked || lock.isLocked}
    private func beginRename() {guard !editBlocked else {return};row.draft=track.title;row.editing=true}
    private func finishRename(save:Bool) {guard row.editing else {return};row.editing=false;nameFocused=false;if save {player.rename(track,to:row.draft)}}
    @ViewBuilder private var actions:some View {
        Button("Edit Audio") {AppDelegate.shared.showQuickEdit(track)}.disabled(editBlocked)
        Button("Rename Track") {beginRename()}.disabled(editBlocked)
        Button("Use Filename") {player.rename(track,to:nil)}.disabled(editBlocked || track.customTitle == nil)
        Button("Duplicate Track") {player.duplicate(track)}.disabled(editBlocked)
        Divider()
        Button("Move Up") {player.moveTrack(track.id,by:-1)}.disabled(editBlocked || index==0)
        Button("Move Down") {player.moveTrack(track.id,by:1)}.disabled(editBlocked || index==player.tracks.count-1)
        Button("Move to Top") {player.moveTrack(track.id,to:0)}.disabled(editBlocked || index==0)
        Button("Move to Bottom") {player.moveTrack(track.id,to:player.tracks.count-1)}.disabled(editBlocked || index==player.tracks.count-1)
        Divider()
        Button("Remove from Queue",role:.destructive) {player.remove(track)}.disabled(editBlocked)
    }
    var body:some View {
        HStack(spacing:10) {
            Text("≡").font(.system(size:15,weight:.medium)).foregroundStyle(.secondary)
                .frame(width:14,height:30).contentShape(Rectangle())
                .onDrag {QueueDrag.provider(track.id)}.allowsHitTesting(!editBlocked && !row.editing)
                .accessibilityLabel("Reorder Track: "+track.title)
                .accessibilityAction(named:Text("Move Up")) {player.moveTrack(track.id,by:-1)}
                .accessibilityAction(named:Text("Move Down")) {player.moveTrack(track.id,by:1)}
                .stageHint("Drag to reorder · or right-click for Move Up / Down")
            Text(player.queueNumber(track)).font(.stage(size:16)).monospacedDigit().foregroundStyle(.secondary).frame(width:25)
            if row.editing {
                TextField("Track name",text:$row.draft).font(.stage(size:14*appearance.theme.textScale)).textFieldStyle(.plain)
                    .padding(5).background(accent.opacity(0.08),in:RoundedRectangle(cornerRadius:5))
                    .focused($nameFocused).accessibilityLabel("Track Name")
                    .onSubmit {finishRename(save:true)}.onExitCommand {finishRename(save:false)}.task {nameFocused=true}
                Button {finishRename(save:true)} label:{MarkerIcon(systemName:"checkmark").frame(width:28,height:30)}.buttonStyle(PlayerControlStyle()).accessibilityLabel("Save Track Name")
            }else {
                Button {player.selectInQueue(track)} label:{
                    Text(track.title).font(.stage(size:14*appearance.theme.textScale)).lineLimit(2).multilineTextAlignment(.leading)
                        .frame(maxWidth:.infinity,minHeight:34,alignment:.leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(setup.selectionBlocked).accessibilityLabel("Select Track: "+track.title).stageHint("Select without playing · "+track.title)
                Button {player.playFromQueue(track)} label:{MarkerIcon(systemName:player.currentID==track.id && player.playing ? "pause.fill":"play.fill",size:15).frame(width:28,height:30)}
                    .buttonStyle(PlayerControlStyle(active:player.currentID==track.id && player.playing)).disabled(setup.selectionBlocked || setup.playbackBlocked)
                    .accessibilityLabel((player.currentID==track.id && player.playing ? "Pause Track: ":"Play Track: ")+track.title).mapAction("track:"+track.id)
                Menu {
                    ForEach(FadeMode.allCases,id:\.self) {mode in
                        Button((player.fadeMode(after:track)==mode ? "✓ ":"")+(mode == .none ? "No Crossfade":"\(Int(mode.seconds)) Seconds")) {player.setFadeMode(mode,after:track)}
                    }
                } label:{Text(player.fadeMode(after:track) == .none ? "Off":"\(Int(player.fadeMode(after:track).seconds)) s").font(.system(size:11,weight:.medium,design:.monospaced)).frame(minWidth:34,minHeight:30)}
                    .menuStyle(.borderlessButton).fixedSize().disabled(editBlocked).accessibilityLabel("Fade: \(Int(player.fadeMode(after:track).seconds)) seconds").stageHint("Crossfade after this track")
                Menu {actions} label:{MarkerIcon(systemName:"slider.horizontal.3",size:15).frame(width:28,height:30)}
                    .menuStyle(.borderlessButton).fixedSize().disabled(editBlocked).accessibilityLabel("Track Actions: "+track.title).stageHint("Rename · edit audio · duplicate · reorder · remove")
            }
        }.frame(minHeight:36).padding(.horizontal,10).padding(.vertical,8)
            .background(player.currentID==track.id ? accent.opacity(0.065):.white.opacity(row.hovering ? 0.035:0),in:RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(player.selectedID==track.id ? accent.opacity(0.30):.clear,lineWidth:0.8))
            .overlay(alignment:row.dropAfter ? .bottom:.top) {if row.targeted {Rectangle().fill(accent.opacity(0.8)).frame(height:2).allowsHitTesting(false)}}
            .background(GeometryReader {proxy in Color.clear.onAppear {row.height=proxy.size.height}.onChange(of:proxy.size.height) {_,height in if abs(row.height-height)>0.5 {row.height=height}}})
            .onDrop(of:[QueueDrag.type.identifier],delegate:QueueRowDrop(player:player,target:track.id,targeted:$row.targeted,after:$row.dropAfter,midpoint:row.height/2))
            .onHover {row.hovering=$0}
            .onChange(of:nameFocused) {_,focused in if !focused {finishRename(save:true)}}
            .onChange(of:setup.editsBlocked) {_,blocked in if blocked {finishRename(save:false);row.targeted=false}}
            .onChange(of:lock.isLocked) {_,locked in if locked {finishRename(save:false);row.targeted=false}}
            .contextMenu {
                Button("Play") {player.play(track)}.disabled(setup.selectionBlocked || setup.playbackBlocked)
                Divider();actions
            }.disabled(lock.isLocked)
    }
}
