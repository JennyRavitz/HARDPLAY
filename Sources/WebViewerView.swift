import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

struct WebViewerView:View {
    var embedded=false
    @ObservedObject private var viewer=WebViewer.shared
    @ObservedObject private var setup=SetupLock.shared
    @ObservedObject private var lock=ControlLock.shared
    private var blocked:Bool {setup.settingsBlocked || lock.isLocked}
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:16) {
            MarkerLabel("Web Viewer",systemImage:"iphone.and.arrow.forward").font(.stage(.title2).bold())
            Text("Your live set, on another screen.").foregroundStyle(.secondary)
            MarkerLabel(viewer.status,systemImage:viewer.running ? "dot.radiowaves.left.and.right":"network.slash").font(.stage(.callout)).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(accent.opacity(0.12),in:RoundedRectangle(cornerRadius:12))
            HStack {Button(viewer.running ? "Stop Sharing":"Start Web Viewer") {if viewer.running {viewer.stop()}else {viewer.start()}}.buttonStyle(.borderedProminent).disabled(blocked);Spacer()}
            if let link=viewer.link {
                if viewer.addresses.count>1 {Picker("Network address",selection:$viewer.address) {ForEach(viewer.addresses,id:\.self) {Text($0).tag($0)}}.disabled(blocked)}
                if let image=qr(link.absoluteString) {HStack {Spacer();Image(nsImage:image).interpolation(.none).resizable().frame(width:210,height:210).padding(12).background(.white,in:RoundedRectangle(cornerRadius:14)).accessibilityLabel("Scan QR code to open live playlist viewer");Spacer()}}
                HStack {Button("Copy Link") {NSPasteboard.general.clearContents();NSPasteboard.general.setString(link.absoluteString,forType:.string)};Button("Open Viewer") {NSWorkspace.shared.open(link)}}.disabled(blocked)
                Text("\(link.host ?? ""):\(String(viewer.port))").font(.stage(.caption,design:.monospaced)).textSelection(.enabled)
                Text("Scan with your phone on the same Wi-Fi or open the copied link on another computer. If a VPN or guest network blocks devices, use the same local network.").font(.stage(.callout)).foregroundStyle(.secondary)
            }
            Divider()
            Text("Current track · time remaining · next track · queue · crossfade status").font(.stage(.callout))
            Text("View only. Audio stays on this Mac. Anyone with this session link can view the set while sharing is on. Stop Sharing revokes the link; each new session creates a new link.").font(.stage(.caption)).foregroundStyle(.secondary)
            Text("Local HTTP connection: use a trusted Wi-Fi or Ethernet network. This is not internet or cloud sharing. Keep HARDPLAY and the Mac awake during the show.").font(.stage(.caption)).foregroundStyle(.secondary)
        }.padding(22)}.frame(minWidth:380,minHeight:embedded ? 300:500)
    }
    private func qr(_ text:String)->NSImage? {let filter=CIFilter.qrCodeGenerator();filter.message=Data(text.utf8);guard let output=filter.outputImage,let image=CIContext().createCGImage(output,from:output.extent) else {return nil};return NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))}
}
