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
            let face=NSBezierPath(roundedRect:NSRect(x:1,y:1,width:23,height:20),xRadius:4,yRadius:4)
            NSGradient(starting:NSColor(calibratedRed:0.92,green:0.13,blue:0.12,alpha:1),ending:NSColor(calibratedRed:0.38,green:0.025,blue:0.04,alpha:1))?.draw(in:face,angle:-90)
            NSColor.white.withAlphaComponent(0.45).setStroke();face.lineWidth=0.7;face.stroke()
            let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
            let attributes:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:7.5,weight:.heavy),.foregroundColor:NSColor.white,.paragraphStyle:paragraph]
            ("Hard" as NSString).draw(in:NSRect(x:1,y:10,width:23,height:10),withAttributes:attributes)
            ("Play" as NSString).draw(in:NSRect(x:1,y:2,width:23,height:10),withAttributes:attributes)
            NSColor.labelColor.setFill()
            switch self {
            case .playing:
                let path=NSBezierPath();path.move(to:NSPoint(x:29,y:6));path.line(to:NSPoint(x:36,y:11));path.line(to:NSPoint(x:29,y:16));path.close();path.fill()
            case .paused:
                for x in [28.0,33.0] { NSBezierPath(roundedRect:NSRect(x:x,y:6,width:2.5,height:10),xRadius:0.6,yRadius:0.6).fill() }
            case .crossfade:
                NSImage(systemSymbolName:"arrow.left.arrow.right",accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[.labelColor]))?.draw(in:NSRect(x:26,y:4,width:12,height:14))
            case .error:
                ("!" as NSString).draw(at:NSPoint(x:29,y:2),withAttributes:[.font:NSFont.systemFont(ofSize:15,weight:.bold),.foregroundColor:NSColor.labelColor])
            case .empty:
                NSColor.secondaryLabelColor.setFill();NSBezierPath(ovalIn:NSRect(x:30,y:9,width:4,height:4)).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Hard Play — \(title)"
        return image
    }
}
