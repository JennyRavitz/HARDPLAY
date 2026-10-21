import SwiftUI

final class HintPreferences: ObservableObject {
    static let shared = HintPreferences()
    @Published var enabled = UserDefaults.standard.bool(forKey:"showButtonHints") {
        didSet { UserDefaults.standard.set(enabled,forKey:"showButtonHints") }
    }
}
final class HintChannel:ObservableObject {
    @Published private(set) var text:String?
    private var owner:UUID?
    func show(_ text:String,owner:UUID){self.owner=owner;self.text=text}
    func hide(owner:UUID){guard self.owner == owner else {return};clear()}
    func clear(){owner=nil;text=nil}
}
private struct HintChannelKey:EnvironmentKey {static let defaultValue:HintChannel?=nil}
extension EnvironmentValues {var stageHintChannel:HintChannel? {get {self[HintChannelKey.self]}set {self[HintChannelKey.self]=newValue}}}
final class HintHover:ObservableObject {let id=UUID();var inside=false}
struct StageHint: ViewModifier {
    @ObservedObject var preferences = HintPreferences.shared
    @Environment(\.stageHintChannel) private var channel
    @StateObject private var hover = HintHover()
    var text:String
    func body(content:Content)->some View {
        content.onHover {inside in
            hover.inside=inside
            if inside && preferences.enabled && !ControlLock.shared.isLocked {channel?.show(text,owner:hover.id)}else {channel?.hide(owner:hover.id)}
        }.onChange(of:text) {_,value in if hover.inside && preferences.enabled && !ControlLock.shared.isLocked {channel?.show(value,owner:hover.id)}}
            .onDisappear {channel?.hide(owner:hover.id)}
    }
}
private struct HintBar:View {
    @ObservedObject var channel:HintChannel
    @ObservedObject private var lock=ControlLock.shared
    var body:some View {
        HStack(spacing:10) {
            Text("HINT").font(.system(size:9,weight:.bold,design:.monospaced)).tracking(1).foregroundStyle(Color(red:0.65,green:0.82,blue:1))
            Text(lock.isLocked ? "Controls locked" : (channel.text ?? "Hover over a control to see its function."))
                .font(.system(size:11,weight:.medium)).foregroundStyle(.white.opacity(channel.text == nil ? 0.62:0.95)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
        }.padding(.horizontal,12).frame(height:44)
            .background(Color(red:0.035,green:0.07,blue:0.13).opacity(0.65),in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).stroke(.white.opacity(0.1),lineWidth:1))
            .padding(.horizontal,14).padding(.top,8).padding(.bottom,2)
            .allowsHitTesting(false).accessibilityElement(children:.combine).accessibilityLabel("Control hint").accessibilityValue(lock.isLocked ? "Controls locked" : (channel.text ?? "Hover over a control to see its function."))
    }
}
private struct HintScope:ViewModifier {
    @StateObject private var channel=HintChannel()
    @ObservedObject private var preferences=HintPreferences.shared
    @ObservedObject private var lock=ControlLock.shared
    func body(content:Content)->some View {
        VStack(spacing:0) {if preferences.enabled {HintBar(channel:channel)};content.environment(\.stageHintChannel,channel)}
            .onChange(of:preferences.enabled) {_,_ in channel.clear()}
            .onChange(of:lock.isLocked) {_,_ in channel.clear()}
    }
}
extension View {
    func stageHint(_ text:String,below:Bool=false)->some View {modifier(StageHint(text:text))}
    func fixedControlHints()->some View {modifier(HintScope())}
}
