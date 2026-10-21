import SwiftUI
import UniformTypeIdentifiers

/// Finder can supply URLs as NSURL, URL data or a URL string.
enum AudioDropURLs {
    static func decode(_ item:Any?)->URL? {
        let url:URL?
        if let value=item as? URL { url=value }
        else if let data=item as? Data { url=URL(dataRepresentation:data,relativeTo:nil) }
        else if let text=item as? String { url=text.hasPrefix("/") ? URL(fileURLWithPath:text):URL(string:text) }
        else { url=nil }
        guard let url,url.isFileURL else { return nil }
        return url.standardizedFileURL
    }
    static func resolve(_ providers:[NSItemProvider]) async->[URL] {
        var result:[URL]=[]
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url:URL?=await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { item,_ in continuation.resume(returning:decode(item)) }
            }
            if let url { result.append(url) }
        }
        return result
    }
}
final class AudioDropFeedback: ObservableObject {
    @Published var targeted=false
    @Published var message:String?
    var clearTask:Task<Void,Never>?
    func show(_ message:String){self.message=message;clearTask?.cancel();clearTask=Task { @MainActor in try? await Task.sleep(for:.seconds(4));if !Task.isCancelled { self.message=nil } }}
}
struct AudioFileDropArea:ViewModifier {
    var enabled=true
    @ObservedObject private var player=Player.shared
    @ObservedObject private var setup=SetupLock.shared
    @ObservedObject private var lock=ControlLock.shared
    @StateObject private var feedback=AudioDropFeedback()
    private var allowed:Bool { enabled && !setup.editsBlocked && !lock.isLocked }
    func body(content:Content)->some View {
        content.contentShape(Rectangle())
            .overlay { if feedback.targeted && allowed { RoundedRectangle(cornerRadius:14).fill(accent.opacity(0.12)).overlay(RoundedRectangle(cornerRadius:14).stroke(accent,lineWidth:2)).overlay { MarkerLabel("Drop audio here",systemImage:"plus.circle.fill").font(.stage(size:13,weight:.semibold)).padding(12).background(.ultraThinMaterial,in:Capsule()) }.allowsHitTesting(false) } }
            .overlay(alignment:.bottom) { if let message=feedback.message { Text(message).font(.stage(size:11,weight:.medium)).multilineTextAlignment(.center).padding(9).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:9)).padding(8).allowsHitTesting(false) } }
            .onDrop(of:[UTType.fileURL],isTargeted:$feedback.targeted) { providers in
                guard allowed else { return false }
                Task {
                    let urls=await AudioDropURLs.resolve(providers)
                    await MainActor.run {
                        guard allowed else { return }
                        let before=player.tracks.count;player.add(urls);let count=player.tracks.count-before
                        feedback.show(count>0 ? "Added \(count) \(count==1 ? "track":"tracks")":"No new audio files to add")
                    }
                }
                return !providers.isEmpty
            }
    }
}
extension View { func audioFileDrop(enabled:Bool=true)->some View { modifier(AudioFileDropArea(enabled:enabled)) } }
