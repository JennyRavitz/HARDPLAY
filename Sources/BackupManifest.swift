import Foundation
import CryptoKit
import AVFoundation

struct BackupSetInput {
    struct Item { let url:URL; let title:String; let occurrenceID:String?; let fade:FadeMode; let position:Double }
    let name:String
    let items:[Item]
    let options:SavedPlaylist.Options
    var signature:String {
        let rows=items.map { [$0.url.path,$0.title,$0.occurrenceID ?? "",$0.fade.rawValue,String(options.startMode == .resume ? $0.position:0)].joined(separator:"\u{0}") }
        return ([name,options.startMode.rawValue,options.endMode.rawValue,String(options.stopBeforeEnd),String(options.shuffle),String(options.repeatAll)]+rows).joined(separator:"\u{1}")
    }
}

struct BackupManifest:Codable,Equatable {
    struct Entry:Codable,Equatable {
        let title:String
        let sha256:String
        let bytes:Int64
        let durationMS:Int64
        let fade:String
        let positionMS:Int64
    }
    let version:Int
    let name:String
    let entries:[Entry]
    let start:String
    let end:String
    let stopBeforeMS:Int64
    let shuffle:Bool
    let repeatAll:Bool
    var valid:Bool {
        version == 1 && !entries.isEmpty && entries.count <= 10000 && name.utf8.count <= 1000 &&
        ["beginning","resume"].contains(start) && ["next","stop"].contains(end) && (0...30000).contains(stopBeforeMS) &&
        entries.allSatisfy { $0.title.utf8.count <= 4096 && $0.sha256.count == 64 && $0.sha256.allSatisfy { "0123456789abcdef".contains($0) } && $0.bytes>0 && $0.durationMS>0 && $0.positionMS>=0 && $0.positionMS<=$0.durationMS && ["none","short","long"].contains($0.fade) }
    }
    func differences(from other:Self)->[String] {
        guard valid && other.valid else {return ["Invalid or unsupported set manifest"]}
        var result:[String]=[]
        if entries.count != other.entries.count {result.append("Track count: \(entries.count) / \(other.entries.count)")}
        if start != other.start {result.append("On Play mode differs")}
        if end != other.end || stopBeforeMS != other.stopBeforeMS {result.append("Auto Stop settings differ")}
        if shuffle != other.shuffle || repeatAll != other.repeatAll {result.append("Shuffle / Repeat settings differ")}
        for (i,pair) in zip(entries,other.entries).enumerated() {
            let (a,b)=pair;let prefix=String(format:"Track %02d",i+1)
            if a.sha256 != b.sha256 || a.bytes != b.bytes {result.append("\(prefix) — different audio / order")}
            else if a.durationMS != b.durationMS {result.append("\(prefix) — decoded duration differs")}
            if a.fade != b.fade {result.append("\(prefix) — fade differs")}
            if a.positionMS != b.positionMS {result.append("\(prefix) — resume position differs")}
        }
        return result
    }
    static func hashFile(_ url:URL)throws->(String,Int64) {
        let before=try FileManager.default.attributesOfItem(atPath:url.path)
        guard before[.type] as? FileAttributeType == .typeRegular else {throw BackupFailure("Not a regular audio file: \(url.lastPathComponent)")}
        let handle=try FileHandle(forReadingFrom:url);defer {try? handle.close()}
        var hash=SHA256();var size:Int64=0
        while let chunk=try handle.read(upToCount:1_048_576),!chunk.isEmpty {try Task.checkCancellation();size += Int64(chunk.count);hash.update(data:chunk)}
        let after=try FileManager.default.attributesOfItem(atPath:url.path)
        guard size>0,(before[.size] as? NSNumber) == (after[.size] as? NSNumber),(before[.modificationDate] as? Date) == (after[.modificationDate] as? Date),(after[.size] as? NSNumber)?.int64Value == size else {throw BackupFailure("Empty or changing file: \(url.lastPathComponent)")}
        return (hash.finalize().map {String(format:"%02x",$0)}.joined(),size)
    }
    static func build(_ input:BackupSetInput,progress:@escaping @Sendable (String)->Void = {_ in}) async throws->Self {
        guard !input.items.isEmpty,input.items.count<=10000 else {throw BackupFailure("Add audio to the set first (maximum 10,000 tracks).")}
        guard input.options.stopBeforeEnd.isFinite,(0...30).contains(input.options.stopBeforeEnd),input.items.allSatisfy({$0.position.isFinite && $0.position>=0}) else {throw BackupFailure("Invalid set positions or Auto Stop settings.")}
        var entries:[Entry]=[];var cache:[URL:Entry]=[:]
        for (i,item) in input.items.enumerated() {
            try Task.checkCancellation();progress("Checking \(i+1) / \(input.items.count) · \(item.title)")
            let access=item.url.startAccessingSecurityScopedResource();defer {if access {item.url.stopAccessingSecurityScopedResource()}}
            let audio:Entry
            if let cached=cache[item.url] {audio=cached}
            else {
                let (hash,size)=try hashFile(item.url)
                let asset=AVURLAsset(url:item.url)
                guard let track=try await asset.loadTracks(withMediaType:.audio).first else {throw BackupFailure("No audio track: \(item.title)")}
                let seconds=try await asset.load(.duration).seconds
                let reader=try AVAssetReader(asset:asset)
                let output=AVAssetReaderTrackOutput(track:track,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM])
                guard reader.canAdd(output) else {throw BackupFailure("Cannot decode: \(item.title)")}
                reader.add(output)
                guard reader.startReading(),output.copyNextSampleBuffer() != nil,seconds.isFinite,seconds>0 else {throw BackupFailure("Cannot decode: \(item.title)")}
                reader.cancelReading()
                audio=Entry(title:item.title,sha256:hash,bytes:size,durationMS:Int64((seconds*1000).rounded()),fade:item.fade.rawValue,positionMS:0);cache[item.url]=audio
            }
            let position=input.options.startMode == .resume ? min(max(0,item.position),Double(audio.durationMS)/1000):0
            entries.append(Entry(title:item.title,sha256:audio.sha256,bytes:audio.bytes,durationMS:audio.durationMS,fade:item.fade.rawValue,positionMS:Int64((position*1000).rounded())))
        }
        let result=Self(version:1,name:input.name,entries:entries,start:input.options.startMode.rawValue,end:input.options.endMode.rawValue,stopBeforeMS:Int64((input.options.stopBeforeEnd*1000).rounded()),shuffle:input.options.shuffle,repeatAll:input.options.repeatAll)
        guard result.valid else {throw BackupFailure("The set contains invalid settings.")};return result
    }
}
struct BackupFailure:LocalizedError {let message:String;init(_ message:String){self.message=message};var errorDescription:String?{message}}

extension Player {
    func backupInput()->BackupSetInput {
        BackupSetInput(name:playlistName,items:tracks.map {.init(url:$0.url,title:$0.title,occurrenceID:$0.occurrenceID,fade:fadeMode(after:$0),position:backupPosition($0))},options:.init(startMode:startMode,endMode:endMode,stopBeforeEnd:stopBeforeEnd,shuffle:shuffle,repeatAll:repeatAll))
    }
}
