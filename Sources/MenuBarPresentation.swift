import AppKit
import SwiftUI

/// The status item always remains available; this preference chooses its player presentation.
final class MenuBarPresentation: ObservableObject {
    static let shared = MenuBarPresentation()
    @Published private(set) var attached: Bool
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        attached = defaults.object(forKey: "miniAttachedToMenuBar") == nil || defaults.bool(forKey: "miniAttachedToMenuBar")
    }
    func setAttached(_ value: Bool) { attached = value; defaults.set(value, forKey: "miniAttachedToMenuBar") }
}

enum MenuBarBadge: String {
    case empty, paused, playing, crossfade, error
    static func state(hasTrack: Bool, playing: Bool, crossfading: Bool, error: String?) -> Self {
        if playing { return crossfading ? .crossfade : .playing }
        if let error, !error.isEmpty { return .error }
        return hasTrack ? .paused : .empty
    }
    var title: String {
        switch self { case .empty: return "Ready"; case .paused: return "Paused"; case .playing: return "Playing"; case .crossfade: return "Crossfade"; case .error: return "Playback error" }
    }
    func image() -> NSImage {
        let image = NSImage(size:NSSize(width:38,height:22),flipped:false) { _ in
            let cg=NSGraphicsContext.current!.cgContext
            cg.saveGState();cg.translateBy(x:1,y:2);cg.scaleBy(x:0.95,y:0.86)
            let beam=NSBezierPath()
            func polygon(_ points:[NSPoint]) {beam.move(to:points[0]);for point in points.dropFirst(){beam.line(to:point)};beam.close()}
            polygon([.init(x:5,y:1),.init(x:0,y:21),.init(x:11,y:11)])
            polygon([.init(x:12,y:1),.init(x:9,y:22),.init(x:15,y:22)])
            polygon([.init(x:19,y:1),.init(x:13,y:11),.init(x:24,y:21)])
            NSColor.black.setFill();beam.fill();cg.restoreGState()
            NSColor.black.setFill()
            switch self {
            case .playing:
                let path=NSBezierPath();path.move(to:NSPoint(x:29,y:6));path.line(to:NSPoint(x:36,y:11));path.line(to:NSPoint(x:29,y:16));path.close();path.fill()
            case .paused:
                for x in [28.0,33.0] { NSBezierPath(roundedRect:NSRect(x:x,y:6,width:2.5,height:10),xRadius:0.6,yRadius:0.6).fill() }
            case .crossfade:
                cg.saveGState();cg.translateBy(x:26,y:5);cg.scaleBy(x:0.5,y:0.5);cg.addPath(MarkerIcon.path("arrow.left.and.right").cgPath);cg.setStrokeColor(NSColor.black.cgColor);cg.setLineWidth(2.2);cg.setLineCap(.round);cg.strokePath();cg.restoreGState()
            case .error:
                ("!" as NSString).draw(at:NSPoint(x:29,y:2),withAttributes:[.font:NSFont.systemFont(ofSize:15,weight:.bold),.foregroundColor:NSColor.black])
            case .empty:
                NSColor.black.setFill();NSBezierPath(ovalIn:NSRect(x:30,y:9,width:4,height:4)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "HARDPLAY — \(title)"
        return image
    }
}
