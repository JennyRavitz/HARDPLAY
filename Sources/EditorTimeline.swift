import AppKit
import SwiftUI

struct EditorTimeline:NSViewRepresentable {
    @ObservedObject var edit:QuickEditModel
    final class TimelineView:NSView {
        weak var edit:QuickEditModel?
        private var tracking:NSTrackingArea?
        private var anchor:Double?
        private var edge:Int=0
        private var initialX:CGFloat=0
        private var dragged=false
        private var additive=false
        var pointerX:CGFloat?
        override var mouseDownCanMoveWindow:Bool {false}
        override var acceptsFirstResponder:Bool {true}
        override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
        override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking {removeTrackingArea(tracking)};tracking=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.mouseMoved,.activeInKeyWindow,.inVisibleRect],owner:self);addTrackingArea(tracking!)}
        private func x(_ time:Double)->CGFloat {guard let edit,edit.viewport.length>0 else {return 0};return CGFloat((time-edit.viewport.start)/edit.viewport.length)*bounds.width}
        private func point(_ event:NSEvent)->(CGFloat,Double) {let local=convert(event.locationInWindow,from:nil);let px=min(bounds.width,max(0,local.x));return (px,edit?.viewport.time(at:Double(px/max(1,bounds.width))) ?? 0)}
        override func draw(_ dirtyRect:NSRect) {
            guard let edit else {return};let area=NSRect(x:0,y:22,width:bounds.width,height:max(1,bounds.height-22))
            NSColor(calibratedRed:0.035,green:0.07,blue:0.11,alpha:1).setFill();bounds.fill()
            let grid=NSBezierPath();grid.lineWidth=0.5;NSColor.white.withAlphaComponent(0.12).setStroke()
            for i in 0...8 {let px=bounds.width*CGFloat(i)/8;grid.move(to:.init(x:px,y:22));grid.line(to:.init(x:px,y:bounds.height));let label=ClipRange.label(edit.viewport.time(at:Double(i)/8));(label as NSString).draw(at:.init(x:min(max(3,px-25),max(3,bounds.width-62)),y:3),withAttributes:[.font:StageTypography.native(9),.foregroundColor:NSColor.white.withAlphaComponent(0.65)])};grid.stroke()
            let wave=NSBezierPath();wave.lineWidth=1;NSColor(calibratedRed:0.58,green:0.77,blue:0.96,alpha:0.8).setStroke()
            for (i,peak) in edit.wavePeaks.enumerated() {let px=CGFloat(i)/CGFloat(max(1,edit.wavePeaks.count-1))*bounds.width;let h=max(1,CGFloat(peak)*(area.height-16));wave.move(to:.init(x:px,y:area.midY-h/2));wave.line(to:.init(x:px,y:area.midY+h/2))};wave.stroke()
            NSColor.black.withAlphaComponent(0.3).setFill();area.fill()
            for (index,clip) in edit.clipSelection.clips.enumerated() {
                let left=max(0,x(clip.range.start)),right=min(bounds.width,x(clip.range.end));guard right>left else {continue}
                let selected=edit.clipSelection.selected.contains(clip.id) && !(dragged && !additive)
                NSColor(calibratedRed:0.58,green:0.77,blue:0.96,alpha:selected ? 0.25:0.02).setFill();NSRect(x:left,y:22,width:right-left,height:area.height).fill()
                NSColor.white.withAlphaComponent(selected ? 0.8:0.25).setFill();NSRect(x:left,y:22,width:1,height:area.height).fill()
                if right-left>55 {(String(format:"%02d",index+1) as NSString).draw(at:.init(x:left+6,y:bounds.height-17),withAttributes:[.font:StageTypography.native(10),.foregroundColor:selected ? NSColor.white:NSColor.gray])}
            }
            let left=x(edit.start),right=x(edit.end)
            if dragged {NSColor(calibratedRed:0.58,green:0.77,blue:0.96,alpha:0.3).setFill();NSRect(x:max(0,left),y:22,width:max(0,min(bounds.width,right)-max(0,left)),height:area.height).fill()}
            if edit.hasSelection || dragged {
                for px in [left,right] where px>=0 && px<=bounds.width {NSColor(calibratedRed:0.65,green:0.83,blue:1,alpha:1).setFill();NSRect(x:px-1,y:22,width:2,height:area.height).fill();NSBezierPath(roundedRect:NSRect(x:px-4,y:area.midY-11,width:8,height:22),xRadius:3,yRadius:3).fill()}
            }
            let head=x(edit.position)
            if head>=0 && head<=bounds.width {NSColor.white.setFill();NSRect(x:head,y:22,width:1,height:area.height).fill()}
            if let pointerX,let time=edit.hoverTime {let text=(NSEvent.modifierFlags.contains(.option) ? "▶ ":"")+ClipRange.label(time);(text as NSString).draw(at:.init(x:min(max(5,pointerX-35),max(5,bounds.width-110)),y:bounds.height-18),withAttributes:[.font:StageTypography.native(11),.foregroundColor:NSColor.white,.backgroundColor:NSColor(calibratedRed:0.04,green:0.08,blue:0.14,alpha:0.95)])}
        }
        override func mouseEntered(with event:NSEvent){mouseMoved(with:event)}
        override func mouseMoved(with event:NSEvent){let (px,time)=point(event);pointerX=px;edit?.timelineWindow=window;edit?.hover(time);needsDisplay=true}
        override func mouseExited(with event:NSEvent){pointerX=nil;edit?.hover(nil);needsDisplay=true}
        override func mouseDown(with event:NSEvent){
            guard let edit,edit.canEdit else {return};window?.makeFirstResponder(self)
            let (px,time)=point(event);pointerX=px;edit.timelineWindow=window;edit.hover(time);anchor=nil;dragged=false
            if event.modifierFlags.contains(.option) {return}
            anchor=time;initialX=px;additive=event.modifierFlags.contains(.command)
            if !additive,edit.hasSelection,abs(px-x(edit.start))<=8 {edge=1}
            else if !additive,edit.hasSelection,abs(px-x(edit.end))<=8 {edge=2}
            else {edge=0}
        }
        override func mouseDragged(with event:NSEvent){
            guard let edit,edit.canEdit else {return};let (px,time)=point(event);pointerX=px;edit.hover(time)
            if event.modifierFlags.contains(.option) {needsDisplay=true;return}
            guard let anchor else {return};if abs(px-initialX)>2 {dragged=true}
            guard dragged else {return}
            if edge == 1 {edit.setStart(time)}else if edge == 2 {edit.setEnd(time)}else {edit.selectRegion(anchor,time)}
            needsDisplay=true
        }
        override func mouseUp(with event:NSEvent){
            guard let edit,anchor != nil else {anchor=nil;dragged=false;return}
            let (_,time)=point(event)
            if dragged {edit.commitRegion(add:additive)}else {edit.seekPreview(time);edit.selectClip(at:time,add:additive)}
            anchor=nil;edge=0;dragged=false;needsDisplay=true
        }
        override func keyDown(with event:NSEvent){
            guard let edit else {return}
            if event.keyCode == 49 {edit.togglePreview()}
            else if event.keyCode == 53 {edit.stopPreview()}
            else if event.keyCode == 123 || event.keyCode == 124 {let delta=event.modifierFlags.contains(.shift) ? 0.01:1/edit.sampleRate;edit.nudgeCursor(event.keyCode == 123 ? -delta:delta)}
            else {super.keyDown(with:event)}
        }
        override func magnify(with event:NSEvent){guard let edit,!edit.busy else {return};let fraction=point(event).0/max(1,bounds.width);edit.zoom(max(0.1,1+event.magnification),at:Double(fraction))}
        override func scrollWheel(with event:NSEvent){guard let edit,!edit.busy else {return};if event.modifierFlags.contains(.command) {edit.zoom(pow(1.03,Double(-event.scrollingDeltaY)),at:Double(point(event).0/max(1,bounds.width)))}else {edit.viewport.pan(edit.viewport.start+Double(event.scrollingDeltaX+event.scrollingDeltaY)*edit.viewport.length/500)}}
        override func resetCursorRects(){addCursorRect(bounds,cursor:.crosshair)}
    }
    func makeNSView(context:Context)->TimelineView {let view=TimelineView();view.setAccessibilityElement(true);view.setAccessibilityRole(.image);view.setAccessibilityLabel("Audio Waveform Editor");view.setAccessibilityHelp("Drag to select audio. Drag selection edges to trim. Hold Option and move over audio to audition.");return view}
    func updateNSView(_ view:TimelineView,context:Context){view.edit=edit;edit.timelineWindow=view.window;view.needsDisplay=true;if let px=view.pointerX {edit.hover(edit.viewport.time(at:Double(px/max(1,view.bounds.width))))};view.setAccessibilityValue("\(edit.selectionCount) selected, In \(ClipRange.preciseLabel(edit.start)), Out \(ClipRange.preciseLabel(edit.end)), zoom \(Int(edit.viewport.zoom))")}
}
