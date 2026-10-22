import AppKit
import SwiftUI

/// Owns the whole hold gesture, so releasing cannot turn into a second Lock click.
struct PocketUnlockControl: NSViewRepresentable {
    final class HoldView: NSView {
        var timer: Timer?
        var started: TimeInterval?
        var progress = 0.0
        override var acceptsFirstResponder: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func draw(_ dirtyRect:NSRect) {
            NSColor(calibratedRed:0.24,green:0.36,blue:0.5,alpha:1).setFill()
            NSBezierPath(roundedRect:bounds,xRadius:7,yRadius:7).fill()
            let fill=NSRect(x:0,y:0,width:bounds.width*progress,height:3)
            NSColor(calibratedRed:0.65,green:0.82,blue:1,alpha:1).setFill();fill.fill()
            let text=progress>0 ? "Keep holding…":"Hold 3s to unlock"
            let attrs:[NSAttributedString.Key:Any]=[.font:StageTypography.native(11),.foregroundColor:NSColor.white]
            let size=(text as NSString).size(withAttributes:attrs)
            (text as NSString).draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attrs)
        }
        func begin() {
            guard ControlLock.shared.isLocked else { return }
            cancel();started=ProcessInfo.processInfo.systemUptime
            timer=Timer.scheduledTimer(withTimeInterval:0.02,repeats:true) { [weak self] _ in
                guard let self,let start=self.started else { return }
                self.progress=min(1,(ProcessInfo.processInfo.systemUptime-start)/3);self.needsDisplay=true
                if self.progress>=1 { self.cancel();ControlLock.shared.unlock(heldFor:3) }
            }
        }
        func cancel(){timer?.invalidate();timer=nil;started=nil;progress=0;needsDisplay=true}
        override func mouseDown(with event:NSEvent){window?.makeFirstResponder(self);begin()}
        override func mouseUp(with event:NSEvent){cancel()}
        override func mouseDragged(with event:NSEvent){if !bounds.contains(convert(event.locationInWindow,from:nil)){cancel()}}
        override func keyDown(with event:NSEvent){if !event.isARepeat && (event.keyCode==49 || event.keyCode==36){begin()}}
        override func keyUp(with event:NSEvent){cancel()}
        override func resignFirstResponder()->Bool{cancel();return super.resignFirstResponder()}
        override func accessibilityPerformPress()->Bool{window?.makeFirstResponder(self);return true}
    }
    func makeNSView(context:Context)->HoldView {let view=HoldView();view.setAccessibilityElement(true);view.setAccessibilityRole(.button);view.setAccessibilityLabel("Hold to Unlock Controls");view.setAccessibilityHelp("Hold mouse or Space for three seconds. Music keeps playing.");return view}
    func updateNSView(_ view:HoldView,context:Context){}
    static func dismantleNSView(_ view:HoldView,coordinator:()){view.cancel()}
}
