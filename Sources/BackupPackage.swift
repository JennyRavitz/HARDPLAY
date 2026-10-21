import Foundation

/// Produces a new self-contained directory, never overwrites the destination or source audio.
enum BackupPackage {
    static func write(_ input:BackupSetInput,manifest:BackupManifest,to destination:URL)throws {
        guard manifest.valid,input.items.count == manifest.entries.count else {throw BackupFailure("Check the set before exporting.")}
        guard input.options.startMode.rawValue == manifest.start,input.options.endMode.rawValue == manifest.end,input.options.stopBeforeEnd.isFinite,(0...30).contains(input.options.stopBeforeEnd),Int64((input.options.stopBeforeEnd*1000).rounded()) == manifest.stopBeforeMS,input.options.shuffle == manifest.shuffle,input.options.repeatAll == manifest.repeatAll,zip(input.items,manifest.entries).allSatisfy({$0.fade.rawValue == $1.fade && $0.title == $1.title}) else {throw BackupFailure("Set settings changed. Check the set again.")}
        let fm=FileManager.default
        guard !fm.fileExists(atPath:destination.path) else {throw BackupFailure("That folder already exists. Choose a new name.")}
        let staging=destination.deletingLastPathComponent().appendingPathComponent(".hardplay-export-\(UUID().uuidString)",isDirectory:true)
        try fm.createDirectory(at:staging,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer {try? fm.removeItem(at:staging)}
        let audio=staging.appendingPathComponent("Audio",isDirectory:true);try fm.createDirectory(at:audio,withIntermediateDirectories:false)
        var names:[String:String]=[:];var entries:[SavedPlaylist.Entry]=[]
        for (i,item) in input.items.enumerated() {
            try Task.checkCancellation()
            let expected=manifest.entries[i]
            let filename:String
            if let existing=names[expected.sha256] {filename=existing}
            else {
                let ext=item.url.pathExtension.lowercased().filter {$0.isASCII && $0.isLetter || $0.isNumber}
                filename=expected.sha256+(ext.isEmpty ? "":"."+String(ext.prefix(10)))
                let target=audio.appendingPathComponent(filename)
                let scoped=item.url.startAccessingSecurityScopedResource();defer {if scoped {item.url.stopAccessingSecurityScopedResource()}}
                let source=try FileHandle(forReadingFrom:item.url);defer {try? source.close()}
                guard fm.createFile(atPath:target.path,contents:nil) else {throw BackupFailure("Cannot create backup audio.")}
                let output=try FileHandle(forWritingTo:target);defer {try? output.close()}
                while let bytes=try source.read(upToCount:1_048_576),!bytes.isEmpty {try Task.checkCancellation();try output.write(contentsOf:bytes)}
                try output.synchronize()
                let (hash,size)=try BackupManifest.hashFile(target)
                guard hash == expected.sha256,size == expected.bytes else {throw BackupFailure("Audio changed during export: \(item.title). Check the set again.")}
                names[expected.sha256]=filename
            }
            entries.append(.init(path:"Audio/"+filename,bookmark:nil,fade:item.fade,position:Double(expected.positionMS)/1000,title:item.title,occurrenceID:item.occurrenceID ?? UUID().uuidString))
        }
        try SavedPlaylist(name:input.name,tracks:entries,selectedIndex:entries.isEmpty ? nil:0,options:input.options).write(to:staging.appendingPathComponent("Set.hardplay"))
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(manifest).write(to:staging.appendingPathComponent("BackupManifest.json"),options:.atomic)
        try Data("HARDPLAY Backup Package\nOpen Set.hardplay on the other Mac, then run Check This Set on both Macs.\nThis package contains audio. Keep it private unless you intend to share it.\n".utf8).write(to:staging.appendingPathComponent("README.txt"))
        try Task.checkCancellation();try fm.moveItem(at:staging,to:destination)
    }
}
