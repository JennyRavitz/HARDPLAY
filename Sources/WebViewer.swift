import Foundation
import Network
import Combine
import Darwin
import SystemConfiguration

struct ViewerSnapshot:Codable {
    struct Item:Codable {let number:Int;let title:String;let fade:Double}
    struct Deck:Codable {let number:Int?;let title:String;let elapsed:Double;let duration:Double;let gain:Double}
    let set:String
    let playing:Bool
    let now:Deck
    let next:Deck
    let crossfading:Bool
    let transitionRemaining:Double
    let endMode:String
    let volume:Double
    let tracks:[Item]
    let totalTracks:Int
    static func capture(_ player:Player)->Self {
        func number(_ track:Track?)->Int? {guard let track,let i=player.tracks.firstIndex(where:{$0.id == track.id}) else {return nil};return i+1}
        func safe(_ value:Double)->Double {value.isFinite ? max(0,value):0}
        return Self(set:String(player.playlistName.prefix(500)),playing:player.playing,
            now:Deck(number:number(player.stageLeft),title:String((player.stageLeft?.title ?? "No track selected").prefix(1000)),elapsed:safe(player.stageLeftTime),duration:safe(player.stageLeftDuration),gain:safe(player.stageLeftGain)),
            next:Deck(number:number(player.stageRight),title:String((player.stageRight?.title ?? "End of queue").prefix(1000)),elapsed:safe(player.stageRightTime),duration:safe(player.stageRightDuration),gain:safe(player.stageRightGain)),
            crossfading:player.isCrossfading,transitionRemaining:safe(player.transitionRemaining),endMode:player.endMode.rawValue,volume:min(1,safe(player.volume)),
            tracks:Array(player.tracks.prefix(20000).enumerated()).map {Item(number:$0.offset+1,title:String($0.element.title.prefix(1000)),fade:player.fadeMode(after:$0.element).seconds)},totalTracks:player.tracks.count)
    }
}

