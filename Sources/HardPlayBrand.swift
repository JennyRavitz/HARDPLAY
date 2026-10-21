import AppKit
import SwiftUI

/// Shared front-facing artwork; the transport keeps its real Play/Pause action.
enum HardPlayBrand {
    static let artwork = Bundle.main.url(forResource:"HardPlayBeams",withExtension:"png").flatMap { NSImage(contentsOf:$0) }
}
struct HardPlayArtwork: View {
    var body: some View {
        if let artwork = HardPlayBrand.artwork {
            Image(nsImage:artwork).resizable().interpolation(.high).aspectRatio(contentMode:.fit).accessibilityHidden(true)
        } else {
            VStack(spacing:0) { Text("Hard"); Text("Play") }.font(.stage(size:15,weight:.black)).foregroundStyle(.white)
                .frame(maxWidth:.infinity,maxHeight:.infinity).background(accent,in:RoundedRectangle(cornerRadius:10))
        }
    }
}
struct HardPlayTransport: View {
    @ObservedObject var appearance = AppearancePreferences.shared
    let playing: Bool
    let compact: Bool
    var body: some View {
        let size = AppearancePreferences.shared.theme.buttonSize
        MarkerIcon(systemName:playing ? "pause.fill":"play.fill",size:size*0.42)
            .font(.stage(size:size * 0.4,weight:.bold)).foregroundStyle(Color(stageHex:AppearancePreferences.shared.theme.text))
            .offset(x:playing ? 0:1)
            .frame(width:size,height:size)
            .background(accent.opacity(0.22),in:Circle())
            .overlay(Circle().stroke(accent.opacity(0.9),lineWidth:1))
            .accessibilityHidden(true)
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
