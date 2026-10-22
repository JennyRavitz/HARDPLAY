import SwiftUI

/// Global performance modes; row menus continue to override individual transitions.
struct QueuePolicyControls: View {
    @ObservedObject var player: Player
    @ObservedObject private var setup = SetupLock.shared
    var body: some View {
        HStack(spacing:8) {
            modeButton("Next Track",hint:"Play → next track",active:player.endMode == .next,first:"play.fill",second:"forward.end.fill") { player.endMode = .next }
            modeButton("Auto Stop",hint:"Play → stop at track end",active:player.endMode == .stop,first:"play.fill",second:"pause.fill") { player.endMode = .stop }
            Divider().frame(height:18)
            modeButton("Restart on Play",hint:"Start selected track from the beginning",active:player.startMode == .beginning,first:"play.fill",second:"arrow.counterclockwise") { player.startMode = .beginning }
            modeButton("Resume on Play",hint:"Start selected track from its saved position",active:player.startMode == .resume,first:"play.fill",second:"arrow.uturn.backward") { player.startMode = .resume }
            Spacer(minLength:2)
            Text("ALL").font(.stage(size:8,weight:.semibold)).foregroundStyle(.secondary)
            ForEach(FadeMode.allCases,id:\.self) { mode in
                Button { player.setFadeModeForAll(mode) } label: {
                    Text(mode == .none ? "0":"\(Int(mode.seconds))s").font(.stage(size:10,weight:.semibold,design:.monospaced)).frame(width:29,height:28)
                }.buttonStyle(PlayerControlStyle(active:player.uniformFadeMode == mode))
                    .accessibilityLabel(mode == .none ? "All Fades Off":"All Fades \(Int(mode.seconds)) Seconds")
                    .stageHint(mode == .none ? "All tracks · no crossfade":"All tracks · \(Int(mode.seconds)) s crossfade",below:true)
                    .disabled(player.tracks.isEmpty)
            }
        }.disabled(setup.editsBlocked)
    }
    private func modeButton(_ title:String,hint:String,active:Bool,first:String,second:String,action:@escaping ()->Void)->some View {
        Button(action:action) { HStack(spacing:3) { MarkerIcon(systemName:first); MarkerIcon(systemName:second) }.font(.stage(size:10)).frame(width:34,height:28) }
            .buttonStyle(PlayerControlStyle(active:active)).accessibilityLabel(title).stageHint(hint,below:true)
    }
}
