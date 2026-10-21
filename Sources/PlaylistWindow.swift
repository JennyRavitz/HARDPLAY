import AppKit
import SwiftUI

enum PlaylistDockEdge: String, CaseIterable {
    case bottom,right,left,top
    var title:String { switch self { case .bottom:return "Below Player";case .right:return "Right of Player";case .left:return "Left of Player";case .top:return "Above Player" } }
}
/// A docked child panel follows its player; a detached panel moves independently.
final class PlaylistWindowState: ObservableObject {
    static let shared = PlaylistWindowState()
    @Published private(set) var detached = UserDefaults.standard.bool(forKey:"playlistDetached")
    @Published private(set) var edge = UserDefaults.standard.string(forKey:"playlistDockEdge").flatMap(PlaylistDockEdge.init(rawValue:))
    @Published private(set) var fromMini = false
    private var positioning = false
    func detach() {
        guard !ControlLock.shared.isLocked else { return }
        releaseParent();edge=nil;detached=true;save();AppDelegate.shared.showPlaylistWindow()
    }
    func dock(_ side:PlaylistDockEdge,fromMini:Bool=false) {
        guard !ControlLock.shared.isLocked else { return }
        releaseParent();self.fromMini=fromMini;edge=side;detached=true;save()
        let app=AppDelegate.shared!,owner=fromMini ? app.miniWindow!:app.mainWindow!
        app.restore(owner)
        positionDock()
        owner.addChildWindow(app.playlistWindow,ordered:.above)
        app.playlistWindow.orderFront(nil)
        ControlMappings.shared.refreshStates()
    }
    func toggleDrawer(fromMini:Bool) {
        guard !ControlLock.shared.isLocked else { return }
        let app=AppDelegate.shared!
        if detached,edge == nil { app.showPlaylistWindow();return }
        if edge != nil,app.playlistWindow.isVisible,self.fromMini == fromMini { app.playlistWindow.orderOut(nil);ControlMappings.shared.refreshStates() }
        else { dock(edge ?? .bottom,fromMini:fromMini) }
    }
    func attach(toMini:Bool) {
        guard !ControlLock.shared.isLocked else { return }
        releaseParent();edge=nil;detached=false;save();AppDelegate.shared.playlistWindow.orderOut(nil)
        if toMini { AppDelegate.shared.showMini() } else { AppDelegate.shared.showMain() }
    }
    private func save() {
        UserDefaults.standard.set(detached,forKey:"playlistDetached")
        UserDefaults.standard.set(edge?.rawValue,forKey:"playlistDockEdge")
    }
    private func releaseParent() {
        if let panel=AppDelegate.shared?.playlistWindow { panel.parent?.removeChildWindow(panel) }
    }
    func positionDock(fitGroup:Bool=true) {
        guard !positioning,let edge,let app=AppDelegate.shared,let panel=app.playlistWindow else { return }
        let owner=fromMini ? app.miniWindow!:app.mainWindow!
        guard let screen=owner.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        positioning=true;defer { positioning=false }
        let gap:CGFloat=8,sideways=edge == .left || edge == .right
        let size=NSSize(width:sideways ? 400:max(380,min(600,owner.frame.width)),height:300)
        var parent=owner.frame
        let left:CGFloat=edge == .left ? size.width+gap:0,right:CGFloat=edge == .right ? size.width+gap:0
        let bottom:CGFloat=edge == .bottom ? size.height+gap:0,top:CGFloat=edge == .top ? size.height+gap:0
        if fitGroup {
            if parent.width+left+right<=screen.width { parent.origin.x=min(max(parent.minX,screen.minX+left),screen.maxX-parent.width-right) }
            if parent.height+bottom+top<=screen.height { parent.origin.y=min(max(parent.minY,screen.minY+bottom),screen.maxY-parent.height-top) }
            if parent != owner.frame { owner.setFrame(parent,display:true) }
        }
        var origin:NSPoint
        switch edge {
        case .bottom:origin=NSPoint(x:parent.minX,y:parent.minY-gap-size.height)
        case .top:origin=NSPoint(x:parent.minX,y:parent.maxY+gap)
        case .right:origin=NSPoint(x:parent.maxX+gap,y:parent.maxY-size.height)
        case .left:origin=NSPoint(x:parent.minX-gap-size.width,y:parent.maxY-size.height)
        }
        origin.x=min(max(origin.x,screen.minX),screen.maxX-size.width)
        origin.y=min(max(origin.y,screen.minY),screen.maxY-size.height)
        panel.setFrame(NSRect(origin:origin,size:size),display:true)
    }
    func ownerMoved(_ window:NSWindow) {
        let app=AppDelegate.shared!
        if edge != nil,window === (fromMini ? app.miniWindow:app.mainWindow) { positionDock(fitGroup:false) }
    }
}
