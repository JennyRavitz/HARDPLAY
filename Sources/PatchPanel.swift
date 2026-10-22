import AppKit
import SwiftUI

/// This edge owns the press so a long hold never becomes a waveform seek or window drag.
struct PatchHoldEdge:NSViewRepresentable {
    var opened:()->Void
    final class EdgeView:NSView {
        var opened:(()->Void)?
        private var timer:Timer?
        private var started:TimeInterval?
        private var progress:Double=0
        override var mouseDownCanMoveWindow:Bool {false}
        override func draw(_ dirtyRect:NSRect) {
            guard progress>0 else {return}
            NSColor(calibratedRed:0.65,green:0.83,blue:1,alpha:0.8).setFill()
            NSBezierPath(roundedRect:NSRect(x:bounds.midX-2,y:bounds.minY,width:4,height:bounds.height*progress),xRadius:2,yRadius:2).fill()
        }
        override func mouseDown(with event:NSEvent) {
            cancel();started=ProcessInfo.processInfo.systemUptime;progress=0.01;needsDisplay=true
            let ticker=Timer(timeInterval:0.02,repeats:true) {[weak self] _ in
                guard let self,let start=self.started else {return}
                self.progress=min(1,(ProcessInfo.processInfo.systemUptime-start)/3);self.needsDisplay=true
                if self.progress>=1 {self.cancel();self.opened?()}
            };timer=ticker;RunLoop.main.add(ticker,forMode:.common)
        }
        override func mouseDragged(with event:NSEvent) {if !bounds.insetBy(dx:-4,dy:-4).contains(convert(event.locationInWindow,from:nil)) {cancel()}}
        override func mouseUp(with event:NSEvent) {cancel()}
        override func viewDidMoveToWindow() {super.viewDidMoveToWindow();if window==nil {cancel()}}
        override func accessibilityPerformPress()->Bool {opened?();return true}
        func cancel() {timer?.invalidate();timer=nil;started=nil;progress=0;needsDisplay=true}
    }
    func makeNSView(context:Context)->EdgeView {
        let view=EdgeView();view.opened=opened;view.setAccessibilityElement(true);view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Hold Right Edge for PATCH");view.setAccessibilityHelp("Hold this strip for three seconds to open the rear panel. Release early to cancel.");return view
    }
    func updateNSView(_ view:EdgeView,context:Context) {view.opened=opened}
    static func dismantleNSView(_ view:EdgeView,coordinator:()) {view.cancel()}
}
struct PatchDrawer:View {
    @Binding var open:Bool
    var compact:Bool
    @ObservedObject var lock=ControlLock.shared
    @ObservedObject var setup=SetupLock.shared
    @ObservedObject var placement=FloatingPlacement.shared
    var body:some View {
        VStack(spacing:12) {
            HStack {
                VStack(alignment:.leading,spacing:3) {Text("PATCH").font(.stage(size:20,weight:.bold));Text("REAR PANEL").font(.stage(size:9)).foregroundStyle(.secondary)}
                Spacer()
                Button {withAnimation(.easeInOut(duration:0.22)) {open=false}} label:{MarkerIcon(systemName:"xmark").frame(width:30,height:30)}.buttonStyle(PlayerControlStyle()).accessibilityLabel("Close PATCH")
            }
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    Text(lock.isLocked ? "CONTROLS LOCKED":"CONTROLS AVAILABLE").font(.stage(size:13,weight:.semibold)).foregroundStyle(lock.isLocked ? .orange:accent)
                    if lock.isLocked {
                        NativeUnlockControl().frame(width:148,height:148).frame(maxWidth:.infinity)
                        Text("Swipe clockwise to unlock\nor hold Space for 3 seconds").font(.stage(size:11)).frame(maxWidth:.infinity)
                    }else {
                        Button {lock.lock()} label:{MarkerLabel("Lock Controls",systemImage:"lock").padding(10).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(PlayerControlStyle()).mapAction("lock")
                    }
                    Text("Music keeps playing.").font(.stage(size:11)).foregroundStyle(.secondary)
                    Divider()
                    Button {if setup.isLocked {setup.unlock()}else {setup.lock()}} label:{MarkerLabel(setup.isLocked ? "Unlock Setup":"Lock Setup",systemImage:setup.isLocked ? "lock.fill":"lock.open").padding(10).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(PlayerControlStyle(active:setup.isLocked)).disabled(lock.isLocked)
                    if compact {
                        Button {placement.miniLocked.toggle()} label:{MarkerLabel(placement.miniLocked ? "Unlock Position":"Lock Position",systemImage:"pin").padding(10).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(PlayerControlStyle(active:placement.miniLocked))
                    }
                    Button {withAnimation(.easeInOut(duration:0.22)) {open=false};AppDelegate.shared.showSettingsWindow()} label:{MarkerLabel("Open PATCH Settings",systemImage:"slider.horizontal.3").padding(10).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(PlayerControlStyle()).disabled(lock.isLocked).windowDestinationMenu(.settings)
                    Text("Audio · themes · MIDI / keys\nwindow layout · quick buttons").font(.stage(size:11)).foregroundStyle(.secondary)
                }.padding(.vertical,4)
            }
        }.padding(16).frame(width:260).frame(maxHeight:560).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).stroke(accent.opacity(0.35),lineWidth:1)).shadow(color:.black.opacity(0.4),radius:15,x:-6,y:4)
            .foregroundStyle(.white).preferredColorScheme(.dark).padding(8)
    }
}
