import SwiftUI
import UniformTypeIdentifiers

/// Private, in-process payload: never confused with audio files dropped from Finder.
enum QueueDrag {
    static let type=UTType(exportedAs:"local.hardplay.queue-item",conformingTo:.data)
    static func provider(_ id:String)->NSItemProvider {
        let provider=NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier:type.identifier,visibility:.ownProcess) {completion in completion(Data(id.utf8),nil);return nil}
        return provider
    }
}
struct QueueRowDrop:DropDelegate {
    let player:Player
    let target:String
    @Binding var targeted:Bool
    @Binding var after:Bool
    var midpoint:CGFloat=26
    func validateDrop(info:DropInfo)->Bool {!SetupLock.shared.editsBlocked && !ControlLock.shared.isLocked && info.hasItemsConforming(to:[QueueDrag.type.identifier])}
    func dropEntered(info:DropInfo) {targeted=validateDrop(info:info);after=info.location.y>midpoint}
    func dropUpdated(info:DropInfo)->DropProposal? {after=info.location.y>midpoint;return DropProposal(operation:validateDrop(info:info) ? .move:.forbidden)}
    func dropExited(info:DropInfo) {targeted=false}
    func performDrop(info:DropInfo)->Bool {
        targeted=false
        guard validateDrop(info:info),let provider=info.itemProviders(for:[QueueDrag.type.identifier]).first else {return false}
        let insertAfter=info.location.y>midpoint
        provider.loadDataRepresentation(forTypeIdentifier:QueueDrag.type.identifier) {data,_ in
            guard let data,data.count<=4096,let id=String(data:data,encoding:.utf8) else {return}
            DispatchQueue.main.async {_ = player.moveTrack(id,relativeTo:target,after:insertAfter)}
        };return true
    }
}
