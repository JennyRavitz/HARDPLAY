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
        let font=NSFont(name:"MarkerFelt-Wide",size:14) ?? .systemFont(ofSize:14,weight:.bold)
        return min(maxWidth,max(72,(name as NSString).size(withAttributes:[.font:font]).width+34))
    }
    private func begin(){guard !setup.editsBlocked,!lock.isLocked else {return};edit.draft=player.playlistName;edit.editing=true;focused=true}
    private func finish(_ save:Bool){guard edit.editing else{return};edit.editing=false;focused=false;if save {player.renameSet(to:edit.draft)}}
    var body:some View {
        Group {
            if edit.editing {
                TextField("Set name",text:$edit.draft).textFieldStyle(.plain).focused($focused).onSubmit {finish(true)}.onExitCommand {finish(false)}.accessibilityLabel("Set Name")
            } else {
                HStack(spacing:5) {Text(player.playlistName).lineLimit(1);if onOpen != nil {Image(systemName:"chevron.down").font(.system(size:9,weight:.bold))}}
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .gesture(TapGesture(count:2).onEnded {begin()}.exclusively(before:TapGesture().onEnded {onOpen?()}))
                    .contextMenu {Button("Rename Set"){begin()}.disabled(setup.editsBlocked || lock.isLocked)}
                    .accessibilityLabel("Playlist: \(player.playlistName)").accessibilityAddTraits(.isButton)
                    .accessibilityAction {onOpen?()}.accessibilityAction(named:Text("Rename Set")){begin()}
            }
        }.font(.custom("MarkerFelt-Wide",size:14)).foregroundStyle(Color(red:0.07,green:0.13,blue:0.22))
            .padding(.horizontal,12).padding(.vertical,7).frame(width:width).background(tapeB,in:TapeEdge())
            .onChange(of:focused) {_,value in if !value {finish(true)}}
            .onChange(of:setup.editsBlocked) {_,value in if value {finish(false)}}
            .onChange(of:lock.isLocked) {_,value in if value {finish(false)}}
            .help("Double-click to rename · Enter to save · Esc to cancel")
    }
}
