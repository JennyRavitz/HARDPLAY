import AppKit
import SwiftUI

final class BackupViewState:ObservableObject {
    @Published var selectedRole:BackupLink.Role = .primary
    @Published var code=""
    @Published var host=""
    @Published var port=""
    @Published var exporting=false
    @Published var exportMessage=""
    @Published var advancedIP=false
}
struct BackupView:View {
    var embedded=false
    @ObservedObject private var link=BackupLink.shared
    @ObservedObject private var player=Player.shared
    @ObservedObject private var setup=SetupLock.shared
    @ObservedObject private var lock=ControlLock.shared
    @StateObject private var ui=BackupViewState()
    private var blocked:Bool {setup.settingsBlocked || lock.isLocked}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Timecode & Backup").font(.stage(.title2).bold())
                Text("Pair two Macs and verify your set. Playback stays independent in this first stage.").font(.stage(.callout)).foregroundStyle(.secondary)
                MarkerLabel(link.summary,systemImage:link.verified ? "checkmark.shield":"desktopcomputer").font(.stage(size:13,weight:.semibold)).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(accent.opacity(0.12),in:RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("backup-status")
                VStack(alignment:.leading,spacing:8) {
                    Text("1 · Connect").font(.stage(.headline))
                    VStack(alignment:.leading,spacing:10) {
                        Picker("This Mac",selection:$ui.selectedRole) {ForEach(BackupLink.Role.allCases,id:\.self){Text($0.rawValue).tag($0)}}.disabled(link.connected || link.listening)
                        HStack {
                            Button("Create Pair") {do {try link.host(ui.selectedRole)}catch {ui.exportMessage=error.localizedDescription}}.disabled(link.connected || link.listening)
                            Button("Find Mac") {link.browse(ui.selectedRole)}.disabled(link.connected || link.listening)
                            Spacer()
                            Button("Disconnect") {link.disconnect()}
                        }
                        if !link.code.isEmpty {
                            Text(link.code).font(.stage(size:22,weight:.bold,design:.monospaced)).textSelection(.enabled)
                            Text("Enter this code on the other Mac. Expires after 5 minutes. Keep the roles opposite.").font(.stage(.caption)).foregroundStyle(.secondary)
                            if let p=link.port {Text("Listening port: \(p.rawValue)").font(.stage(.caption)).textSelection(.enabled)}
                        }
                        if !link.connected && !link.listening {
                            TextField("Pairing code from the other Mac",text:$ui.code).textFieldStyle(.roundedBorder)
                            ForEach(link.peers) {peer in
                                HStack {Text(peer.name).lineLimit(1);Spacer();Button("Connect") {link.connect(peer.endpoint,code:ui.code,role:ui.selectedRole)}}
                            }
                            Button(ui.advancedIP ? "Hide IP settings":"Connect by IP…") {ui.advancedIP.toggle()}.font(.stage(.caption))
                            if ui.advancedIP {
                                HStack {TextField("IP address",text:$ui.host);TextField("Port",text:$ui.port).frame(width:70)}.textFieldStyle(.roundedBorder)
                                Button("Connect by IP") {if let number=UInt16(ui.port),number>0,!ui.host.trimmingCharacters(in:.whitespaces).isEmpty {link.connect(.hostPort(host:.init(ui.host.trimmingCharacters(in:.whitespaces)),port:.init(rawValue:number)!),code:ui.code,role:ui.selectedRole)}}.disabled(UInt16(ui.port).map {$0 == 0} ?? true)
                            }
                        }
                        if link.connected {MarkerLabel("Encrypted connection · \(link.peerName)",systemImage:"lock.shield").font(.stage(.caption))}
                    }.padding(7)
                }.padding(10).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading,spacing:8) {
                    Text("2 · Check Set").font(.stage(.headline))
                    VStack(alignment:.leading,spacing:10) {
                        Text("Compare audio contents, queue order, fades, Auto Stop and resume positions. Run this on both Macs while paused.").font(.stage(.caption)).foregroundStyle(.secondary)
                        HStack {
                            Button(link.scanning ? "Checking…":"Check This Set") {link.check(player.backupInput())}.disabled(link.scanning || player.playing || player.tracks.isEmpty || ui.exporting)
                            Button(ui.exporting ? "Exporting…":"Export Backup Package…") {exportPackage()}.disabled(link.scanning || ui.exporting || player.playing || link.local == nil)
                        }
                        if link.scanning || ui.exporting {ProgressView().controlSize(.small)}
                        if !link.progress.isEmpty {Text(link.progress).font(.stage(.caption)).textSelection(.enabled)}
                        if let local=link.local {Text("This Mac: \(local.entries.count) tracks checked").font(.stage(.caption))}
                        if let remote=link.remote {Text("Other Mac: \(remote.entries.count) tracks checked").font(.stage(.caption))}
                        ForEach(Array(link.issues.prefix(100).enumerated()),id:\.offset) {_,message in MarkerLabel(message,systemImage:"exclamationmark.triangle").font(.stage(.caption)).foregroundStyle(.orange)}
                        if link.issues.count>100 {Text("…and \(link.issues.count-100) more differences").font(.stage(.caption))}
                        if !ui.exportMessage.isEmpty {Text(ui.exportMessage).font(.stage(.caption)).textSelection(.enabled)}
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(7)
                }.padding(10).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                Text("Next stages: scheduled playback → LTC / MTC → armed hardware failover. Set verification does not arm or synchronize audio.").font(.stage(.caption)).foregroundStyle(.secondary)
                Text("Network loss never stops your music or changes the audio source.").font(.stage(.caption)).foregroundStyle(.secondary)
            }.padding(20).disabled(blocked)
        }.frame(minWidth:440,minHeight:embedded ? 300:540).onAppear {link.observe(player)}
    }
    private func exportPackage() {
        guard !blocked,!player.playing,let manifest=link.local else {return}
        let input=player.backupInput()
        guard link.matches(input) else {link.invalidate();return}
        let panel=NSSavePanel();panel.title="Export Backup Package";panel.nameFieldStringValue="HARDPLAY Backup";panel.canCreateDirectories=true
        guard panel.runModal() == .OK,let destination=panel.url,!blocked else {return}
        ui.exporting=true;ui.exportMessage="Copying and verifying audio…"
        Task { @MainActor in
            let worker=Task.detached(priority:.utility) {try BackupPackage.write(input,manifest:manifest,to:destination)}
            do {try await worker.value;ui.exportMessage="Saved \(destination.lastPathComponent) · open Set.hardplay on the other Mac"}
            catch {ui.exportMessage=error.localizedDescription}
            ui.exporting=false
        }
    }
}

struct BackupStatusStrip:View {
    @ObservedObject private var link=BackupLink.shared
    var body:some View {
        if link.connected || link.listening {
            Button {AppDelegate.shared.showBackupWindow()} label: {
                MarkerLabel(link.summary,systemImage:link.verified ? "checkmark.shield":"network").font(.stage(size:10,weight:.medium)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading).padding(7)
            }.buttonStyle(PlayerControlStyle()).accessibilityLabel("Backup: \(link.summary)")
        }
    }
}
