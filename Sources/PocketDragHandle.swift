import AppKit
import SwiftUI

final class PocketPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // The invisible space reserved for the lock drawer must not push the player away from the screen edge.
    static func constrainedFrame(_ proposed:NSRect,visible:NSRect)->NSRect {
        var frame=proposed
        let faceLeft:CGFloat=158,faceRight:CGFloat=6
        frame.origin.x=min(max(frame.minX,visible.minX-faceLeft),visible.maxX-frame.width+faceRight)
        frame.origin.y=min(max(frame.minY,visible.minY-6),visible.maxY-frame.height+6)
        return frame
    }
    override func constrainFrameRect(_ frameRect:NSRect,to screen:NSScreen?)->NSRect {
        guard let screen=screen ?? self.screen ?? NSScreen.main else { return frameRect }
        return Self.constrainedFrame(frameRect,visible:screen.visibleFrame)
    }
}
struct PocketDragHandle: NSViewRepresentable {
    final class HandleView:NSView {
        override var mouseDownCanMoveWindow:Bool { false }
        override func draw(_ dirtyRect:NSRect) {
            ("HARD PLAY" as NSString).draw(at:NSPoint(x:0,y:(bounds.height-10)/2),withAttributes:[.font:NSFont.systemFont(ofSize:8,weight:.heavy),.foregroundColor:NSColor.white.withAlphaComponent(0.7),.kern:1])
        }
        private var initialMouse:NSPoint?
        private var initialFrame:NSRect?
        override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }
        private func screenPoint(_ event:NSEvent,window:NSWindow)->NSPoint {
            if let point=event.cgEvent?.location,let primary=NSScreen.screens.first {
                return NSPoint(x:point.x,y:primary.frame.maxY-point.y)
            }
            return window.convertPoint(toScreen:event.locationInWindow)
        }
        override func mouseDown(with event:NSEvent) {
            guard !FloatingPlacement.shared.pocketLocked,let window else { return }
            setAccessibilityValue("Drag started")
            initialMouse=screenPoint(event,window:window);initialFrame=window.frame
        }
        override func mouseDragged(with event:NSEvent) {
            guard !FloatingPlacement.shared.pocketLocked,let window,let initialMouse,let initialFrame else { return }
            let mouse=screenPoint(event,window:window)
            var frame=initialFrame;frame.origin.x+=mouse.x-initialMouse.x;frame.origin.y+=mouse.y-initialMouse.y
            let screen=NSScreen.screens.first { $0.frame.contains(mouse) } ?? window.screen
            window.setFrame(window.constrainFrameRect(frame,to:screen),display:true)
            setAccessibilityValue("Position \(Int(window.frame.minX)), \(Int(window.frame.minY))")
        }
        override func mouseUp(with event:NSEvent) { initialMouse=nil;initialFrame=nil }
        override func resetCursorRects() { addCursorRect(bounds,cursor:FloatingPlacement.shared.pocketLocked ? .arrow:.openHand) }
    }
    func makeNSView(context:Context)->HandleView { let view=HandleView();view.setAccessibilityElement(true);view.setAccessibilityRole(.staticText);view.setAccessibilityLabel("HARD PLAY");view.setAccessibilityHelp("Drag here to move the player anywhere");view.setAccessibilityValue("Ready to move");return view }
    func updateNSView(_ view:HandleView,context:Context){view.window?.invalidateCursorRects(for:view)}
}