/// Explicitly started, read-only local HTTP viewer. No audio files, paths, transport or edit endpoints.
final class WebViewer:ObservableObject {
    static let shared=WebViewer()
    @Published private(set) var running=false
    @Published private(set) var status="Viewer off"
    @Published private(set) var port:UInt16=0
    @Published private(set) var addresses:[String]=[]
    @Published var address="127.0.0.1"
    private(set) var token=""
    private var listener:NWListener?
    private var clients:[UUID:NWConnection]=[:]
    private var generation=UUID()
    private var cached=Data()
    private var cachedAt:TimeInterval=0
    private let snapshot:()->ViewerSnapshot
    private let canConfigure:()->Bool
    init(snapshot:@escaping ()->ViewerSnapshot = {ViewerSnapshot.capture(Player.shared)},canConfigure:@escaping ()->Bool = {!SetupLock.shared.settingsBlocked && !ControlLock.shared.isLocked}){self.snapshot=snapshot;self.canConfigure=canConfigure}
    var link:URL? {guard running,port>0,!token.isEmpty else {return nil};return URL(string:"http://\(address):\(port)/#\(token)")}
    func start() {
        guard canConfigure(),!running else {return};stopInternal()
        token=UUID().uuidString.replacingOccurrences(of:"-",with:"")+UUID().uuidString.replacingOccurrences(of:"-",with:"")
        addresses=Self.localAddresses();address=addresses.first ?? "127.0.0.1"
        do {
            let params=NWParameters.tcp;params.includePeerToPeer=false
            let server=try NWListener(using:params,on:.any);listener=server;running=true;status="Starting viewer…"
            let session=generation
            server.stateUpdateHandler={ [weak self,weak server] state in
                guard let self,self.generation == session else {return}
                switch state {
                case .ready:self.port=server?.port?.rawValue ?? 0;self.status=self.addresses.isEmpty ? "This Mac only · connect Wi-Fi or Ethernet and restart":"Ready · devices on the same network"
                case .failed(let error):self.stopInternal();self.status="Viewer unavailable: "+error.localizedDescription
                default:break
                }
            }
            server.newConnectionHandler={ [weak self] connection in
                guard let self,self.generation == session,self.clients.count<24 else {connection.cancel();return}
                let id=UUID();self.clients[id]=connection;connection.start(queue:.main)
                connection.stateUpdateHandler={ [weak self] state in if case .failed=state {self?.finish(id)} }
                self.receive(connection,id:id,data:Data(),session:session)
                DispatchQueue.main.asyncAfter(deadline:.now()+5) { [weak self] in self?.finish(id) }
            }
            server.start(queue:.main)
        } catch {stopInternal();status="Cannot start viewer: "+error.localizedDescription}
    }
    func stop(){guard canConfigure() else {return};stopInternal();status="Viewer off · previous links revoked"}
    private func stopInternal(){generation=UUID();listener?.cancel();listener=nil;for connection in clients.values {connection.cancel()};clients.removeAll();running=false;port=0;token="";cached=Data();cachedAt=0}
    private func finish(_ id:UUID){clients.removeValue(forKey:id)?.cancel()}
    private func receive(_ connection:NWConnection,id:UUID,data:Data,session:UUID) {
        connection.receive(minimumIncompleteLength:1,maximumLength:8192) { [weak self] chunk,_,complete,error in
            guard let self,self.generation == session,self.clients[id] != nil else {return}
            var request=data;if let chunk {request.append(chunk)}
            guard request.count<=8192 else {self.send(Self.response(413,"Request too large"),connection,id);return}
            if request.range(of:Data("\r\n\r\n".utf8)) != nil {
                let reply=self.reply(request);self.send(reply,connection,id)
            } else if complete || error != nil {self.finish(id)}else {self.receive(connection,id:id,data:request,session:session)}
        }
    }
    private func send(_ data:Data,_ connection:NWConnection,_ id:UUID){connection.send(content:data,completion:.contentProcessed { [weak self] _ in self?.finish(id) })}
    func reply(_ request:Data)->Data {
        guard request.count<=8192,let raw=String(data:request,encoding:.utf8),let headerEnd=raw.range(of:"\r\n\r\n"),raw[headerEnd.upperBound...].isEmpty else {return Self.response(400,"Bad request")}
        let lines=raw[..<headerEnd.lowerBound].components(separatedBy:"\r\n")
        let first=(lines.first ?? "").split(separator:" ")
        guard first.count == 3,first[2] == "HTTP/1.1" else {return Self.response(400,"Bad request")}
        guard first[0] == "GET" else {return Self.response(405,"Read-only viewer")}
        var headers:[String:String]=[:]
        for line in lines.dropFirst() {
            guard let colon=line.firstIndex(of:":") else {return Self.response(400,"Bad request")}
            let name=line[..<colon].lowercased();guard headers[name] == nil else {return Self.response(400,"Duplicate header")}
            headers[name]=line[line.index(after:colon)...].trimmingCharacters(in:.whitespaces)
        }
        let hosts=(addresses+["127.0.0.1","localhost"]).map {"\($0):\(port)"}
        guard let host=headers["host"],hosts.contains(host),headers["transfer-encoding"] == nil,headers["content-length"].map({$0 == "0"}) ?? true else {return Self.response(403,"Invalid viewer host")}
        if let origin=headers["origin"],origin != "http://"+host {return Self.response(403,"Same-origin only")}
        if headers["sec-fetch-site"] == "cross-site" {return Self.response(403,"Same-origin only")}
        switch first[1] {
        case "/":return Self.response(200,ViewerPage.html,type:"text/html; charset=utf-8")
        case "/viewer.css":return Self.response(200,ViewerPage.css,type:"text/css; charset=utf-8")
        case "/viewer.js":return Self.response(200,ViewerPage.js,type:"text/javascript; charset=utf-8")
        case "/api/state":
            guard running,!token.isEmpty,headers["authorization"] == "Bearer "+token else {return Self.response(401,"Link expired or invalid")}
            let now=ProcessInfo.processInfo.systemUptime
            if cached.isEmpty || now-cachedAt>=0.5 {guard let encoded=try? JSONEncoder().encode(snapshot()) else {return Self.response(503,"State unavailable")};cached=encoded;cachedAt=now}
            return Self.response(200,data:cached,type:"application/json")
        default:return Self.response(404,"Not found")
        }
    }
    static func response(_ status:Int,_ text:String,type:String="text/plain; charset=utf-8")->Data {response(status,data:Data(text.utf8),type:type)}
    static func response(_ status:Int,data:Data,type:String)->Data {
        let names=[200:"OK",400:"Bad Request",401:"Unauthorized",403:"Forbidden",404:"Not Found",405:"Method Not Allowed",413:"Content Too Large",503:"Service Unavailable"]
        var result=Data("HTTP/1.1 \(status) \(names[status] ?? "Error")\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\r\n".utf8);result.append(data);return result
    }
    static func localAddresses()->[String] {
        var head:UnsafeMutablePointer<ifaddrs>?;guard getifaddrs(&head) == 0 else {return []};defer {freeifaddrs(head)}
        var result:[String]=[];var cursor=head
        while let item=cursor {
            defer {cursor=item.pointee.ifa_next}
            let name=String(cString:item.pointee.ifa_name)
            guard (name.hasPrefix("en") || name.hasPrefix("bridge")),let addr=item.pointee.ifa_addr,Int32(addr.pointee.sa_family) == AF_INET,item.pointee.ifa_flags & UInt32(IFF_UP) != 0 else {continue}
            var buffer=[CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(addr,socklen_t(addr.pointee.sa_len),&buffer,socklen_t(buffer.count),nil,0,NI_NUMERICHOST) == 0 {let ip=String(cString:buffer);if !ip.hasPrefix("127."),!ip.hasPrefix("169.254."),!result.contains(ip) {result.append(ip)}}
        }
        // Prefer the active service address over static aliases on the same interface.
        if let global=SCDynamicStoreCopyValue(nil,"State:/Network/Global/IPv4" as CFString) as? [String:Any],
           let service=global["PrimaryService"] as? String,
           let info=SCDynamicStoreCopyValue(nil,("State:/Network/Service/"+service+"/IPv4") as CFString) as? [String:Any],
           let primary=info["Addresses"] as? [String] {
            return primary.filter {result.contains($0)}+result.filter {!primary.contains($0)}
        }
        return result
    }
}
