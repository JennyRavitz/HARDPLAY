import SwiftUI

/// Pointer inspection is read-only; only the slider's editing callback seeks.
final class SeekHoverState: ObservableObject { @Published var x: CGFloat? }

struct SeekPositionSlider: View {
    @ObservedObject var appearance = AppearancePreferences.shared
    @Binding var value: Double
    let duration: Double
    var onEditingChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var enabled
    @StateObject private var hover = SeekHoverState()
    private var validDuration: Bool { duration.isFinite && duration > 0 }
    var body: some View {
        GeometryReader { geometry in
            Slider(value:$value,in:0...max(validDuration ? duration:0,1),onEditingChanged:onEditingChanged)
                .controlSize(.mini).tint(accent).accessibilityLabel("Playback Position")
                .overlay(alignment:.topLeading) {
                    if enabled,validDuration,let x=hover.x {
                        let fraction=min(1,max(0,(x-6)/max(1,geometry.size.width-12)))
                        Text(timeLabel(Double(fraction)*duration))
                            .font(.stage(size:11,weight:.semibold,design:.monospaced)).foregroundStyle(.white)
                            .padding(.horizontal,8).padding(.vertical,5)
                            .background(Color(red:0.08,green:0.14,blue:0.22).opacity(0.98),in:RoundedRectangle(cornerRadius:6))
                            .overlay(RoundedRectangle(cornerRadius:6).stroke(accent.opacity(0.5),lineWidth:1))
                            .fixedSize().position(x:min(max(32,x),max(32,geometry.size.width-32)),y:-13)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hover.x=point.x
                    case .ended: hover.x=nil
                    }
                }
                .onChange(of:enabled) { _,active in if !active { hover.x=nil } }
        }.frame(height:16)
    }
}
