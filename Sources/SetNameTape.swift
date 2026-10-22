import AppKit
import SwiftUI

final class SetNameEdit:ObservableObject { @Published var editing=false;@Published var draft="" }
struct SetNameTape:View {
    @ObservedObject var player:Player
    var maxWidth:CGFloat=280
    var onOpen:(()->Void)?=nil
    @ObservedObject private var setup=SetupLock.shared
    @ObservedObject private var lock=ControlLock.shared
    @ObservedObject private var appearance=AppearancePreferences.shared
    @StateObject private var edit=SetNameEdit()
    @FocusState private var focused:Bool
    private var width:CGFloat {
        let name=edit.editing ? edit.draft:player.playlistName
        let font=StageTypography.native(14)
        return min(maxWidth,max(88,(name as NSString).size(withAttributes:[.font:font]).width+(onOpen == nil ? 30:54)))
    }
    private func begin(){guard !setup.editsBlocked,!lock.isLocked else {return};edit.draft=player.playlistName;edit.editing=true;focused=true}
    private func finish(_ save:Bool){guard edit.editing else{return};edit.editing=false;focused=false;if save {player.renameSet(to:edit.draft)}}
    var body:some View {
        Group {
            if edit.editing {
                TextField("Set name",text:$edit.draft).textFieldStyle(.plain).focused($focused).onSubmit {finish(true)}.onExitCommand {finish(false)}.accessibilityLabel("Set Name")
            } else {
                HStack(alignment:.center,spacing:8) {Text(player.playlistName).fixedSize(horizontal:false,vertical:true).multilineTextAlignment(.leading);if onOpen != nil {MarkerIcon(systemName:"chevron.down").font(.stage(size:9,weight:.bold))}}
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .gesture(TapGesture(count:2).onEnded {begin()}.exclusively(before:TapGesture().onEnded {onOpen?()}))
                    .contextMenu {
                        Button("Rename Set"){begin()}.disabled(setup.editsBlocked || lock.isLocked)
                        Button("New Playlist…"){player.requestNewPlaylist()}.disabled(setup.editsBlocked || lock.isLocked)
                        Button("Delete Playlist…",role:.destructive){player.requestDeletePlaylist()}.disabled(!player.canDeletePlaylist || setup.editsBlocked || lock.isLocked)
                    }
                    .accessibilityLabel("Playlist: \(player.playlistName)").accessibilityAddTraits(.isButton)
                    .accessibilityAction {onOpen?()}.accessibilityAction(named:Text("Rename Set")){begin()}
            }
        }.font(.custom(StageTypography.name,size:14)).foregroundStyle(tapeInk)
            .padding(.horizontal,12).padding(.vertical,7).frame(width:width,alignment:.leading).background(TapeSurface())
            .onChange(of:focused) {_,value in if !value {finish(true)}}
            .onChange(of:setup.editsBlocked) {_,value in if value {finish(false)}}
            .onChange(of:lock.isLocked) {_,value in if value {finish(false)}}
            .stageHint("Double-click to rename · Enter to save · Esc to cancel").accessibilityHint("Double-click to rename · Enter to save · Esc to cancel")
    }
}
