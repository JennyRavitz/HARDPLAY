import Foundation
import Network
import Security
import CryptoKit
import Combine

/// Preparation only. This protocol never executes transport commands or switches audio.
final class BackupLink:ObservableObject {
    static let shared=BackupLink()
    enum Role:String,CaseIterable,Codable {case primary="Primary A",backup="Backup B"}
    struct Peer:Identifiable {let id:String;let endpoint:NWEndpoint;let name:String}
    struct Packet:Codable {let version:Int;let kind:String;let role:Role;let name:String;let manifest:BackupManifest?}
    @Published private(set) var role:Role = .primary
    @Published private(set) var peers:[Peer]=[]
    @Published private(set) var code=""
    @Published private(set) var status="Disconnected"
    @Published private(set) var peerName=""
    @Published private(set) var connected=false
    @Published private(set) var listening=false
    @Published private(set) var scanning=false
    @Published private(set) var progress=""
    @Published private(set) var local:BackupManifest?
    @Published private(set) var remote:BackupManifest?
    @Published private(set) var issues:[String]=[]
    private var listener:NWListener?
    private var browser:NWBrowser?
    private var connection:NWConnection?
    private var incoming=Data()
    private var timer:Timer?
    private var lastReceive=ProcessInfo.processInfo.systemUptime
    private var scanTask:Task<Void,Never>?
    private var signature:String?
    private var epoch=UUID()
    private var scanEpoch=UUID()
    private var updates:AnyCancellable?
    private var source:Player?
    private var fileWatch:AnyCancellable?
    private var fileStamp:String?
    private func stamps(_ input:BackupSetInput)->String {
        input.items.map {item in
            let a=try? FileManager.default.attributesOfItem(atPath:item.url.path)
            return "\(item.url.path):\((a?[.size] as? NSNumber)?.int64Value ?? -1):\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1)"
        }.joined(separator:"\n")
    }

