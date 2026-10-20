import SwiftUI

struct MappingTarget: ViewModifier {
    @ObservedObject var mappings = ControlMappings.shared
    var action: MappedAction
    func body(content:Content) -> some View {
        content.overlay {
            if mappings.mapping {
                Button { mappings.learn(action) } label: {
                    RoundedRectangle(cornerRadius:8).fill(Color(red:0.04,green:0.12,blue:0.23).opacity(0.85))
                        .overlay(RoundedRectangle(cornerRadius:8).stroke(mappings.selected == action ? .white : accent,lineWidth:2))
                        .overlay(Text(action.title).font(.system(size:9,weight:.semibold)).foregroundStyle(.white).padding(2))
                }.buttonStyle(.plain).accessibilityLabel("Map: \(action.title)")
            }
        }
    }
}
extension View {
    func mapAction(_ action:String) -> some View { modifier(MappingTarget(action:.init(rawValue:action))) }
}
struct MappingView: View {
    @ObservedObject var mappings = ControlMappings.shared
    @ObservedObject var player = Player.shared
    @ObservedObject var lock = ControlLock.shared
    @ObservedObject var setup = SetupLock.shared
    private var actions:[MappedAction] { MappedAction.all + player.tracks.map { .init(rawValue:"track:" + $0.id) } }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Keyboard / MIDI").font(.system(size:18,weight:.semibold))
                Spacer()
                Button { AppDelegate.shared.minimize(AppDelegate.shared.mappingWindow) } label: { Image(systemName:"minus").frame(width:28,height:28) }
                    .buttonStyle(PlayerControlStyle()).accessibilityLabel("Minimize Mapping Window").stageHint("Minimize · restore from menu bar").disabled(lock.isLocked)
                Toggle("Map",isOn:$mappings.mapping).toggleStyle(.button).tint(accent).disabled(setup.settingsBlocked)
                Button { if setup.settingsBlocked { setup.unlock() } else { mappings.mapping = false; setup.lockSettings() } } label: { Image(systemName:setup.settingsBlocked ? "lock.fill":"lock.open").frame(width:30,height:30) }
                    .buttonStyle(PlayerControlStyle(active:setup.settingsBlocked)).accessibilityLabel(setup.settingsBlocked ? "Unlock Settings":"Lock Settings").stageHint(setup.settingsBlocked ? "Unlock settings and mappings":"Protect settings and mappings")
            }
            HStack {
                Picker("Input",selection:$mappings.input) { ForEach(MappingInput.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).disabled(setup.settingsBlocked)
                Menu {
                    Button("Save Set…") { mappings.saveSet() }
                    Button("Open Set…") { mappings.loadSet() }
                } label: { Label(mappings.setName,systemImage:"folder").lineLimit(1) }.fixedSize().disabled(setup.settingsBlocked)
            }
            Text(mappings.mapping ? "Select an action here or click a highlighted player button. Then press your key or MIDI button. Esc cancels learning." : "Mappings are active. Enable Map to change assignments.")
                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            ScrollView {
                LazyVStack(spacing:6) {
                    ForEach(actions) { action in mappingRow(action) }
                }
            }
            Text("Trigger = run once · Toggle = first press On, second press Off").font(.system(size:10)).foregroundStyle(.secondary)
            Text(mappings.message).font(.system(size:11)).foregroundStyle(accent).fixedSize(horizontal:false,vertical:true)
            Divider()
            HStack { Text("MIDI Inputs").font(.system(size:12,weight:.semibold)); Spacer(); Button("Refresh") { mappings.refreshMIDI() }.font(.system(size:11)).disabled(setup.settingsBlocked) }
            Text(mappings.devices.isEmpty ? "No MIDI inputs connected" : mappings.devices.joined(separator:" · "))
                .font(.system(size:11)).foregroundStyle(.secondary).lineLimit(3)
            Text("MIDI buttons: Note / CC. Master Volume: continuous CC fader. Single keys: inside HARDPLAY. Global shortcuts registered: \(mappings.globalCount). ⌥⌘ Space and standard ⌘ shortcuts stay reserved.")
                .font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(18).frame(minWidth:500,minHeight:500)
            .preferredColorScheme(.dark).foregroundStyle(.white)
            .onChange(of:setup.settingsBlocked) { _, blocked in if blocked { mappings.mapping = false } }
            .disabled(lock.isLocked).overlay { if lock.isLocked { UnlockShield() } }
    }
    private func mappingRow(_ action:MappedAction) -> some View {
        HStack(spacing:8) {
            Text(action.title).font(.system(size:12,weight:.medium)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
            ForEach(MappingInput.allCases,id:\.self) { input in
                VStack(spacing:4) {
                    Button { mappings.learn(action,input:input) } label: {
                        VStack(spacing:3) {
                            Text(input.rawValue).font(.system(size:9)).foregroundStyle(.secondary)
                            Text(action.rawValue == "volume" && input == .keyboard ? "MIDI CC" : mappings.selected == action && mappings.input == input ? "Listening…" : mappings.label(action,input:input)).font(.system(size:11)).lineLimit(1)
                        }.frame(width:105,height:34)
                    }.buttonStyle(PlayerControlStyle(active:mappings.selected == action && mappings.input == input))
                        .disabled(setup.settingsBlocked || (action.rawValue == "volume" && input == .keyboard))
                        .accessibilityLabel("Map \(action.title): \(input.rawValue)")
                        .contextMenu { Button("Clear \(input.rawValue)") { mappings.clear(action,input:input) } }
                    behaviorControl(action,input:input)
                }
            }
        }.padding(7).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:8))
    }
    @ViewBuilder private func behaviorControl(_ action:MappedAction,input:MappingInput) -> some View {
        if action.rawValue == "volume" {
            Text("Continuous CC").font(.system(size:10)).foregroundStyle(.secondary)
        } else if action.supportsToggle {
            Menu {
                ForEach(ButtonBehavior.allCases,id:\.self) { behavior in
                    Button { mappings.setBehavior(behavior,for:action,input:input) } label: {
                        if mappings.behavior(action,input:input) == behavior { Label(behavior.rawValue,systemImage:"checkmark") }
                        else { Text(behavior.rawValue) }
                    }
                }
            } label: {
                Text(behaviorLabel(action,input:input)).font(.system(size:10))
            }.menuStyle(.borderlessButton).fixedSize()
                .disabled(setup.settingsBlocked || !mappings.hasBinding(action,input:input))
                .accessibilityLabel("\(action.title) \(input.rawValue) behavior: \(behaviorLabel(action,input:input))")
        } else {
            Text("Trigger").font(.system(size:10)).foregroundStyle(.secondary)
        }
    }

    private func behaviorLabel(_ action:MappedAction,input:MappingInput) -> String {
        let mode = mappings.behavior(action,input:input)
        if mode == .toggle, mappings.hasBinding(action,input:input), let on = mappings.isOn(action) {
            return "Toggle · " + (on ? "On":"Off")
        }
        return mode.rawValue
    }

}
