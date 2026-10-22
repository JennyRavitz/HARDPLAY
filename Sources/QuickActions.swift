import SwiftUI

struct QuickActionButton:Codable,Identifiable,Equatable {
    var id=UUID()
    var action:MappedAction
    var behavior:ButtonBehavior
    var valid:Bool {action.valid && action.rawValue != "volume" && (behavior != .toggle || action.supportsToggle)}
}
final class QuickActions:ObservableObject {
    static let shared=QuickActions()
    @Published private(set) var buttons:[QuickActionButton]=[]
    private let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        if let data=defaults.data(forKey:"quickActionButtons"),let saved=try? JSONDecoder().decode([QuickActionButton].self,from:data),saved.count<=4,Set(saved.map(\.id)).count==saved.count,saved.allSatisfy(\.valid) {buttons=saved}
    }
    private var canEdit:Bool {!ControlLock.shared.isLocked && !SetupLock.shared.settingsBlocked}
    private func save() {defaults.set(try? JSONEncoder().encode(buttons),forKey:"quickActionButtons")}
    func add(_ action:MappedAction) {
        guard canEdit,buttons.count<4 else {return}
        let button=QuickActionButton(action:action,behavior:action.defaultBehavior)
        guard button.valid else {return};buttons.append(button);save()
    }
    func assign(_ action:MappedAction,to id:UUID) {
        guard canEdit,action.valid,action.rawValue != "volume",let i=buttons.firstIndex(where:{$0.id==id}) else {return}
        buttons[i].action=action;buttons[i].behavior=action.defaultBehavior;save()
    }
    func behavior(_ behavior:ButtonBehavior,id:UUID) {
        guard canEdit,let i=buttons.firstIndex(where:{$0.id==id}),behavior != .toggle || buttons[i].action.supportsToggle else {return}
        buttons[i].behavior=behavior;save()
    }
    func remove(_ id:UUID) {guard canEdit else {return};buttons.removeAll {$0.id==id};save()}
}
struct ActionChoices:View {
    let choose:(MappedAction)->Void
    var body:some View {
        ForEach(MappedAction.all.filter {$0.rawValue != "volume"}) {action in Button(action.title) {choose(action)}}
        if !Player.shared.tracks.isEmpty {
            Menu("Play a track") {ForEach(Player.shared.tracks) {track in Button(track.title) {choose(MappedAction(rawValue:"track:"+track.id))}}}
        }
    }
}
struct QuickActionMenu:View {
    let button:QuickActionButton
    @ObservedObject var actions=QuickActions.shared
    var body:some View {
        Menu("Assign action") {ActionChoices {actions.assign($0,to:button.id)}}
        if button.action.supportsToggle {
            ForEach(ButtonBehavior.allCases,id:\.self) {mode in
                Button((mode==button.behavior ? "✓ ":"")+mode.rawValue) {actions.behavior(mode,id:button.id)}
            }
        }
        if let section=button.action.workspaceSection {Divider();ForEach([WindowDestination.inside,.nearby,.independent]) {value in Button("Open · "+value.title) {WorkspaceState.shared.open(section,at:value)}}}
        Divider();Button("Remove Button",role:.destructive) {actions.remove(button.id)}
    }
}
struct QuickActionSettings:View {
    @ObservedObject var actions=QuickActions.shared
    var body:some View {
        DisclosureGroup("Custom quick buttons") {
            VStack(alignment:.leading,spacing:12) {
                Text("Up to four buttons below the player toolbar. Right-click to reassign. Trigger runs once; Toggle switches on and off.").font(.stage(size:11)).foregroundStyle(.secondary)
                ForEach(actions.buttons) {button in
                    HStack {Text(button.action.title).lineLimit(2).fixedSize(horizontal:false,vertical:true);Spacer();Menu {QuickActionMenu(button:button)} label:{Text(button.behavior.rawValue+" · Edit")}}
                }
                Menu {ActionChoices {actions.add($0)}} label:{MarkerLabel("Add Button",systemImage:"plus")}.disabled(actions.buttons.count>=4)
            }.padding(.top,10)
        }
    }
}
struct QuickActionBar:View {
    @ObservedObject var actions=QuickActions.shared
    @ObservedObject var mappings=ControlMappings.shared
    @ObservedObject var player=Player.shared
    @ObservedObject var windows=WindowPresentation.shared
    @ObservedObject var setup=SetupLock.shared
    @ObservedObject var lock=ControlLock.shared
    var body:some View {
        if !actions.buttons.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing:12) {
                    ForEach(actions.buttons) {button in
                        Button {mappings.trigger(button.action,behavior:button.behavior)} label:{Text(button.action.title).font(.stage(size:12)).padding(.horizontal,12).frame(height:36)}
                            .buttonStyle(PlayerControlStyle(active:mappings.isOn(button.action) ?? false))
                            .stageHint(button.action.title+" · "+button.behavior.rawValue+" · right-click to assign")
                            .contextMenu {QuickActionMenu(button:button)}
                    }
                }.padding(.vertical,4)
            }.fixedSize(horizontal:false,vertical:true).disabled(lock.isLocked)
        }
    }
}
extension MappedAction {
    var workspaceSection:WorkspaceSection? {
        switch rawValue {case "settings":return .settings;case "themes":return .themes;case "mappings":return .mappings;case "backup":return .backup;case "viewer":return .viewer;case "editSelected":return .editor;default:return nil}
    }
}
