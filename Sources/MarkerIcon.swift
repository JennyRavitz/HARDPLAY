import SwiftUI
import AppKit

/// Hand-inked paths, not font glyphs: every in-app icon follows the same marker weight.
struct MarkerIcon:View {
    let systemName:String
    var size:CGFloat=16
    private static var cache:[String:NSImage]=[:]
    static func image(_ name:String)->NSImage {
        if let image=cache[name] {return image}
        let image=NSImage(size:NSSize(width:24,height:24),flipped:true) {_ in
            guard let context=NSGraphicsContext.current?.cgContext else {return false}
            let path=Self.path(name).cgPath
            context.setStrokeColor(NSColor.black.cgColor);context.setLineCap(.round);context.setLineJoin(.round);context.setLineWidth(2.2);context.addPath(path);context.strokePath()
            context.setAlpha(0.22);context.translateBy(x:0.28,y:-0.18);context.setLineWidth(1.4);context.addPath(path);context.strokePath();return true
        }
        image.isTemplate=true;cache[name]=image;return image
    }
    var body:some View {
        Image(nsImage:Self.image(systemName)).renderingMode(.template).resizable().aspectRatio(contentMode:.fit).frame(width:size,height:size).accessibilityHidden(true)
    }
    static func path(_ name:String)->Path {
        var p=Path()
        func line(_ points:[(Double,Double)],_ closed:Bool=false) {
            guard let a=points.first else {return};p.move(to:.init(x:a.0,y:a.1))
            for (i,b) in points.dropFirst().enumerated() {
                let prev=points[i],bend=(i%2 == 0 ? 0.23 : -0.18)
                p.addQuadCurve(to:.init(x:b.0,y:b.1),control:.init(x:(prev.0+b.0)/2+bend,y:(prev.1+b.1)/2-bend))
            };if closed {p.closeSubpath()}
        }
        func box(_ x:Double,_ y:Double,_ w:Double,_ h:Double){line([(x+0.2,y),(x+w,y+0.2),(x+w-0.2,y+h),(x,y+h-0.2),(x+0.2,y)])}
        func circle(_ x:Double,_ y:Double,_ r:Double) {line((0...16).map {i in let a=Double(i)*Double.pi/8,dr=(i%3 == 0 ? 0.15:0);return (x+cos(a)*(r+dr),y+sin(a)*(r-dr))})}
        func arrow(_ left:Bool=false) {line(left ? [(14,5),(7,12),(14,19)]:[(10,5),(17,12),(10,19)])}
        switch name {
        case "play.fill","play":line([(7,4),(20,12),(7,20),(7,4)])
        case "pause.fill","pause":line([(7,5),(7,19)]);line([(16,5),(16,19)])
        case "stop.fill","stop":box(5,5,14,14)
        case "backward.end.fill":line([(5,5),(5,19)]);line([(19,5),(7,12),(19,19),(19,5)])
        case "forward.end.fill":line([(19,5),(19,19)]);line([(5,5),(17,12),(5,19),(5,5)])
        case "chevron.down":line([(5,8),(12,16),(19,8)])
        case "chevron.up":line([(5,16),(12,8),(19,16)])
        case "chevron.left":arrow(true)
        case "chevron.right":arrow()
        case "plus","plus.circle.fill":line([(12,4),(12,20)]);line([(4,12),(20,12)])
        case "minus":line([(4,12),(20,12)])
        case "xmark","xmark.circle.fill":line([(5,5),(19,19)]);line([(19,5),(5,19)])
        case "checkmark","checkmark.shield":line([(4,12),(9,18),(20,5)])
        case "lock","lock.fill","lock.open","lock.shield","lock.rectangle","lock.rectangle.fill":
            box(5,10,14,11);p.move(to:.init(x:8,y:10));p.addCurve(to:.init(x:16,y:name == "lock.open" ? 5:10),control1:.init(x:6,y:-1),control2:.init(x:18,y:-1));line([(12,14),(12,17)])
        case "slider.horizontal.3":
            for (y,x) in [(6.0,8.0),(12,16),(18,10)] {line([(3,y),(x-2,y)]);line([(x+2,y),(21,y)]);circle(x,y,2)}
        case "speaker.wave.1","speaker.wave.2","speaker.slash","speaker.fill":
            line([(3,9),(7,9),(12,5),(12,19),(7,15),(3,15),(3,9)])
            if name == "speaker.slash" {line([(16,8),(22,16)]);line([(22,8),(16,16)])}
            else {p.move(to:.init(x:16,y:8));p.addQuadCurve(to:.init(x:16,y:16),control:.init(x:21,y:12));if name == "speaker.wave.2" {p.move(to:.init(x:19,y:5));p.addQuadCurve(to:.init(x:19,y:19),control:.init(x:26,y:12))}}
        case "pin","pin.slash":line([(8,3),(17,3),(15,11),(19,14),(5,14),(9,11),(8,3)]);line([(12,14),(12,22)]);if name == "pin.slash" {line([(3,3),(21,21)])}
        case "folder","folder.fill":line([(3,6),(9,6),(12,9),(21,9),(20,20),(3,20),(3,6)])
        case "doc.on.doc","square.on.square","rectangle.on.rectangle","pip":box(3,3,13,13);box(10,10,11,11)
        case "rectangle.split.2x1":box(3,4,18,16);line([(13,4),(13,20)])
        case "arrow.up.right.square":line([(4,10),(4,21),(21,21),(21,11)]);line([(11,3),(21,3),(21,13)]);line([(21,3),(9,15)])
        case "arrow.left.and.right","arrow.left.arrow.right":line([(3,12),(21,12)]);line([(8,7),(3,12),(8,17)]);line([(16,7),(21,12),(16,17)])
        case "arrow.up.left.and.arrow.down.right":line([(3,3),(9,3)]);line([(3,3),(3,9)]);line([(3,3),(10,10)]);line([(21,21),(15,21)]);line([(21,21),(21,15)]);line([(21,21),(14,14)])
        case "arrow.counterclockwise","arrow.uturn.backward":
            p.move(to:.init(x:5,y:8));p.addCurve(to:.init(x:5,y:17),control1:.init(x:25,y:-2),control2:.init(x:26,y:29));line([(5,2),(5,8),(11,8)])
        case "pencil":line([(4,16),(3,21),(8,20),(21,7),(17,3),(4,16)]);line([(14,6),(18,10)])
        case "scissors":circle(6,17,3);circle(18,17,3);line([(8,15),(20,3)]);line([(16,15),(4,3)])
        case "trash":line([(4,6),(20,6)]);line([(9,6),(9,3),(15,3),(15,6)]);line([(6,7),(7,21),(17,21),(18,7)]);line([(10,10),(10,17)]);line([(14,10),(14,17)])
        case "waveform.path","waveform":line([(2,13),(5,9),(8,17),(11,4),(14,20),(17,8),(20,14),(22,12)])
        case "link":line([(8,16),(16,8)]);p.move(to:.init(x:9,y:7));p.addCurve(to:.init(x:17,y:15),control1:.init(x:23,y:-6),control2:.init(x:31,y:7));p.move(to:.init(x:7,y:9));p.addCurve(to:.init(x:15,y:17),control1:.init(x:-6,y:23),control2:.init(x:7,y:31))
        case "pianokeys":box(3,4,18,16);for x in [8.0,16] {line([(x,4),(x,13)])};line([(12,4),(12,20)]);line([(7,13),(7,20)]);line([(17,13),(17,20)])
        case "paintpalette":circle(12,12,9);for (x,y) in [(8.0,8.0),(15,7),(18,12)] {circle(x,y,0.9)};circle(9,16,2)
        case "plus.magnifyingglass","minus.magnifyingglass","magnifyingglass":circle(10,10,6.5);line([(15,15),(22,22)]);if name != "magnifyingglass" {line([(7,10),(13,10)])};if name == "plus.magnifyingglass" {line([(10,7),(10,13)])}
        case "iphone","iphone.and.arrow.forward":box(7,2,10,20);line([(10,5),(14,5)]);line([(11,19),(13,19)])
        case "network","network.slash","dot.radiowaves.left.and.right":
            circle(12,12,2);for x in [5.0,19.0] {p.move(to:.init(x:x,y:4));p.addQuadCurve(to:.init(x:x,y:20),control:.init(x:x<12 ? -1:25,y:12))};if name == "network.slash" {line([(3,3),(21,21)])}
        case "desktopcomputer":box(3,3,18,13);line([(12,16),(12,21)]);line([(7,21),(17,21)])
        case "exclamationmark.triangle":line([(12,3),(23,21),(1,21),(12,3)]);line([(12,9),(12,14)]);circle(12,18,0.5)
        case "square.stack.3d.up","square.3.layers.3d":line([(2,7),(12,2),(22,7),(12,12),(2,7)]);line([(3,12),(12,17),(21,12)]);line([(3,17),(12,22),(21,17)])
        default: // Uncommon system-name aliases share a recognizable hand-drawn utility mark.
            if name.contains("lock") {box(5,10,14,11);p.move(to:.init(x:8,y:10));p.addCurve(to:.init(x:16,y:10),control1:.init(x:6,y:-1),control2:.init(x:18,y:-1))}
            else if name.contains("arrow") {line([(4,12),(20,12)]);line([(14,6),(20,12),(14,18)])}
            else if name.contains("list") {for y in [6.0,12,18] {circle(3,y,0.6);line([(8,y),(21,y)])}}
            else {box(4,4,16,16);line([(8,12),(16,12)])}
        }
        return p
    }
}
struct MarkerLabel:View {
    let title:String
    let systemImage:String
    init(_ title:String,systemImage:String){self.title=title;self.systemImage=systemImage}
    var body:some View {Label {Text(title)} icon: {Image(nsImage:MarkerIcon.image(systemImage)).renderingMode(.template)}}
}
