import SwiftUI

final class TrackRowEdit: ObservableObject {
    @Published var editing = false
    @Published var draft = ""
    @Published var hovering = false
}

struct QueueTrackRow: View {
    @ObservedObject var appearance = AppearancePreferences.shared
    @ObservedObject var player: Player
    let track: Track
    @ObservedObject private var setup = SetupLock.shared
    @ObservedObject private var lock = ControlLock.shared
    @StateObject private var row = TrackRowEdit()
    @FocusState private var nameFocused: Bool

    private func beginRename() {
        guard !setup.editsBlocked, !lock.isLocked else { return }
        row.draft = track.title; row.editing = true
    }
    private func finishRename(save: Bool) {
        guard row.editing else { return }
        row.editing = false; nameFocused = false
        if save { player.rename(track, to:row.draft) }
    }
    private func fadeTitle(_ mode: FadeMode) -> String {
        mode == .none ? "Off" : "\(mode.title) · \(Int(mode.seconds)) s"
    }
    var body: some View {
        HStack(spacing:10) {
            if row.editing {
                Text(player.queueNumber(track)).font(.custom(StageTypography.name,size:19)).frame(width:26)
                TextField("Track name",text:$row.draft)
                    .font(.stage(size:15 * AppearancePreferences.shared.theme.textScale,weight:.medium)).textFieldStyle(.plain)
                    .padding(.horizontal,5).padding(.vertical,5)
                    .background(accent.opacity(0.1),in:RoundedRectangle(cornerRadius:5))
                    .overlay(RoundedRectangle(cornerRadius:5).stroke(accent.opacity(0.65),lineWidth:1))
                    .focused($nameFocused).accessibilityLabel("Track Name")
                    .onSubmit { finishRename(save:true) }
                    .onExitCommand { finishRename(save:false) }
                    .task { nameFocused = true }
            } else {
                Button { player.selectInQueue(track) } label: {
                    HStack(spacing:10) {
                        Text(player.queueNumber(track)).font(.custom(StageTypography.name,size:19)).frame(width:26)
                        Text(track.title).font(.stage(size:15 * AppearancePreferences.shared.theme.textScale,weight:.medium)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength:0)
                    }.frame(minHeight:36).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(setup.selectionBlocked).stageHint("Select without playing · " + track.title).accessibilityLabel("Select Track: \(track.title)")
            }
            Button { player.playFromQueue(track) } label: {
                MarkerIcon(systemName:player.currentID == track.id && player.playing ? "pause.fill":"play.fill").font(.stage(size:12)).frame(width:26,height:28)
            }.buttonStyle(PlayerControlStyle(active:player.currentID == track.id && player.playing))
                .disabled(setup.selectionBlocked || setup.playbackBlocked).accessibilityLabel((player.currentID == track.id && player.playing ? "Pause Track: ":"Play Track: ") + track.title).mapAction("track:" + track.id)
            Button {
                if row.editing { finishRename(save:true) } else { beginRename() }
            } label: {
                MarkerIcon(systemName:row.editing ? "checkmark":"pencil").font(.stage(size:12)).frame(width:24,height:28)
            }.buttonStyle(.plain).foregroundStyle(accent)
                .disabled(setup.editsBlocked)
                .opacity(row.editing || row.hovering ? 1 : 0.65)
                .accessibilityLabel(row.editing ? "Save Track Name" : "Rename Track: \(track.title)")
            Button {AppDelegate.shared.showQuickEdit(track)} label: {MarkerIcon(systemName:"scissors").font(.stage(size:12)).frame(width:24,height:28)}.buttonStyle(.plain).foregroundStyle(accent).disabled(setup.editsBlocked).accessibilityLabel("Quick Edit: \(track.title)").stageHint("Trim audio · save a copy or replace this item",below:true)
            Menu {
                Button {AppDelegate.shared.showQuickEdit(track)} label: {MarkerLabel("Quick Edit…",systemImage:"scissors")}.disabled(setup.editsBlocked)
                Button { player.duplicate(track) } label: { MarkerLabel("Duplicate Track",systemImage:"doc.on.doc") }
                Button { beginRename() } label: { MarkerLabel("Rename Track",systemImage:"pencil") }
                Button("Use Filename") { player.rename(track,to:nil) }.disabled(track.customTitle == nil)
                Divider()
                Picker("Transition",selection:Binding(get:{player.fadeMode(after:track)},set:{player.setFadeMode($0,after:track)})) {
                    ForEach(FadeMode.allCases,id:\.self) { Text(fadeTitle($0)).tag($0) }
                }
                Divider(); Button { player.remove(track) } label: { MarkerLabel("Remove from Queue",systemImage:"trash") }
            } label: {
                HStack(spacing:3) { MarkerIcon(systemName:"waveform.path"); Text("\(Int(player.fadeMode(after:track).seconds))s").font(.stage(size:10,design:.monospaced)) }
            }.menuStyle(.borderlessButton).fixedSize().disabled(setup.editsBlocked)
                .accessibilityLabel("Fade: \(Int(player.fadeMode(after:track).seconds)) seconds").stageHint("Track transition",below:true)
            Button { player.remove(track) } label: { MarkerIcon(systemName:"trash").font(.stage(size:12)).frame(width:24,height:28) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7)).disabled(setup.editsBlocked)
                .opacity(row.editing ? 0 : (row.hovering ? 1 : 0.65)).allowsHitTesting(!row.editing)
                .accessibilityLabel("Remove from Queue: \(track.title)").stageHint("Remove from queue",below:true)
        }.frame(minHeight:36).padding(.horizontal,8).padding(.vertical,8)
            .background(track.id == player.stageLeft?.id ? accent.opacity(0.12):(track.id == player.stageRight?.id ? tapeB.opacity(0.1):.clear),in:RoundedRectangle(cornerRadius:6))
            .overlay(RoundedRectangle(cornerRadius:6).stroke(player.selectedID == track.id ? accent.opacity(0.65):.clear,lineWidth:1))
            .onHover { row.hovering = $0 }
            .onChange(of:nameFocused) { _, focused in if !focused { finishRename(save:true) } }
            .onChange(of:setup.editsBlocked) { _, blocked in if blocked { finishRename(save:false) } }
            .onChange(of:lock.isLocked) { _, locked in if locked { finishRename(save:false) } }
            .contextMenu {
                Button { player.play(track) } label: { MarkerLabel("Play",systemImage:"play.fill") }.disabled(setup.selectionBlocked || setup.playbackBlocked)
                Button {AppDelegate.shared.showQuickEdit(track)} label: {MarkerLabel("Quick Edit…",systemImage:"scissors")}.disabled(setup.editsBlocked)
                Button { player.duplicate(track) } label: { MarkerLabel("Duplicate Track",systemImage:"doc.on.doc") }.disabled(setup.editsBlocked)
                Divider()
                Button { beginRename() } label: { MarkerLabel("Rename Track",systemImage:"pencil") }.disabled(setup.editsBlocked)
                Button("Use Filename") { player.rename(track,to:nil) }.disabled(setup.editsBlocked || track.customTitle == nil)
                Divider()
                Button("Restart") { player.load(track,position:0) }.disabled(setup.selectionBlocked)
                Button("Resume") { player.play(track) }.disabled(setup.selectionBlocked)
                Divider(); Button { player.remove(track) } label: { MarkerLabel("Remove from Queue",systemImage:"trash") }.disabled(setup.editsBlocked)
            }
    }
}
