import SwiftUI
import AppKit

struct StageTheme: Codable {
    var preset = "Tape Blue"
    var accent = "93C5F4"
    var background = "20252D"
    var text = "F2F3F6"
    var tape = "ADC9E4"
    var opacity = 0.88
    var buttonSize = 60.0
    var textScale = 1.0
    var spacing = 14.0
    var radius = 12.0
    var texture = true
    static let names = ["Tape Blue", "Tape White", "Tape Black", "Speaker Grille", "Road Case", "Stage", "Flightcase", "Cables", "Cinema", "Theatre", "Minimal"]
    static func named(_ name: String) -> StageTheme {
        var t = StageTheme(); t.preset = name
        switch name {
        case "Tape Blue": t.tape="ADC9E4";t.accent="ADC9E4";t.radius=6
        case "Tape White": t.tape="E9E5D9";t.accent="E9E5D9";t.radius=6
        case "Tape Black": t.tape="15181D";t.accent="C5D2E2";t.radius=6
        case "Speaker Grille": t.background="171D24";t.accent="9EBED6";t.tape="B7CAD4";t.radius=5;t.opacity=0.97;t.spacing=12
        case "Road Case": t.background="20252B";t.accent="BFCCD9";t.tape="D7C79E";t.radius=4;t.opacity=0.96;t.spacing=12
        case "Stage": t.background="27374B";t.tape="C8C8FB"
        case "Flightcase": t.background = "252C35"; t.accent = "BDD9ED"; t.tape = "EBCB89"; t.radius = 5
        case "Cables": t.background = "122C38"; t.accent = "7DDAEB"; t.tape = "E8BC95"; t.radius = 18
        case "Cinema": t.background = "151925"; t.accent = "E6BD83"; t.tape = "C4CBDD"; t.radius = 8
        case "Theatre": t.background = "381F32"; t.accent = "E6B6B7"; t.tape = "E6CEA2"; t.radius = 16
        case "Minimal": t.background = "1D293A"; t.accent = "A9CFF7"; t.texture = false; t.opacity = 0.82
        default: break
        }
        return t
    }
}
final class AppearancePreferences: ObservableObject {
    static let shared = AppearancePreferences()
    @Published var theme: StageTheme { didSet { if let data = try? JSONEncoder().encode(theme) { UserDefaults.standard.set(data, forKey:"stageAppearance.v1") } } }
    init() {
        let defaults=UserDefaults.standard
        let prior=defaults.data(forKey:"stageAppearance.v1")
        if !defaults.bool(forKey:"markerStyle.v1") {
            if let prior {defaults.set(prior,forKey:"stageAppearance.beforeMarker.v1")}
            theme = .named("Tape Blue");defaults.set(true,forKey:"markerStyle.v1")
            if let data=try? JSONEncoder().encode(theme) {defaults.set(data,forKey:"stageAppearance.v1")}
        } else {theme=prior.flatMap {try? JSONDecoder().decode(StageTheme.self,from:$0)} ?? .named("Tape Blue")}
    }
    func color(_ key: WritableKeyPath<StageTheme,String>) -> Binding<Color> {
        Binding(get:{ Color(stageHex:self.theme[keyPath:key]) },set:{ color in
            guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
            self.theme[keyPath:key] = String(format:"%02X%02X%02X",Int(c.redComponent*255),Int(c.greenComponent*255),Int(c.blueComponent*255))
        })
    }
}
extension Color {
    init(stageHex: String) {
        let value = UInt64(stageHex,radix:16) ?? 0x93C5F4
        self.init(red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255)
    }
}
struct ThemedBackdrop: View {
    @ObservedObject var appearance = AppearancePreferences.shared
    var body: some View {
        let t = appearance.theme
        GlassBackdrop().overlay(Color(stageHex:t.background).opacity(t.opacity))
            .overlay {
                if t.texture {
                    Canvas { ctx,size in
                        let color = Color(stageHex:t.accent).opacity(0.055)
                        switch t.preset {
                        case "Speaker Grille":
                            for row in 0...Int(size.height/9) {
                                for x in stride(from:row%2 == 0 ? 3.0:7.5,to:size.width,by:9) {
                                    let y=CGFloat(row)*9
                                    ctx.fill(Path(ellipseIn:CGRect(x:x,y:y+0.7,width:4.6,height:4.6)),with:.color(.white.opacity(0.065)))
                                    ctx.fill(Path(ellipseIn:CGRect(x:x,y:y,width:4.6,height:4.6)),with:.color(.black.opacity(0.5)))
                                }
                            }
                        case "Road Case", "Flightcase":
                            for y in stride(from:0.0,to:size.height,by:7) {
                                var p=Path();p.move(to:.init(x:0,y:y));p.addLine(to:.init(x:size.width,y:y+size.width*0.12));ctx.stroke(p,with:.color(.white.opacity(0.025)),lineWidth:0.6)
                            }
                            let rail=CGRect(x:6,y:6,width:max(0,size.width-12),height:max(0,size.height-12))
                            ctx.stroke(Path(roundedRect:rail,cornerRadius:11),with:.color(Color(stageHex:"7F8993").opacity(0.55)),lineWidth:7)
                            ctx.stroke(Path(roundedRect:rail.insetBy(dx:4,dy:4),cornerRadius:8),with:.color(.black.opacity(0.7)),lineWidth:1)
                            for x in [12.0,size.width-12] {for y in [12.0,size.height-12] {
                                ctx.fill(Path(ellipseIn:CGRect(x:x-2.2,y:y-2.2,width:4.4,height:4.4)),with:.color(.white.opacity(0.5)))
                                var screw=Path();screw.move(to:.init(x:x-1,y:y));screw.addLine(to:.init(x:x+1,y:y));ctx.stroke(screw,with:.color(.black.opacity(0.7)),lineWidth:0.7)
                            }}
                        case "Tape Blue", "Tape White", "Tape Black":
                            for x in stride(from:8.0,to:size.width,by:24) { for y in stride(from:8.0,to:size.height,by:24) { ctx.fill(Path(ellipseIn:CGRect(x:x,y:y,width:2,height:2)),with:.color(color)) } }
                        case "Cables":
                            for i in 0..<7 { var p=Path(); let y=CGFloat(i)*110; p.move(to:CGPoint(x:0,y:y)); p.addCurve(to:CGPoint(x:size.width,y:y+90),control1:CGPoint(x:size.width*0.65,y:y-80),control2:CGPoint(x:size.width*0.3,y:y+190)); ctx.stroke(p,with:.color(color),lineWidth:3) }
                        case "Cinema":
                            for y in stride(from:14.0,to:size.height,by:28) { for x in [5.0,size.width-12] { ctx.fill(Path(roundedRect:CGRect(x:x,y:y,width:7,height:12),cornerRadius:2),with:.color(color)) } }
                        case "Theatre":
                            for x in stride(from:0.0,to:size.width,by:20) { ctx.fill(Path(CGRect(x:x,y:0,width:8,height:size.height)),with:.color(color)) }
                        case "Stage":
                            var p=Path(); for y in stride(from:0.0,to:size.height,by:70) { p.move(to:CGPoint(x:0,y:y));p.addLine(to:CGPoint(x:size.width,y:y)) };ctx.stroke(p,with:.color(color),lineWidth:1)
                        default: break
                        }
                    }.allowsHitTesting(false)
                }
            }
    }
}
struct ThemeEditorView: View {
    @ObservedObject var appearance = AppearancePreferences.shared
    @ObservedObject var setup = SetupLock.shared
    @ObservedObject var lock = ControlLock.shared
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Themes & Appearance").font(.stage(.title2).bold())
                Text("Marker lettering · refined tape · speaker grille and road-case hardware. Live preview stays in the player.").font(.stage(.callout)).foregroundStyle(.secondary)
                HStack {HardPlayShieldWordmark();Spacer();HardPlayWordmark(layout:.stacked)}
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                    ForEach(StageTheme.names,id:\.self) { name in
                        Button { appearance.theme = .named(name) } label: {
                            HStack { Circle().fill(Color(stageHex:StageTheme.named(name).accent)).frame(width:12,height:12);Text(name);Spacer();if appearance.theme.preset == name { MarkerIcon(systemName:"checkmark") } }.padding(9)
                        }.buttonStyle(PlayerControlStyle(active:appearance.theme.preset == name))
                    }
                }
                Divider()
                ColorPicker("Accent",selection:appearance.color(\.accent),supportsOpacity:false)
                ColorPicker("Background",selection:appearance.color(\.background),supportsOpacity:false)
                ColorPicker("Text",selection:appearance.color(\.text),supportsOpacity:false)
                ColorPicker("Playlist tape",selection:appearance.color(\.tape),supportsOpacity:false)
                adjustment("Background opacity",value:$appearance.theme.opacity,range:0.25...1,suffix:"%",factor:100)
                adjustment("Play button",value:$appearance.theme.buttonSize,range:48...90,suffix:" px")
                adjustment("Track text",value:$appearance.theme.textScale,range:0.9...1.5,suffix:"%",factor:100)
                adjustment("Spacing",value:$appearance.theme.spacing,range:8...22,suffix:" px")
                adjustment("Corner radius",value:$appearance.theme.radius,range:0...24,suffix:" px")
                Toggle("Scenic texture",isOn:$appearance.theme.texture)
                Button("Reset to Tape Blue") { appearance.theme = .named("Tape Blue") }.buttonStyle(.bordered)
                Text("Saved automatically on this Mac.").font(.stage(.caption)).foregroundStyle(.secondary)
            }.padding(22).disabled(setup.settingsBlocked || lock.isLocked)
        }.frame(minWidth:360,minHeight:500).foregroundStyle(Color(stageHex:appearance.theme.text))
    }
    private func adjustment(_ title:String,value:Binding<Double>,range:ClosedRange<Double>,suffix:String,factor:Double=1)->some View {
        VStack(spacing:5) { HStack { Text(title);Spacer();Text("\(Int(value.wrappedValue*factor))\(suffix)").monospacedDigit().foregroundStyle(.secondary) };Slider(value:value,in:range).tint(accent).accessibilityLabel(title) }
    }
}
