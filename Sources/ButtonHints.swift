import SwiftUI

final class HintPreferences: ObservableObject {
    static let shared = HintPreferences()
    @Published var enabled = UserDefaults.standard.bool(forKey:"showButtonHints") {
        didSet { UserDefaults.standard.set(enabled,forKey:"showButtonHints") }
    }
}
final class HintHover: ObservableObject { @Published var inside = false }
struct StageHint: ViewModifier {
    @ObservedObject var preferences = HintPreferences.shared
    @StateObject private var hover = HintHover()
    var text: String
    var below = false
    func body(content: Content) -> some View {
        content.onHover { hover.inside = $0 }
            .overlay(alignment:below ? .bottomTrailing : .top) {
                if preferences.enabled && hover.inside && !ControlLock.shared.isLocked {
                    Text(text).font(.system(size:11,weight:.medium)).foregroundStyle(.white)
                        .padding(.horizontal,10).padding(.vertical,8)
                        .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:10))
                        .overlay(RoundedRectangle(cornerRadius:10).stroke(.white.opacity(0.22),lineWidth:1))
                        .fixedSize().offset(y:below ? 40 : -40).allowsHitTesting(false)
                }
            }.zIndex(preferences.enabled && hover.inside ? 100 : 0)
    }
}
extension View {
    func stageHint(_ text:String,below:Bool=false)->some View { modifier(StageHint(text:text,below:below)) }
}
