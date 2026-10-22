import AppKit
import SwiftUI

enum WorkspaceMode:String {case nearby,single}
enum WorkspaceSection:String,CaseIterable,Identifiable {
    case settings,themes,mappings,backup,viewer,editor
    var id:String {rawValue}
    var title:String {switch self {case .settings:return "Settings";case .themes:return "Themes";case .mappings:return "MIDI / Keys";case .backup:return "Backup";case .viewer:return "Viewer";case .editor:return "Audio Edit"}}
    var icon:String {switch self {case .settings:return "slider.horizontal.3";case .themes:return "paintpalette";case .mappings:return "pianokeys";case .backup:return "network";case .viewer:return "iphone";case .editor:return "scissors"}}
}
enum WindowDestination:String,CaseIterable,Identifiable {
    case workspace,inside,nearby,independent,ask
    var id:String {rawValue}
    var title:String {switch self {case .workspace:return "Workspace Default";case .inside:return "Inside Player";case .nearby:return "Nearby Window";case .independent:return "Independent Window";case .ask:return "Ask Each Time"}}
}
final class WorkspaceState:ObservableObject {
    static let shared=WorkspaceState()
    @Published private(set) var mode=WorkspaceMode(rawValue:UserDefaults.standard.string(forKey:"workspaceMode") ?? "") ?? .nearby
    @Published var section:WorkspaceSection?
    @Published var editor:QuickEditModel?
    private let defaults:UserDefaults
    @Published private(set) var destinations:[String:String]
    private var forced:WindowDestination?
    private var live:[WorkspaceSection:WindowDestination]=[:]
    private var asking=false
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        destinations=defaults.dictionary(forKey:"windowDestinations") as? [String:String] ?? [:]
        mode=WorkspaceMode(rawValue:defaults.string(forKey:"workspaceMode") ?? "") ?? .nearby
    }
    func destination(_ target:WorkspaceSection)->WindowDestination {WindowDestination(rawValue:destinations[target.rawValue] ?? "") ?? .workspace}
    func setDestination(_ value:WindowDestination,for target:WorkspaceSection) {
        guard !ControlLock.shared.isLocked,!SetupLock.shared.settingsBlocked else {return}
        destinations[target.rawValue]=value.rawValue;defaults.set(destinations,forKey:"windowDestinations")
    }
    func resolved(_ target:WorkspaceSection)->WindowDestination {
        let value=destination(target)
        return value == .workspace ? (mode == .single ? .inside:.nearby):value
    }
    func followsPlayer(_ target:WorkspaceSection)->Bool { (live[target] ?? resolved(target)) == .nearby }
    func open(_ target:WorkspaceSection,at destination:WindowDestination?=nil) {
        forced=destination;defer {forced=nil}
        guard let app=AppDelegate.shared else {return}
        switch target {
        case .settings:app.showSettingsWindow()
        case .themes:app.showThemesWindow()
        case .mappings:app.showMappings()
        case .backup:app.showBackupWindow()
        case .viewer:app.showWebViewer()
        case .editor:if let track=editor?.track ?? Player.shared.selectedTrack ?? Player.shared.current {app.showQuickEdit(track)}
        }
    }
    var title:String {mode == .single ? "Single Window":"Nearby Windows"}
    func toggle() {
        guard !ControlLock.shared.isLocked else {return}
        mode=mode == .single ? .nearby:.single
        defaults.set(mode.rawValue,forKey:"workspaceMode")
        AppDelegate.shared?.workspaceModeChanged()
    }
    /// True means this request belongs to the single-window workspace, even when protected.
    @discardableResult func present(_ target:WorkspaceSection)->Bool {
        guard !ControlLock.shared.isLocked else {return true}
        if target == .editor {guard !SetupLock.shared.editsBlocked else {return true}}
        else if target != .settings {guard !SetupLock.shared.settingsBlocked else {return true}}
        let placement=forced ?? resolved(target)
        if placement == .ask {
            guard !asking,let app=AppDelegate.shared,let window=app.mainWindow else {return true}
            asking=true;app.showMain()
            let alert=NSAlert();alert.messageText="Open \(target.title)"
            alert.informativeText="Choose where this panel opens. Playback continues."
            for title in ["Inside Player","Nearby Window","Independent Window","Cancel"] {alert.addButton(withTitle:title)}
            alert.showsSuppressionButton=true;alert.suppressionButton?.title="Remember for this panel"
            alert.beginSheetModal(for:window) {[weak self] response in
                guard let self else {return};self.asking=false
                let choices:[WindowDestination]=[.inside,.nearby,.independent]
                let index=response.rawValue-NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                guard choices.indices.contains(index) else {return}
                let choice=choices[index]
                if alert.suppressionButton?.state == .on {self.setDestination(choice,for:target)}
                self.open(target,at:choice)
            };return true
        }
        live[target]=placement
        guard placement == .inside else {
            if section == target {player()}
            return false
        }
        if section == .mappings,target != .mappings {ControlMappings.shared.mapping=false}
        section=target;AppDelegate.shared?.hideWorkspacePanel(target);AppDelegate.shared?.showMain();AppDelegate.shared?.makeRoomForWorkspace()
        return true
    }
    func player() {
        section=nil;ControlMappings.shared.mapping=false
        editor?.hover(nil);editor?.stopPreview()
        WindowPresentation.shared.requestFit()
    }
}

