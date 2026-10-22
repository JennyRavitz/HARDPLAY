import SwiftUI
import AppKit

/// A small companion player with its own silhouette, not a copy of a branded device.
final class PocketUIState: ObservableObject { @Published var drawerOpen = false;@Published var scrub:Double=0;@Published var scrubbing=false }

struct PocketPlayerView: View {
    @StateObject private var ui = PocketUIState()
    @ObservedObject var placement = FloatingPlacement.shared
    @ObservedObject var player = Player.shared
    @ObservedObject var lock = ControlLock.shared
    @ObservedObject var setup = SetupLock.shared
    @ObservedObject var appearance = AppearancePreferences.shared
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing:0) {
                lockPanel
                    .offset(x:ui.drawerOpen ? 0:152).opacity(ui.drawerOpen && !placement.pocketNearLeftEdge ? 1:0).allowsHitTesting(ui.drawerOpen && !placement.pocketNearLeftEdge).accessibilityHidden(!ui.drawerOpen || placement.pocketNearLeftEdge)
                    .frame(width:152,height:220).clipped().padding(.bottom,20)
                pocketBody(width:max(180,geometry.size.width-164),height:max(308,geometry.size.height-12))
            }.frame(width:geometry.size.width,height:geometry.size.height)
        }.frame(minWidth:344,minHeight:320).audioFileDrop()
        .onChange(of:lock.isLocked) {_,value in if value {ui.scrubbing=false}}
        .onChange(of:setup.playbackBlocked) {_,value in if value {ui.scrubbing=false}}
        .onChange(of:player.currentID) {_,_ in ui.scrubbing=false}
    }
    private var lockPanel: some View {
            VStack(alignment:.leading,spacing:9) {
                Text("LOCKS").font(.stage(size:8,weight:.heavy)).tracking(1).foregroundStyle(.white.opacity(0.6))
                Button { placement.pocketLocked.toggle() } label: {
                    lockRow("Position",state:placement.pocketLocked ? "Fixed in place":"Move freely",symbol:placement.pocketLocked ? "pin.fill":"arrow.up.and.down.and.arrow.left.and.right",locked:placement.pocketLocked)
                }.buttonStyle(.plain).accessibilityLabel(placement.pocketLocked ? "Position fixed. Unlock Widget Position":"Position unlocked. Lock Widget Position")
                VStack(alignment:.leading,spacing:5) {
                    lockRow("Controls",state:lock.isLocked ? "Locked":"Available",symbol:lock.isLocked ? "lock.fill":"lock.open",locked:lock.isLocked)
                    if lock.isLocked { PocketUnlockControl().frame(height:30) }
                    else { Button("Lock controls") { lock.lock() }.font(.stage(size:10,weight:.semibold)).buttonStyle(.bordered).accessibilityLabel("Lock Widget Controls") }
                }
                Text(lock.isLocked ? "Music continues. Hold 3 sec to unlock.":"Play & skip are available.").font(.stage(size:9)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal:false,vertical:true)
            }.padding(10).frame(width:148).background(Color(red:0.07,green:0.11,blue:0.17).opacity(0.98),in:RoundedRectangle(cornerRadius:12))
    }
    private func lockRow(_ title:String,state:String,symbol:String,locked:Bool)->some View {
        HStack(spacing:7) {
            MarkerIcon(systemName:symbol).font(.stage(size:12)).frame(width:18)
            VStack(alignment:.leading,spacing:3) { Text(title).font(.stage(size:11,weight:.semibold));Text(state).font(.stage(size:9)).foregroundStyle(.white.opacity(0.7)) }
            Spacer(minLength:0)
            Circle().fill(locked ? Color(red:1,green:0.7,blue:0.4):accent).frame(width:5,height:5)
        }.foregroundStyle(.white).padding(6).background(.white.opacity(locked ? 0.1:0.035),in:RoundedRectangle(cornerRadius:7))
    }
    private func pocketBody(width:CGFloat,height:CGFloat)->some View {
        let scale=min(1.6,width/180)
        let wheel=min(200,max(96,min(width-64,height-190*scale)))
        return VStack(spacing:10) {
            HStack {
                PocketDragHandle().frame(width:116,height:18).help(placement.pocketLocked ? "Position fixed · unlock in the side panel":"Drag here to move the player anywhere")
                Spacer()
                Button { AppDelegate.shared.showMain();AppDelegate.shared.pocketWindow.orderOut(nil) } label: { MarkerIcon(systemName:"arrow.up.left.and.arrow.down.right").font(.stage(size:10)) }.buttonStyle(.plain).accessibilityLabel("Restore Player")
            }.foregroundStyle(.white.opacity(0.7))
            VStack(alignment:.leading,spacing:6) {
                HStack { Circle().fill(player.playing ? accent : .gray).frame(width:5,height:5);Text(lock.isLocked ? "CONTROLS LOCKED":player.playing ? "PLAYING":"PAUSED").font(.stage(size:7,weight:.bold,design:.monospaced));Spacer();Text(player.queueNumber(player.current)).font(.stage(size:8,design:.monospaced)) }
                Text(player.current?.title ?? "Your music, ready").font(.stage(size:11*scale,weight:.semibold)).lineLimit(2).frame(maxWidth:.infinity,minHeight:28*scale,alignment:.leading)
                HStack { Text(timeLabel(ui.scrubbing ? ui.scrub:player.elapsed));Spacer();Text(timeLabel(player.duration)) }.font(.stage(size:8*scale,design:.monospaced))
                Text("\(placement.pocketLocked ? "POSITION FIXED":"MOVE FREELY") · \(lock.isLocked ? "BUTTONS LOCKED":"BUTTONS ON")").font(.stage(size:6,weight:.medium,design:.monospaced)).foregroundStyle(accent.opacity(0.8))
                SeekPositionSlider(value:Binding(get:{ui.scrubbing ? ui.scrub:player.elapsed},set:{value in ui.scrub=value}),duration:player.duration) {editing in
                    if editing {ui.scrub=player.elapsed;ui.scrubbing=true}
                    else {let target=ui.scrub;ui.scrubbing=false;if !lock.isLocked,!setup.playbackBlocked {player.seek(target)}}
                }.disabled(lock.isLocked || setup.playbackBlocked || player.current == nil || player.duration<=0)
                .accessibilityLabel("Pocket Playback Position")
            }.padding(10).foregroundStyle(accent).background(Color(red:0.035,green:0.07,blue:0.1),in:RoundedRectangle(cornerRadius:10))
            Spacer(minLength:0)
            ZStack {
                Circle().fill(.white.opacity(0.07)).overlay(Circle().stroke(.white.opacity(0.14),lineWidth:1))
                VStack {
                    Button("OPEN") { AppDelegate.shared.showMain();AppDelegate.shared.pocketWindow.orderOut(nil) }.font(.stage(size:7,weight:.heavy)).buttonStyle(.plain).accessibilityLabel("Open Main Player")
                    Spacer()
                    HStack {
                        Button { player.previous() } label: { MarkerIcon(systemName:"backward.end.fill") }.disabled(setup.selectionBlocked)
                        Spacer()
                        Button { player.toggle() } label: { MarkerIcon(systemName:player.playing ? "pause.fill":"play.fill").font(.stage(size:18,weight:.bold)).frame(width:42,height:42).background(accent.opacity(0.2),in:Circle()) }.accessibilityLabel(player.playing ? "Pause":"Play").disabled(setup.playbackBlocked)
                        Spacer()
                        Button { player.next() } label: { MarkerIcon(systemName:"forward.end.fill") }.disabled(setup.selectionBlocked)
                    }.buttonStyle(.plain).font(.stage(size:11)).disabled(player.current == nil)
                    Spacer()
                    Text(lock.isLocked ? "LOCKED":"READY").font(.stage(size:6,weight:.bold,design:.monospaced))
                }.padding(12)
            }.frame(width:wheel,height:wheel).foregroundStyle(.white).disabled(lock.isLocked)
            .overlay {if lock.isLocked {NativeUnlockControl().frame(width:148,height:148).background(.ultraThinMaterial,in:Circle()).accessibilityLabel("Unlock Pocket Controls")}}
            Spacer(minLength:0)
        }.padding(14).frame(width:width,height:height).background(LinearGradient(colors:[Color(red:0.22,green:0.26,blue:0.32),Color(red:0.09,green:0.12,blue:0.17)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:25))
            .overlay(RoundedRectangle(cornerRadius:25).stroke(.white.opacity(0.25),lineWidth:1))
            .overlay(alignment:.topLeading) {
                if ui.drawerOpen && placement.pocketNearLeftEdge { lockPanel.offset(x:20,y:32) }
            }
            .overlay(alignment:.topLeading) {
                Button { withAnimation(.easeInOut(duration:0.2)) { ui.drawerOpen.toggle() } } label: {
                    Color.clear.frame(width:16,height:126).contentShape(Rectangle())
                }.buttonStyle(.plain).offset(x:0,y:30).accessibilityLabel(ui.drawerOpen ? "Hide Widget Lock Panel":"Show Widget Lock Panel").help("Tap the left edge of the display to show or hide locks")
            }
            .overlay(alignment:.bottomTrailing) { PocketResizeHandle().frame(width:22,height:22).padding(5).help(placement.pocketLocked ? "Unlock position to resize":"Drag to resize the pocket player") }
            .padding(6)
    }
}
