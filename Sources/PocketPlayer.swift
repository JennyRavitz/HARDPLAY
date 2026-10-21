import SwiftUI
import AppKit

/// A small companion player with its own silhouette, not a copy of a branded device.
struct PocketPlayerView: View {
    @ObservedObject var player = Player.shared
    @ObservedObject var lock = ControlLock.shared
    @ObservedObject var setup = SetupLock.shared
    @ObservedObject var appearance = AppearancePreferences.shared
    var body: some View {
        VStack(spacing:10) {
            HStack {
                Text("HARD / PLAY").font(.system(size:8,weight:.heavy,design:.rounded)).tracking(1)
                Spacer()
                Button { AppDelegate.shared.showMain();AppDelegate.shared.pocketWindow.orderOut(nil) } label: { Image(systemName:"arrow.up.left.and.arrow.down.right").font(.system(size:10)) }.buttonStyle(.plain).accessibilityLabel("Restore Player")
            }.foregroundStyle(.white.opacity(0.7))
            VStack(alignment:.leading,spacing:6) {
                HStack { Circle().fill(player.playing ? accent : .gray).frame(width:5,height:5);Text(player.playing ? "PLAYING":"PAUSED").font(.system(size:7,weight:.bold,design:.monospaced));Spacer();Text(player.queueNumber(player.current)).font(.system(size:8,design:.monospaced)) }
                Text(player.current?.title ?? "Your music, ready").font(.system(size:11,weight:.semibold)).lineLimit(2).frame(maxWidth:.infinity,minHeight:28,alignment:.leading)
                HStack { Text(timeLabel(player.elapsed));Spacer();Text(timeLabel(player.duration)) }.font(.system(size:8,design:.monospaced))
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
                    Image(systemName:lock.isLocked ? "lock.fill":"waveform").font(.system(size:8))
                }.padding(12)
            }.frame(width:116,height:116).foregroundStyle(.white).disabled(lock.isLocked)
        }.padding(14).frame(width:180).background(LinearGradient(colors:[Color(red:0.22,green:0.26,blue:0.32),Color(red:0.09,green:0.12,blue:0.17)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:25))
            .overlay(RoundedRectangle(cornerRadius:25).stroke(.white.opacity(0.25),lineWidth:1)).padding(6)
    }
}
