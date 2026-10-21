import Foundation

private func fixtureSnapshot(elapsed:Double=42,playing:Bool=true)->ViewerSnapshot {
    .init(set:"Night Stage · My Set",playing:playing,
        now:.init(number:2,title:"A Quiet Signal",elapsed:elapsed,duration:215,gain:1),
        next:.init(number:3,title:"Blue Hour",elapsed:0,duration:184,gain:0),
        crossfading:false,transitionRemaining:0,endMode:"next",volume:0.8,
        tracks:[.init(number:1,title:"Opening",fade:3),.init(number:2,title:"A Quiet Signal",fade:6),.init(number:3,title:"Blue Hour",fade:0),.init(number:4,title:"Closing Lights",fade:3)],totalTracks:4)
}
@MainActor func runViewerTests() async throws {
    var elapsed=42.0,playing=true,blocked=false
    let viewer=WebViewer(snapshot:{fixtureSnapshot(elapsed:elapsed,playing:playing)},canConfigure:{!blocked})
    defer {blocked=false;viewer.stop()}
    func waitReady() async throws {for _ in 0..<100 {if viewer.port>0 {return};try await Task.sleep(nanoseconds:20_000_000)};throw BackupFailure("Viewer listener did not start")}
    viewer.start();try await waitReady();let initialToken=viewer.token
    precondition(viewer.link?.fragment == initialToken && initialToken.count == 64)
    let host="127.0.0.1:\(viewer.port)"
    func raw(_ path:String="/api/state",method:String="GET",headers:String="",hostValue:String?=nil)->Data {Data("\(method) \(path) HTTP/1.1\r\nHost: \(hostValue ?? host)\r\n\(headers)\r\n".utf8)}
    func code(_ data:Data)->Int {Int(String(decoding:data.prefix(24),as:UTF8.self).split(separator:" ")[1])!}
    let auth="Authorization: Bearer \(initialToken)\r\n"
    precondition(code(viewer.reply(raw())) == 401)
    precondition(code(viewer.reply(raw(headers:"Authorization: Bearer wrong\r\n"))) == 401)
    precondition(code(viewer.reply(raw(method:"POST",headers:auth))) == 405)
    precondition(code(viewer.reply(raw("/api/play",headers:auth))) == 404)
    precondition(code(viewer.reply(raw("/../audio.wav",headers:auth))) == 404)
    precondition(code(viewer.reply(raw(headers:auth,hostValue:"attacker.invalid:\(viewer.port)"))) == 403)
    precondition(code(viewer.reply(raw(headers:auth+"Origin: https://attacker.invalid\r\n"))) == 403)
    precondition(code(viewer.reply(raw(headers:auth+"Sec-Fetch-Site: cross-site\r\n"))) == 403)
    precondition(code(viewer.reply(raw(headers:auth+auth))) == 400)
    precondition(code(viewer.reply(Data(repeating:65,count:8193))) == 400)
    precondition(code(viewer.reply(raw("/"))) == 200 && code(viewer.reply(raw("/viewer.js"))) == 200)
    let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=3;let client=URLSession(configuration:config);defer {client.invalidateAndCancel()}
    func request(_ path:String="/api/state",token:String?=initialToken) async throws->(Data,HTTPURLResponse) {
        var request=URLRequest(url:URL(string:"http://\(host)\(path)")!);if let token {request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")};let (data,response)=try await client.data(for:request);return (data,response as! HTTPURLResponse)
    }
    let (first,response)=try await request();precondition(response.statusCode == 200 && response.value(forHTTPHeaderField:"Cache-Control") == "no-store")
    let state=try JSONDecoder().decode(ViewerSnapshot.self,from:first);precondition(state.playing && state.now.elapsed == 42 && state.tracks.count == 4)
    let text=String(decoding:first,as:UTF8.self);precondition(!text.contains("file:") && !text.contains(initialToken))
    elapsed=99;playing=false;try await Task.sleep(nanoseconds:550_000_000)
    let (changed,_)=try await request();let paused=try JSONDecoder().decode(ViewerSnapshot.self,from:changed);precondition(!paused.playing && paused.now.elapsed == 99)
    let (_,denied)=try await request(token:nil);precondition(denied.statusCode == 401)
    blocked=true;viewer.stop();precondition(viewer.running);blocked=false
    viewer.stop();precondition(!viewer.running && viewer.link == nil && viewer.token.isEmpty)
    viewer.start();try await waitReady();precondition(viewer.token != initialToken)
    let old=Data("GET /api/state HTTP/1.1\r\nHost: 127.0.0.1:\(viewer.port)\r\nAuthorization: Bearer \(initialToken)\r\n\r\n".utf8)
    precondition(code(viewer.reply(old)) == 401)
    let suite="local.hardplay.viewer-test.\(UUID().uuidString)",defaults=UserDefaults(suiteName:suite)!
    defer {defaults.removePersistentDomain(forName:suite)}
    let player=Player(defaults:defaults,remoteCommands:false)
    let a=Track(url:URL(fileURLWithPath:"/private/secret/audio.wav"),customTitle:"<script>alert('track')</script>")
    let b=Track(url:a.url,customTitle:"Second occurrence",occurrenceID:UUID().uuidString)
    player.tracks=[a,b];player.currentID=b.id;player.elapsed=Double.nan;player.duration=Double.infinity
    let snapshot=ViewerSnapshot.capture(player),encoded=try JSONEncoder().encode(snapshot)
    precondition(snapshot.now.number == 2 && snapshot.tracks.count == 2 && snapshot.now.elapsed == 0 && snapshot.now.duration == 0)
    precondition(!String(decoding:encoded,as:UTF8.self).contains("secret") && snapshot.tracks[0].title == a.title)
    print("PASS: live HTTP state and pause updates, token authentication/rotation, no transport or file routes, host/origin/method/header bounds, no-store, duplicate queue positions, no source paths, finite times and setup lock")
}
@MainActor func runViewerFixture() async {
    let started=Date()
    let viewer=WebViewer(snapshot:{fixtureSnapshot(elapsed:42+Date().timeIntervalSince(started))},canConfigure:{true})
    viewer.start()
    for _ in 0..<100 {if viewer.port>0 {break};try? await Task.sleep(nanoseconds:20_000_000)}
    guard viewer.port>0 else {print("FAIL: viewer fixture listener");exit(1)}
    print("VIEWER_FIXTURE http://127.0.0.1:\(viewer.port)/#\(viewer.token)");fflush(stdout)
    // Headless synthetic state only. No app windows, user library or audio engine playback.
    try? await Task.sleep(nanoseconds:600_000_000_000);viewer.stop();exit(0)
}
