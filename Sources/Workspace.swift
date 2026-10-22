import AppKit
import SwiftUI

enum WorkspaceMode:String {case nearby,single}
enum WorkspaceSection:String,CaseIterable,Identifiable {
    case settings,themes,mappings,backup,viewer,editor
    var id:String {rawValue}
    var title:String {switch self {case .settings:return "Settings";case .themes:return "Themes";case .mappings:return "MIDI / Keys";case .backup:return "Backup";case .viewer:return "Viewer";case .editor:return "Audio Edit"}}
    var icon:String {switch self {case .settings:return "slider.horizontal.3";case .themes:return "paintpalette";case .mappings:return "pianokeys";case .backup:return "network";case .viewer:return "iphone";case .editor:return "scissors"}}
}
final class WorkspaceState:ObservableObject {
    static let shared=WorkspaceState()
    @Published private(set) var mode=WorkspaceMode(rawValue:UserDefaults.standard.string(forKey:"workspaceMode") ?? "") ?? .nearby
    @Published var section:WorkspaceSection?
    @Published var editor:QuickEditModel?
    var title:String {mode == .single ? "Single Window":"Nearby Windows"}
    func toggle() {
        guard !ControlLock.shared.isLocked else {return}
        mode=mode == .single ? .nearby:.single
        UserDefaults.standard.set(mode.rawValue,forKey:"workspaceMode")
        AppDelegate.shared?.workspaceModeChanged()
    }
    /// True means this request belongs to the single-window workspace, even when protected.
    @discardableResult func present(_ target:WorkspaceSection)->Bool {
        guard mode == .single else {return false}
        guard !ControlLock.shared.isLocked else {return true}
        if target == .editor {guard !SetupLock.shared.editsBlocked else {return true}}
        else if target != .settings {guard !SetupLock.shared.settingsBlocked else {return true}}
        if section == .mappings,target != .mappings {ControlMappings.shared.mapping=false}
        section=target;AppDelegate.shared?.showMain();AppDelegate.shared?.makeRoomForWorkspace()
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
