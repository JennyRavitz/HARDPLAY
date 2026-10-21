import Foundation
import Network

private func silentWave()->Data {
    var d=Data()
    func text(_ s:String){d.append(Data(s.utf8))}
    func u16(_ n:UInt16){var n=n.littleEndian;withUnsafeBytes(of:&n){d.append(contentsOf:$0)}}
    func u32(_ n:UInt32){var n=n.littleEndian;withUnsafeBytes(of:&n){d.append(contentsOf:$0)}}
    text("RIFF");u32(36+96000);text("WAVEfmt ");u32(16);u16(1);u16(1);u32(48000);u32(96000);u16(2);u16(16);text("data");u32(96000);d.append(Data(count:96000));return d
}
private func expectFailure(_ operation:()async throws->Void) async throws {
    do {try await operation()}catch {return};throw BackupFailure("Expected operation to fail")
}
@MainActor func runBackupTests(network:Bool) async throws {
    let fm=FileManager.default,dir=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("hardplay-backup-test-\(UUID().uuidString)")
    try fm.createDirectory(at:dir,withIntermediateDirectories:true);defer {try? fm.removeItem(at:dir)}
    let a=dir.appendingPathComponent("Трек A.wav"),b=dir.appendingPathComponent("Other path.wav")
    try silentWave().write(to:a);try silentWave().write(to:b)
    let options=SavedPlaylist.Options(startMode:.resume,endMode:.stop,stopBeforeEnd:3,shuffle:false,repeatAll:false)
    func input(_ urls:[URL],fade:FadeMode = .short)->BackupSetInput {.init(name:"Show",items:urls.enumerated().map {.init(url:$0.element,title:"Cue \($0.offset)",occurrenceID:nil,fade:fade,position:0.25)},options:options)}
    let set=input([a,a]);let manifest=try await BackupManifest.build(set)
    let moved=try await BackupManifest.build(input([b,b]));precondition(manifest.valid && manifest.differences(from:moved).isEmpty)
    let fades=try await BackupManifest.build(input([b,b],fade:.long));precondition(manifest.differences(from:fades).count == 2)
    var bytes=silentWave();bytes[bytes.count-2]=1;try bytes.write(to:b)
    let changed=try await BackupManifest.build(input([b,b]));precondition(manifest.differences(from:changed).contains {$0.contains("different audio")})
    try await expectFailure {_ = try await BackupManifest.build(input([dir.appendingPathComponent("missing.wav")]))}
    let broken=dir.appendingPathComponent("broken.wav");try Data("no audio".utf8).write(to:broken)
    try await expectFailure {_ = try await BackupManifest.build(input([broken]))}
    try await expectFailure {_ = try await BackupManifest.build(input([dir]))}
    let package=dir.appendingPathComponent("Backup")
    try BackupPackage.write(set,manifest:manifest,to:package)
    let saved=try SavedPlaylist.read(from:package.appendingPathComponent("Set.hardplay"))
    precondition(saved.tracks.count == 2 && saved.tracks[0].occurrenceID != saved.tracks[1].occurrenceID)
    precondition(saved.tracks.allSatisfy {$0.bookmark == nil && !$0.path.hasPrefix("/")})
    let files=try fm.contentsOfDirectory(atPath:package.appendingPathComponent("Audio").path);precondition(files.count == 1)
    let packaged=BackupSetInput(name:saved.name,items:saved.tracks.map {.init(url:package.appendingPathComponent($0.path),title:$0.title ?? "",occurrenceID:$0.occurrenceID,fade:$0.fade,position:$0.position)},options:saved.options)
    let packagedManifest=try await BackupManifest.build(packaged);precondition(manifest.differences(from:packagedManifest).isEmpty)
    try await expectFailure {try BackupPackage.write(set,manifest:manifest,to:package)}
    try bytes.write(to:a)
    try await expectFailure {try BackupPackage.write(set,manifest:manifest,to:dir.appendingPathComponent("Changing"))}
    precondition(!fm.fileExists(atPath:dir.appendingPathComponent("Changing").path))
    func frame(_ p:BackupLink.Packet)throws->Data {let payload=try JSONEncoder().encode(p);var n=UInt32(payload.count).bigEndian;var d=withUnsafeBytes(of:&n){Data($0)};d.append(payload);return d}
    let packet=BackupLink.Packet(version:1,kind:"manifest",role:.primary,name:"A",manifest:manifest)
    let encoded=try frame(packet);var partial=Data(encoded.prefix(3));let empty=try BackupLink.extract(&partial);precondition(empty.isEmpty);partial.append(encoded.dropFirst(3));partial.append(encoded);let packets=try BackupLink.extract(&partial);precondition(packets.count == 2 && partial.isEmpty)
    try await expectFailure {var invalid=Data([255,255,255,255]);_ = try BackupLink.extract(&invalid)}
    try await expectFailure {var invalid=try frame(.init(version:99,kind:"hello",role:.primary,name:"A",manifest:nil));_ = try BackupLink.extract(&invalid)}
    try await expectFailure {var invalid=try frame(.init(version:1,kind:"play",role:.primary,name:"A",manifest:nil));_ = try BackupLink.extract(&invalid)}
    print("PASS: SHA-256, portable path comparison, duplicate cues, fade mismatch, decode probe, missing/corrupt files, verified package, atomic failure and bounded protocol frames")
    guard network else {return}
    func wait(_ check:()->Bool) async throws {for _ in 0..<200 {if check(){return};try await Task.sleep(for:.milliseconds(100))};throw BackupFailure("Backup network test timed out")}
    let primary=BackupLink(name:"Test A",canConfigure:{true}),backup=BackupLink(name:"Test B",canConfigure:{true})
    func report(_ stage:String){print("LINK TEST: \(stage) · A=\(primary.status) · B=\(backup.status)");fflush(stdout)}
    defer {primary.disconnect();backup.disconnect()}
    try primary.host(.primary,advertise:false);try await wait {primary.port != nil}
    report("listener ready");let pairing=primary.code;backup.connect(.hostPort(host:"127.0.0.1",port:primary.port!),code:pairing,role:.backup)
    do {try await wait {primary.connected && backup.connected}}catch {report("pairing timeout");throw error};report("paired");precondition(primary.peerName == "Test B" && backup.peerName == "Test A")
    // Restore identical audio after the export mutation test.
    try silentWave().write(to:a);try silentWave().write(to:b)
    primary.check(input([a,a]));backup.check(input([b,b]));do {try await wait {primary.verified && backup.verified}}catch {report("verification timeout · \(primary.progress) / \(backup.progress)");throw error};report("sets verified")
    try bytes.write(to:b);try await wait {!primary.verified && primary.remote == nil && backup.local == nil};precondition(primary.connected)
    try silentWave().write(to:b)
    backup.check(input([b,b],fade:.long));try await wait {!primary.issues.isEmpty && !backup.issues.isEmpty}
    backup.disconnect();try await wait {!primary.connected};precondition(!primary.verified)
    try primary.host(.primary,advertise:false);try await wait {primary.port != nil}
    let correct=primary.code
    backup.connect(.hostPort(host:"127.0.0.1",port:primary.port!),code:"AAAA-BBBB-CCCC",role:.backup)
    try await wait {backup.status.contains("failed") || backup.status.contains("timed out")};precondition(!primary.connected && !backup.connected && !primary.verified)
    primary.disconnect();backup.disconnect()
    try primary.host(.primary,advertise:false);try await wait {primary.port != nil}
    let sameRole=BackupLink(name:"Wrong Role",canConfigure:{true});defer {sameRole.disconnect()}
    sameRole.connect(.hostPort(host:"127.0.0.1",port:primary.port!),code:primary.code)
    try await wait {sameRole.status.contains("opposite roles") || primary.status.contains("opposite roles")};precondition(!primary.verified && !sameRole.verified)
    sameRole.disconnect();primary.disconnect()
    try primary.host(.primary,advertise:false);try await wait {primary.port != nil}
    let stalled=NWConnection(to:.hostPort(host:"127.0.0.1",port:primary.port!),using:BackupLink.parameters(BackupLink.normalizedCode(primary.code)))
    let hello=try frame(.init(version:1,kind:"hello",role:.backup,name:"Stalled test peer",manifest:nil))
    stalled.stateUpdateHandler={state in if case .ready=state {stalled.send(content:hello,completion:.contentProcessed {_ in})}}
    stalled.start(queue:.main);defer {stalled.stateUpdateHandler=nil;stalled.cancel()}
    try await wait {primary.connected};try await wait {!primary.connected};precondition(primary.status.contains("offline"))
    _=correct
    print("PASS: real TLS-PSK loopback pairing, encrypted manifest exchange, matching/mismatching sets, remote invalidation, disconnect, wrong-code rejection, same-role rejection, file-change invalidation and missing-heartbeat timeout")
}
