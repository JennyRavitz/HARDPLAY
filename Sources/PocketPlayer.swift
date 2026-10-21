import SwiftUI
import AppKit

/// A small companion player with its own silhouette, not a copy of a branded device.
final class PocketUIState: ObservableObject { @Published var drawerOpen = false }

struct PocketPlayerView: View {
    @StateObject private var ui = PocketUIState()
    @ObservedObject var placement = FloatingPlacement.shared
    @ObservedObject var player = Player.shared
    @ObservedObject var lock = ControlLock.shared
    @ObservedObject var setup = SetupLock.shared
    @ObservedObject var appearance = AppearancePreferences.shared
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:9) {
                Text("LOCKS").font(.system(size:8,weight:.heavy)).tracking(1).foregroundStyle(.white.opacity(0.6))
                Button { placement.pocketLocked.toggle() } label: {
                    lockRow("Position",state:placement.pocketLocked ? "Fixed in place":"Move freely",symbol:placement.pocketLocked ? "pin.fill":"arrow.up.and.down.and.arrow.left.and.right",locked:placement.pocketLocked)
                }.buttonStyle(.plain).accessibilityLabel(placement.pocketLocked ? "Position fixed. Unlock Widget Position":"Position unlocked. Lock Widget Position")
                VStack(alignment:.leading,spacing:5) {
                    lockRow("Controls",state:lock.isLocked ? "Locked":"Available",symbol:lock.isLocked ? "lock.fill":"lock.open",locked:lock.isLocked)
                    if lock.isLocked { PocketUnlockControl().frame(height:30) }
                    else { Button("Lock controls") { lock.lock() }.font(.system(size:10,weight:.semibold)).buttonStyle(.bordered).accessibilityLabel("Lock Widget Controls") }
                }
                Text(lock.isLocked ? "Music continues. Hold 1 sec to unlock.":"Play & skip are available.").font(.system(size:9)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal:false,vertical:true)
            }.padding(10).frame(width:148).background(Color(red:0.07,green:0.11,blue:0.17).opacity(0.98),in:RoundedRectangle(cornerRadius:12))
                .offset(x:ui.drawerOpen ? 0:152).opacity(ui.drawerOpen ? 1:0).allowsHitTesting(ui.drawerOpen).accessibilityHidden(!ui.drawerOpen)
                .frame(width:152,height:220).clipped().padding(.bottom,20)
            pocketBody
        }.frame(width:344)
    }
    private func lockRow(_ title:String,state:String,symbol:String,locked:Bool)->some View {
        HStack(spacing:7) {
            Image(systemName:symbol).font(.system(size:12)).frame(width:18)
            VStack(alignment:.leading,spacing:3) { Text(title).font(.system(size:11,weight:.semibold));Text(state).font(.system(size:9)).foregroundStyle(.white.opacity(0.7)) }
            Spacer(minLength:0)
            Circle().fill(locked ? Color(red:1,green:0.7,blue:0.4):accent).frame(width:5,height:5)
        }.foregroundStyle(.white).padding(6).background(.white.opacity(locked ? 0.1:0.035),in:RoundedRectangle(cornerRadius:7))
    }
    private var pocketBody: some View {
        VStack(spacing:10) {
            HStack {
                Text("HARD / PLAY").font(.system(size:8,weight:.heavy,design:.rounded)).tracking(1)
                Spacer()
                Button { AppDelegate.shared.showMain();AppDelegate.shared.pocketWindow.orderOut(nil) } label: { Image(systemName:"arrow.up.left.and.arrow.down.right").font(.system(size:10)) }.buttonStyle(.plain).accessibilityLabel("Restore Player")
            }.foregroundStyle(.white.opacity(0.7))
            VStack(alignment:.leading,spacing:6) {
                HStack { Circle().fill(player.playing ? accent : .gray).frame(width:5,height:5);Text(lock.isLocked ? "CONTROLS LOCKED":player.playing ? "PLAYING":"PAUSED").font(.system(size:7,weight:.bold,design:.monospaced));Spacer();Text(player.queueNumber(player.current)).font(.system(size:8,design:.monospaced)) }
                Text(player.current?.title ?? "Your music, ready").font(.system(size:11,weight:.semibold)).lineLimit(2).frame(maxWidth:.infinity,minHeight:28,alignment:.leading)
                HStack { Text(timeLabel(player.elapsed));Spacer();Text(timeLabel(player.duration)) }.font(.system(size:8,design:.monospaced))
                Text("\(placement.pocketLocked ? "POSITION FIXED":"MOVE FREELY") · \(lock.isLocked ? "BUTTONS LOCKED":"BUTTONS ON")").font(.system(size:6,weight:.medium,design:.monospaced)).foregroundStyle(accent.opacity(0.8))
                GeometryReader { g in Capsule().fill(accent.opacity(0.25)).overlay(alignment:.leading) { Capsule().fill(accent).frame(width:g.size.width*player.fraction) } }.frame(height:3)
            }.padding(10).foregroundStyle(accent).background(Color(red:0.035,green:0.07,blue:0.1),in:RoundedRectangle(cornerRadius:10))
            ZStack {
                Circle().fill(.white.opacity(0.07)).overlay(Circle().stroke(.white.opacity(0.14),lineWidth:1))
                VStack {
                    Button("OPEN") { AppDelegate.shared.showMain();AppDelegate.shared.pocketWindow.orderOut(nil) }.font(.system(size:7,weight:.heavy)).buttonStyle(.plain).accessibilityLabel("Open Main Player")
                    Spacer()
                    HStack {
                        Button { player.previous() } label: { Image(systemName:"backward.end.fill") }.disabled(setup.selectionBlocked)
                        Spacer()
                        Button { player.toggle() } label: { Image(systemName:player.playing ? "pause.fill":"play.fill").font(.system(size:18,weight:.bold)).frame(width:42,height:42).background(accent.opacity(0.2),in:Circle()) }.accessibilityLabel(player.playing ? "Pause":"Play").disabled(setup.playbackBlocked)
                        Spacer()
                        Button { player.next() } label: { Image(systemName:"forward.end.fill") }.disabled(setup.selectionBlocked)
                    }.buttonStyle(.plain).font(.system(size:11)).disabled(player.current == nil)
                    Spacer()
                    Text(lock.isLocked ? "LOCKED":"READY").font(.system(size:6,weight:.bold,design:.monospaced))
                }.padding(12)
            }.frame(width:116,height:116).foregroundStyle(.white).disabled(lock.isLocked)
        }.padding(14).frame(width:180).background(LinearGradient(colors:[Color(red:0.22,green:0.26,blue:0.32),Color(red:0.09,green:0.12,blue:0.17)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:25))
            .overlay(RoundedRectangle(cornerRadius:25).stroke(.white.opacity(0.25),lineWidth:1))
            .overlay(alignment:.topLeading) {
                Button { withAnimation(.easeInOut(duration:0.2)) { ui.drawerOpen.toggle() } } label: {
                    Color.clear.frame(width:16,height:126).contentShape(Rectangle())
                }.buttonStyle(.plain).offset(x:0,y:30).accessibilityLabel(ui.drawerOpen ? "Hide Widget Lock Panel":"Show Widget Lock Panel").help("Tap the left edge of the display to show or hide locks")
            }.padding(6)
    }
}