/// Prefer free space around the player; cascade only when the display cannot fit every panel.
enum WorkspaceLayout {
    static func frames(main:NSRect,screen:NSRect,sizes:[NSSize])->[NSRect] {
        var result:[NSRect]=[],occupied=[main]
        for (index,size) in sizes.enumerated() {
            let w=min(size.width,screen.width),h=min(size.height,screen.height),gap:CGFloat=12
            var candidates:[NSRect]=[]
            for anchor in [main]+result {
                candidates += [NSRect(x:anchor.maxX+gap,y:anchor.maxY-h,width:w,height:h),NSRect(x:anchor.minX-w-gap,y:anchor.maxY-h,width:w,height:h),NSRect(x:anchor.minX,y:anchor.minY-h-gap,width:w,height:h),NSRect(x:anchor.minX,y:anchor.maxY+gap,width:w,height:h)]
            }
            let available=candidates.first {r in screen.contains(r) && !occupied.contains(where:{$0.insetBy(dx:-4,dy:-4).intersects(r)})}
            let fallback=NSRect(x:min(max(main.maxX-80+CGFloat(index)*28,screen.minX),screen.maxX-w),y:min(max(main.maxY-h-CGFloat(index)*28,screen.minY),screen.maxY-h),width:w,height:h)
            let frame=available ?? fallback;result.append(frame);occupied.append(frame)
        }
        return result
    }
}

struct WorkspacePane:View {
    let section:WorkspaceSection
    @ObservedObject var workspace=WorkspaceState.shared
    @ObservedObject var player=Player.shared
    var body:some View {
        Group {
            switch section {
            case .settings:PlayerView(settingsOnly:true,embedded:true).padding(16)
            case .themes:ThemeEditorView(embedded:true)
            case .mappings:MappingView(embedded:true)
            case .backup:BackupView(embedded:true)
            case .viewer:WebViewerView(embedded:true)
            case .editor:
                if let edit=workspace.editor {QuickEditView(edit:edit,embedded:true)}
                else {
                    VStack(spacing:14) {
                        Text("Select a track, then open Edit Audio.").font(.stage(size:16))
                        if let track=player.selectedTrack ?? player.current {
                            Button("Edit Selected Track") {AppDelegate.shared.showQuickEdit(track)}.buttonStyle(PlayerControlStyle()).padding(8)
                        }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.black.opacity(0.12),in:RoundedRectangle(cornerRadius:10))
    }
}

struct WindowDestinationSettings:View {
    @ObservedObject var workspace=WorkspaceState.shared
    var body:some View {
        DisclosureGroup("Window opening preferences") {
            VStack(spacing:12) {
                ForEach(WorkspaceSection.allCases) {section in
                    Picker(section.title,selection:Binding(get:{workspace.destination(section)},set:{workspace.setDestination($0,for:section)})) {
                        ForEach(WindowDestination.allCases) {Text($0.title).tag($0)}
                    }
                }
                Text("Nearby panels follow the player. Independent panels keep their own position. Right-click a panel button for a one-time choice.").font(.stage(size:11)).foregroundStyle(.secondary)
            }.padding(.top,10)
        }
    }
}
extension View {
    func windowDestinationMenu(_ section:WorkspaceSection)->some View {
        contextMenu {
            ForEach([WindowDestination.inside,.nearby,.independent]) {value in
                Button("Open · "+value.title) {WorkspaceState.shared.open(section,at:value)}
            }
            Menu("Default location") {
                ForEach(WindowDestination.allCases) {value in
                    Button((WorkspaceState.shared.destination(section)==value ? "✓ ":"")+value.title) {WorkspaceState.shared.setDestination(value,for:section)}
                }
            }
        }
    }
}
