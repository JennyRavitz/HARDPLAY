import Foundation
import AVFoundation

struct ClipRange:Equatable {
    let start:Double
    let end:Double
    var duration:Double {end-start}
    var valid:Bool {start.isFinite && end.isFinite && start>=0 && end>start}
    static func parse(_ text:String)->Double? {
        let parts=text.trimmingCharacters(in:.whitespacesAndNewlines).split(separator:":",omittingEmptySubsequences:false)
        guard (1...3).contains(parts.count) else {return nil}
        var total=0.0
        for (i,part) in parts.enumerated() {guard let value=Double(part.replacingOccurrences(of:",",with:".")),value.isFinite,value>=0,(i == 0 || value<60) else {return nil};total=total*60+value}
        return total
    }
    static func preciseLabel(_ value:Double)->String {let n=max(0,value);return String(format:"%d:%09.6f",Int(n)/60,n.truncatingRemainder(dividingBy:60))}
    static func label(_ value:Double)->String {let n=max(0,value);return String(format:"%d:%06.3f",Int(n)/60,n.truncatingRemainder(dividingBy:60))}
}
enum ClipExport {
    struct Info {let duration:Double;let sampleRate:Double;let channels:UInt32}
    static func inspect(_ url:URL)throws->Info {
        let scoped=url.startAccessingSecurityScopedResource();defer {if scoped {url.stopAccessingSecurityScopedResource()}}
        let file=try AVAudioFile(forReading:url)
        guard file.length>0,file.processingFormat.sampleRate.isFinite,file.processingFormat.sampleRate>0 else {throw BackupFailure("This file has no readable audio.")}
        return Info(duration:Double(file.length)/file.processingFormat.sampleRate,sampleRate:file.processingFormat.sampleRate,channels:file.processingFormat.channelCount)
    }
    static func write(source:URL,range:ClipRange,to destination:URL,progress:@escaping @Sendable (Double)->Void = {_ in})throws {try write(source:source,ranges:[range],to:destination,progress:progress)}
    static func write(source:URL,ranges:[ClipRange],to destination:URL,progress:@escaping @Sendable (Double)->Void = {_ in})throws {
        guard !ranges.isEmpty,ranges.count<=10000,ranges.allSatisfy(\.valid),source.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath() else {throw BackupFailure("Choose a new WAV file. The original audio is preserved.")}
        let fm=FileManager.default
        guard !fm.fileExists(atPath:destination.path) else {throw BackupFailure("Choose a new filename; existing audio is never overwritten.")}
        let scoped=source.startAccessingSecurityScopedResource();defer {if scoped {source.stopAccessingSecurityScopedResource()}}
        let before=try fm.attributesOfItem(atPath:source.path)
        let input=try AVAudioFile(forReading:source);let format=input.processingFormat;let rate=format.sampleRate
        guard rate.isFinite,rate>0,ranges.allSatisfy({$0.end<=Double(input.length)/rate+0.5/rate}) else {throw BackupFailure("The selected range is outside this audio file.")}
        let ordered=ranges.sorted {$0.start<$1.start}
        guard zip(ordered,ordered.dropFirst()).allSatisfy({$0.end<=$1.start}) else {throw BackupFailure("Selected fragments overlap.")}
        let intervals=ordered.map {(first:AVAudioFramePosition(($0.start*rate).rounded()),last:min(input.length,AVAudioFramePosition(($0.end*rate).rounded())))}
        guard intervals.allSatisfy({$0.first>=0 && $0.last>$0.first}) else {throw BackupFailure("Select at least one audio sample per fragment.")}
        let total=intervals.reduce(Int64(0)) {$0+$1.last-$1.first}
        let temporary=destination.deletingLastPathComponent().appendingPathComponent(".hardplay-edit-\(UUID().uuidString).wav")
        defer {try? fm.removeItem(at:temporary)}
        let settings:[String:Any]=[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:rate,AVNumberOfChannelsKey:format.channelCount,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsBigEndianKey:false,AVLinearPCMIsNonInterleaved:false]
        do {
            let output=try AVAudioFile(forWriting:temporary,settings:settings,commonFormat:format.commonFormat,interleaved:format.isInterleaved)
            guard let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:8192) else {throw BackupFailure("Cannot allocate an audio buffer.")}
            var copied:Int64=0
            for interval in intervals {
                input.framePosition=interval.first;var remaining=interval.last-interval.first
                while remaining>0 {
                    try Task.checkCancellation()
                    try input.read(into:buffer,frameCount:AVAudioFrameCount(min(8192,remaining)))
                    guard buffer.frameLength>0 else {throw BackupFailure("Audio ended before the selected out point.")}
                    try output.write(from:buffer);remaining -= AVAudioFramePosition(buffer.frameLength);copied += Int64(buffer.frameLength)
                    progress(Double(copied)/Double(total))
                }
            }

        }
        let after=try fm.attributesOfItem(atPath:source.path)
        guard (before[.size] as? NSNumber) == (after[.size] as? NSNumber),(before[.modificationDate] as? Date) == (after[.modificationDate] as? Date) else {throw BackupFailure("The original file changed during editing. Open it again.")}
        let check=try AVAudioFile(forReading:temporary)
        guard check.length == total else {throw BackupFailure("The exported audio length could not be verified.")}
        try Task.checkCancellation();try fm.moveItem(at:temporary,to:destination)
    }
}

