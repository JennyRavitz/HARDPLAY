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
        let image = NSImage(size:NSSize(width:30,height:18), flipped:false) { _ in
            NSColor.black.setFill()
            for (index,height) in [6.0,11.0,16.0,11.0,6.0].enumerated() {
                NSBezierPath(roundedRect:NSRect(x:Double(index)*3,y:(18-height)/2,width:1.8,height:height),xRadius:0.9,yRadius:0.9).fill()
            }
            switch self {
            case .playing:
                let path = NSBezierPath(); path.move(to:NSPoint(x:21,y:4)); path.line(to:NSPoint(x:28,y:9)); path.line(to:NSPoint(x:21,y:14)); path.close(); path.fill()
            case .paused:
                for x in [20.0,25.0] { NSBezierPath(roundedRect:NSRect(x:x,y:4,width:2.4,height:10),xRadius:0.7,yRadius:0.7).fill() }
            case .crossfade:
                NSImage(systemSymbolName:"arrow.left.arrow.right",accessibilityDescription:nil)?.draw(in:NSRect(x:17,y:2,width:13,height:14))
            case .error:
                ("!" as NSString).draw(at:NSPoint(x:21,y:1),withAttributes:[.font:NSFont.systemFont(ofSize:14,weight:.bold),.foregroundColor:NSColor.black])
            case .empty:
                NSColor.black.setStroke(); let path=NSBezierPath(ovalIn:NSRect(x:21,y:6,width:6,height:6)); path.lineWidth=1.5; path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "HARDPLAY — \(title)"
        return image
    }
}
