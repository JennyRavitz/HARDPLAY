import AppKit
import SwiftUI

/// Shared front-facing artwork; the transport keeps its real Play/Pause action.
enum HardPlayBrand {
    static let keycap = Bundle.main.url(forResource:"RedKeycap",withExtension:"png").flatMap { NSImage(contentsOf:$0) }
    static let artwork = Bundle.main.url(forResource:"HardPlayButton",withExtension:"png").flatMap { NSImage(contentsOf:$0) }
}
struct HardPlayArtwork: View {
    var body: some View {
        if let artwork = HardPlayBrand.artwork {
            Image(nsImage:artwork).resizable().interpolation(.high).aspectRatio(contentMode:.fit).accessibilityHidden(true)
        } else {
            VStack(spacing:0) { Text("Hard"); Text("Play") }.font(.system(size:15,weight:.black)).foregroundStyle(.white)
                .frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.red,in:RoundedRectangle(cornerRadius:10))
        }
    }
}
struct HardPlayTransport: View {
    let playing: Bool
    let compact: Bool
    var body: some View {
        ZStack {
            if let keycap=HardPlayBrand.keycap {
                Image(nsImage:keycap).resizable().interpolation(.high).aspectRatio(contentMode:.fit)
            } else { RoundedRectangle(cornerRadius:14).fill(Color.red.gradient) }
            Image(systemName:playing ? "pause.fill":"play.fill")
                .font(.system(size:compact ? 29:32,weight:.bold)).foregroundStyle(Color(red:1,green:0.96,blue:0.94))
                .shadow(color:.black.opacity(0.7),radius:1,x:0,y:2).offset(x:playing ? 0:2)
        }.frame(width:compact ? 84:90,height:compact ? 84:90).accessibilityHidden(true)
            .shadow(color:.red.opacity(playing ? 0.3:0.08),radius:playing ? 7:2)
    }
}
struct HardPlayPressStyle: ButtonStyle {
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.contentShape(RoundedRectangle(cornerRadius:16))
            .scaleEffect(configuration.isPressed ? 0.95:1)
            .brightness(configuration.isPressed ? -0.08:0)
            .animation(.easeOut(duration:0.1),value:configuration.isPressed)
    }
}