    private let canConfigure:()->Bool
    let name:String
    var port:NWEndpoint.Port? {guard let port=listener?.port,port.rawValue>0 else {return nil};return port}
    var verified:Bool {connected && local != nil && remote != nil && issues.isEmpty}
    var summary:String {
        if !connected {return status}
        if scanning {return "Checking set…"}
        if local == nil || remote == nil {return "Connected · Check both sets"}
        return issues.isEmpty ? "Sets match · preparation only":"Set mismatch · \(issues.count) issues"
    }
    init(name:String=Host.current().localizedName ?? "HARDPLAY Mac",canConfigure:@escaping ()->Bool = { !SetupLock.shared.settingsBlocked && !ControlLock.shared.isLocked }) {self.name=String(name.prefix(100));self.canConfigure=canConfigure}
    func observe(_ player:Player) {
        guard updates == nil else {return};source=player
        updates=player.objectWillChange.throttle(for:.seconds(1),scheduler:RunLoop.main,latest:true).sink { [weak self,weak player] _ in
            DispatchQueue.main.async {guard let self,let player,let signature=self.signature else {return};if player.backupInput().signature != signature {self.invalidate()}}
        }
    }
    static func normalizedCode(_ value:String)->String {value.uppercased().filter {"ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0)}}
    static func parameters(_ code:String)->NWParameters {
        let tls=NWProtocolTLS.Options()
        let key=Data(SHA256.hash(data:Data(("HARDPLAY pairing v1:"+code).utf8)))
        let identity=Data("HARDPLAY-backup-v1".utf8)
        key.withUnsafeBytes {keyBytes in identity.withUnsafeBytes {identityBytes in
            sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,DispatchData(bytes:keyBytes) as __DispatchData,DispatchData(bytes:identityBytes) as __DispatchData)
        }}
        // Network.framework external PSK is supported with TLS 1.2, not TLS 1.3.
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,tls_ciphersuite_t(rawValue:0x00A8)!)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
        let tcp=NWProtocolTCP.Options();tcp.noDelay=true
        let params=NWParameters(tls:tls,tcp:tcp);params.includePeerToPeer=false
        return params
    }
    func host(_ newRole:Role = .primary,advertise:Bool=true)throws {
        guard canConfigure() else {return};disconnect();role=newRole
        let alphabet=Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let raw=String((0..<12).map {_ in alphabet.randomElement()!})
        code=stride(from:0,to:12,by:4).map {String(Array(raw)[$0..<$0+4])}.joined(separator:"-")
        let server=try NWListener(using:Self.parameters(raw),on:.any);listener=server;listening=true;status="Waiting for the other Mac"
        if advertise {server.service=NWListener.Service(name:name,type:"_hardplay-bk._tcp")}
        let session=epoch
        server.stateUpdateHandler={ [weak self] state in if CommandLine.arguments.contains("--backup-link-test") {print("SERVER: \(state)");fflush(stdout)};guard let self,self.epoch == session else {return};if case .ready=state {self.status="Waiting for the other Mac"};if case .failed(let error)=state {self.status="Listener: \(error.localizedDescription)";self.listening=false} }
        server.newConnectionHandler={ [weak self] candidate in
            guard let self,self.epoch == session,self.connection == nil else {candidate.cancel();return}
            if CommandLine.arguments.contains("--backup-link-test") {print("ACCEPTED connection");fflush(stdout)}
            self.attach(candidate,session:session)
        }
        server.start(queue:.main)
        // Pairing is deliberately ephemeral and cannot stay open unattended forever.
        DispatchQueue.main.asyncAfter(deadline:.now()+300) { [weak self] in guard let self,self.epoch == session,!self.connected else {return};self.disconnect();self.status="Pairing expired · create a new code" }
    }
    func browse(_ newRole:Role = .backup) {
        guard canConfigure() else {return};disconnect();role=newRole;status="Looking for HARDPLAY Macs…"
        let search=NWBrowser(for:.bonjour(type:"_hardplay-bk._tcp",domain:nil),using:.tcp);browser=search;let session=epoch
        search.browseResultsChangedHandler={ [weak self] results,_ in guard let self,self.epoch == session else {return};self.peers=results.map {result in let label:String;if case .service(let n,_,_,_)=result.endpoint {label=n}else {label=result.endpoint.debugDescription};return Peer(id:result.endpoint.debugDescription,endpoint:result.endpoint,name:label)}.sorted {$0.name<$1.name} }
        search.stateUpdateHandler={ [weak self] state in guard let self,self.epoch == session else {return};if case .failed(let e)=state {self.status="Discovery: \(e.localizedDescription)"};if case .waiting(let e)=state {self.status="Allow Local Network access · \(e.localizedDescription)"} }
        search.start(queue:.main)
    }
    func connect(_ endpoint:NWEndpoint,code entered:String,role newRole:Role? = nil) {
        guard canConfigure() else {return};let normalized=Self.normalizedCode(entered)
        guard normalized.count == 12 else {status="Enter all 12 characters of the pairing code";return}
        // Stop browsing but retain the chosen role. A new explicit connect replaces old sessions.
        let selected=newRole ?? role;disconnect();role=selected;status="Connecting securely…"
        attach(NWConnection(to:endpoint,using:Self.parameters(normalized)),session:epoch)
    }
    private func attach(_ candidate:NWConnection,session:UUID) {
        connection=candidate;incoming.removeAll();remote=nil;peerName=""
        candidate.stateUpdateHandler={ [weak self,weak candidate] state in
            guard let self,let candidate,self.epoch == session,self.connection === candidate else {return}
            if CommandLine.arguments.contains("--backup-link-test") {print("\(self.name) CONNECTION: \(state)");fflush(stdout)}
            switch state {
            case .ready:
                self.lastReceive=ProcessInfo.processInfo.systemUptime;self.status="Authenticating peer…"
                self.send("hello");self.receive(candidate,session:session)
                self.timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
                    guard let self,self.connection === candidate else {return}
                    if ProcessInfo.processInfo.systemUptime-self.lastReceive>4 {self.drop("Peer offline · audio unchanged");return}
                    self.send("heartbeat")
                }
            case .waiting(let error):self.status="Waiting for network: \(error.localizedDescription)"
            case .failed(let error):self.drop("Connection failed · check code / network: \(error.localizedDescription)")
            case .cancelled:break
            default:break
            }
        }
        candidate.start(queue:.main)
        DispatchQueue.main.asyncAfter(deadline:.now()+8) { [weak self,weak candidate] in guard let self,let candidate,self.connection === candidate,!self.connected else {return};self.drop("Pairing timed out · check the code and network") }
    }
    private func send(_ kind:String) {
        guard let connection else {return}
        let packet=Packet(version:1,kind:kind,role:role,name:name,manifest:kind == "manifest" ? local:nil)
        guard let payload=try? JSONEncoder().encode(packet),payload.count<=Self.maxFrame else {return}
        var length=UInt32(payload.count).bigEndian;var frame=withUnsafeBytes(of:&length) {Data($0)};frame.append(payload)
        connection.send(content:frame,completion:.contentProcessed { [weak self,weak connection] error in if let error,let connection {DispatchQueue.main.async {guard let self,self.connection === connection else {return};self.drop("Send failed: \(error.localizedDescription)")}} })
    }
    static let maxFrame=8_000_000
    static func extract(_ buffer:inout Data)throws->[Packet] {
        var packets:[Packet]=[]
        while buffer.count>=4 {
            let size=buffer.prefix(4).reduce(UInt32(0)) {($0<<8)|UInt32($1)}
            guard size>0,size<=maxFrame else {throw BackupFailure("Invalid backup message length")}
            guard buffer.count>=4+Int(size) else {break}
            let packet=try JSONDecoder().decode(Packet.self,from:Data(buffer.dropFirst(4).prefix(Int(size))))
            guard packet.version == 1,["hello","heartbeat","manifest","invalidate"].contains(packet.kind),packet.name.utf8.count<=1000,(packet.manifest == nil || (packet.kind == "manifest" && packet.manifest!.valid)) else {throw BackupFailure("Unsupported backup protocol")}
            packets.append(packet);buffer=Data(buffer.dropFirst(4+Int(size)))
        }
        guard buffer.count<=maxFrame+4 else {throw BackupFailure("Backup message too large")};return packets
    }
    private func receive(_ candidate:NWConnection,session:UUID) {
        candidate.receive(minimumIncompleteLength:1,maximumLength:65536) { [weak self,weak candidate] data,_,complete,error in
            guard let self,let candidate,self.epoch == session,self.connection === candidate else {return}
            if let data {self.incoming.append(data)}
            do {
                for packet in try Self.extract(&self.incoming) {
                    guard packet.role != self.role else {throw BackupFailure("Choose opposite roles: Primary A and Backup B")}
                    self.lastReceive=ProcessInfo.processInfo.systemUptime
                    if packet.kind == "hello" {self.connected=true;self.peerName=packet.name;self.code="";self.status="Connected · TLS";if self.local != nil {self.send("manifest")}}
                    else {guard self.connected else {throw BackupFailure("Expected peer hello first")}}
                    if packet.kind == "manifest" {self.remote=packet.manifest;self.compare()}
                    if packet.kind == "invalidate" {self.remote=nil;self.compare()}
                }
            } catch {self.drop(error.localizedDescription);return}
            if complete || error != nil {self.drop("Peer disconnected · audio unchanged");return}
            self.receive(candidate,session:session)
        }
    }
    private func compare() {issues=(local != nil && remote != nil) ? local!.differences(from:remote!):[]}
    func invalidate() {fileWatch?.cancel();fileWatch=nil;fileStamp=nil;scanTask?.cancel();scanEpoch=UUID();scanning=false;local=nil;signature=nil;issues=[];progress="Set changed · check again";if connected {send("invalidate")}}
    func matches(_ input:BackupSetInput)->Bool {local != nil && signature == input.signature && fileStamp == stamps(input)}
    func check(_ input:BackupSetInput) {
        guard canConfigure() else {return};invalidate();scanning=true;progress="Reading audio…";let checkID=UUID();scanEpoch=checkID
        let initialStamp=stamps(input)
        scanTask=Task { @MainActor [weak self] in
            let worker=Task.detached(priority:.utility) {try await BackupManifest.build(input)}
            do {
                let manifest=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                guard let self,!Task.isCancelled,self.scanEpoch == checkID else {return}
                if CommandLine.arguments.contains("--backup-link-test"),self.stamps(input) != initialStamp {print("FILE STAMP CHANGED: \(initialStamp) -> \(self.stamps(input))");fflush(stdout)}
                guard self.stamps(input) == initialStamp,self.source.map({$0.backupInput().signature == input.signature}) ?? true else {self.invalidate();return}
                self.fileStamp=initialStamp
                self.fileWatch=Timer.publish(every:2,on:.main,in:.common).autoconnect().sink { [weak self] _ in guard let self else {return};if self.stamps(input) != self.fileStamp {self.invalidate()} }
                self.local=manifest;self.signature=input.signature;self.scanning=false;self.progress="\(manifest.entries.count) tracks checked · SHA-256 + decode probe";self.compare();if self.connected {self.send("manifest")}
            } catch {guard let self,self.scanEpoch == checkID else {return};self.scanning=false;self.progress=error.localizedDescription}
        }
    }
    private func drop(_ message:String) {connection?.stateUpdateHandler=nil;connection?.cancel();connection=nil;timer?.invalidate();timer=nil;connected=false;remote=nil;incoming.removeAll();issues=[];peerName="";status=message}
    func disconnect() {epoch=UUID();drop("Disconnected");listener?.cancel();listener=nil;browser?.cancel();browser=nil;peers=[];code="";listening=false}
}