/// A bounded envelope for the visible timeline; zooming requests real source samples again.
enum EditorWaveform {
    static func peaks(url:URL,range:ClipRange,bins:Int=2048)throws->[Double] {
        guard range.valid,(16...8192).contains(bins) else {return []}
        let scoped=url.startAccessingSecurityScopedResource();defer {if scoped {url.stopAccessingSecurityScopedResource()}}
        let file=try AVAudioFile(forReading:url);let rate=file.processingFormat.sampleRate
        let first=max(0,AVAudioFramePosition((range.start*rate).rounded())),last=min(file.length,AVAudioFramePosition((range.end*rate).rounded()))
        guard last>first,let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:32768) else {return []}
        file.framePosition=first;var done:AVAudioFramePosition=0;let total=last-first;var peaks=[Double](repeating:0,count:bins)
        let strideSize=max(1,Int(total)/max(1,bins*16))
        while done<total {
            try Task.checkCancellation();try file.read(into:buffer,frameCount:AVAudioFrameCount(min(32768,total-done)))
            guard buffer.frameLength>0,let channels=buffer.floatChannelData else {break}
            for frame in stride(from:0,to:Int(buffer.frameLength),by:strideSize) {
                let index=min(bins-1,Int(Double(done+Int64(frame))/Double(total)*Double(bins)))
                var peak=0.0
                for channel in 0..<Int(buffer.format.channelCount) {peak=max(peak,Double(abs(channels[channel][frame])))}
                if peak.isFinite {peaks[index]=max(peaks[index],peak)}
            }
            done += Int64(buffer.frameLength)
        }
        return peaks.map {min(1,pow($0,0.65))}
    }
}

struct TimelineViewport:Equatable {
    var duration:Double
    var zoom:Double=1
    var start:Double=0
    var length:Double {duration>0 ? duration/max(1,zoom):0}
    mutating func setZoom(_ value:Double,anchorFraction:Double=0.5) {
        guard duration.isFinite,duration>0,value.isFinite else {return}
        let fraction=min(1,max(0,anchorFraction)),anchor=start+length*fraction
        zoom=min(256,max(1,value));start=min(max(0,anchor-length*fraction),max(0,duration-length))
    }
    mutating func pan(_ value:Double){guard value.isFinite else {return};start=min(max(0,value),max(0,duration-length))}
    func time(at fraction:Double)->Double {min(duration,max(0,start+min(1,max(0,fraction))*length))}
}

struct EditorClip:Identifiable,Equatable {
    let id:UUID
    var range:ClipRange
    init(id:UUID=UUID(),range:ClipRange){self.id=id;self.range=range}
}
struct EditorClipSelection {
    var clips:[EditorClip]=[]
    var selected:Set<UUID>=[]
    var ranges:[ClipRange] {clips.filter {selected.contains($0.id)}.map(\.range).sorted {$0.start<$1.start}}
    mutating func cut(at time:Double) {
        guard time.isFinite,let index=clips.firstIndex(where:{$0.range.start<time && time<$0.range.end}) else {return}
        let old=clips[index],right=EditorClip(range:.init(start:time,end:old.range.end))
        clips[index].range=ClipRange(start:old.range.start,end:time);clips.insert(right,at:index+1)
        if selected.contains(old.id) {selected.insert(right.id)}
    }
    mutating func select(_ range:ClipRange,add:Bool) {
        guard range.valid else {return};cut(at:range.start);cut(at:range.end)
        let ids=Set(clips.filter {$0.range.start>=range.start-0.0000001 && $0.range.end<=range.end+0.0000001}.map(\.id))
        if add {selected.formUnion(ids)}else {selected=ids}
    }
    mutating func choose(at time:Double,add:Bool)->ClipRange? {
        guard let clip=clips.first(where:{$0.range.start<=time && (time<$0.range.end || (time == $0.range.end && $0.id == clips.last?.id))}) else {return nil}
        if add {if selected.contains(clip.id) {selected.remove(clip.id)}else {selected.insert(clip.id)}}else {selected=[clip.id]}
        return clip.range
    }
}
