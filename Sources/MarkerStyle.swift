import SwiftUI
import AppKit
import CoreText

/// Bundled, process-scoped typeface: never installs fonts on the user's Mac.
enum StageTypography {
    static let name:String = {
        guard let url=Bundle.main.url(forResource:"BalsamiqSans-Bold",withExtension:"ttf") else {return "MarkerFelt-Wide"}
        CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
        if let descriptors=CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],let descriptor=descriptors.first,
           let name=CTFontDescriptorCopyAttribute(descriptor,kCTFontNameAttribute) as? String {return name}
        return "BalsamiqSans-Bold"
    }()
    static func native(_ size:CGFloat)->NSFont {NSFont(name:name,size:size) ?? NSFont(name:"MarkerFelt-Wide",size:size) ?? .systemFont(ofSize:size)}
}
extension Font {
    static func stage(size:CGFloat,weight:Font.Weight = .regular,design:Font.Design = .default)->Font {.custom(StageTypography.name,size:size)}
    static func stage(_ style:Font.TextStyle,design:Font.Design = .default)->Font {
        let size:CGFloat
        switch style {case .largeTitle:size=28;case .title:size=24;case .title2:size=20;case .title3:size=17;case .headline:size=14;case .subheadline:size=12;case .callout:size=13;case .caption:size=11;case .caption2:size=10;case .footnote:size=11;default:size=14}
        return .custom(StageTypography.name,size:size)
    }
}

/// Low-contrast fabric grain; deterministic and passive, with no texture files or animation.
struct TapeGrain:View {
    var body:some View {Canvas {context,size in
        for y in stride(from:2.0,to:size.height,by:1.9) {
            var p=Path();p.move(to:.init(x:1,y:y));p.addLine(to:.init(x:size.width-1,y:y+0.5));context.stroke(p,with:.color(.white.opacity(0.025)),lineWidth:0.5)
        }
        for x in stride(from:2.0,to:size.width,by:2.4) {
            var p=Path();p.move(to:.init(x:x,y:1));p.addLine(to:.init(x:x+0.6,y:size.height-1));context.stroke(p,with:.color(.black.opacity(0.02)),lineWidth:0.5)
        }
    }.allowsHitTesting(false)}
}
var tapeInk:Color {
    let hex=UInt64(AppearancePreferences.shared.theme.tape,radix:16) ?? 0xADC9E4
    let light=(0.2126*Double((hex>>16)&255)+0.7152*Double((hex>>8)&255)+0.0722*Double(hex&255))/255
    return Color(stageHex:light<0.48 ? "F3EFE6":"171B20")
}
struct TapeSurface:View {
    @ObservedObject private var appearance=AppearancePreferences.shared
    var body:some View {TapeEdge().fill(tapeB).overlay(TapeGrain().clipShape(TapeEdge())).overlay(TapeEdge().stroke(.white.opacity(0.2),lineWidth:0.7)).shadow(color:.black.opacity(0.15),radius:1,y:1)}
}
enum WordmarkLayout {case horizontal,stacked}
struct HardPlayWordmark:View {
    @ObservedObject private var appearance=AppearancePreferences.shared
    var layout:WordmarkLayout = .horizontal
    var body:some View {
        Group {
            if layout == .horizontal {Text("HARDPLAY").font(.stage(size:17)).fixedSize()}
            else {VStack(alignment:.leading,spacing:-2) {Text("HARD");Text("PLAY")}.font(.stage(size:16))}
        }.foregroundStyle(tapeInk).padding(.horizontal,10).padding(.vertical,5).background(TapeSurface()).accessibilityLabel("HARDPLAY")
    }
}

/// A compact stamped equipment badge; the wordmark stays separate from the app icon.
struct StageShield:Shape {
    func path(in r:CGRect)->Path {
        var p=Path();let points:[CGPoint]=[.init(x:0,y:5),.init(x:8,y:0),.init(x:r.width-8,y:0),.init(x:r.width,y:5),.init(x:r.width-3,y:r.height-9),.init(x:r.midX,y:r.height),.init(x:3,y:r.height-9)]
        p.addLines(points);p.closeSubpath();return p
    }
}
struct HardPlayShieldWordmark:View {
    @ObservedObject private var appearance=AppearancePreferences.shared
    var body:some View {
        Text("HARDPLAY").font(.stage(size:18)).tracking(0.4).foregroundStyle(Color(stageHex:appearance.theme.text))
            .padding(.bottom,4).frame(width:132,height:42)
            .background(LinearGradient(colors:[Color(stageHex:"39434E"),Color(stageHex:"161C23")],startPoint:.top,endPoint:.bottom),in:StageShield())
            .overlay(StageShield().stroke(LinearGradient(colors:[accent.opacity(0.9),.white.opacity(0.18),accent.opacity(0.35)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1.3))
            .overlay(alignment:.leading){Circle().fill(.white.opacity(0.35)).frame(width:2,height:2).padding(.leading,5)}
            .overlay(alignment:.trailing){Circle().fill(.white.opacity(0.35)).frame(width:2,height:2).padding(.trailing,5)}
            .shadow(color:.black.opacity(0.3),radius:2,y:2).accessibilityLabel("HARDPLAY")
    }
}

/// Compact marker label: one bundled 75 KB font, no image or animation.
enum CrewMarker {
    static let name:String = {
        guard let url=Bundle.main.url(forResource:"PermanentMarker-Regular",withExtension:"ttf") else {return StageTypography.name}
        CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
        return "PermanentMarker-Regular"
    }()
}
struct MiniStageLabel:View {
    var body:some View {
        HStack(spacing:8) {
            MarkerIcon(systemName:"player.mini",size:19)
            VStack(alignment:.leading,spacing:-3) {
                Text("mini").font(.custom(CrewMarker.name,size:11))
                Text("hardplay").font(.custom(CrewMarker.name,size:18))
            }
        }.foregroundStyle(tapeInk).padding(.horizontal,10).frame(height:40).background(TapeSurface())
    }
}
