import AppKit
import Combine
import SwiftUI
import Carbon
import CoreMIDI
import UniformTypeIdentifiers

struct MappedAction: RawRepresentable, Codable, Hashable, Identifiable {
    var rawValue: String
    var id: String { rawValue }
    static let names: [(String,String)] = [("playPause","Play / Pause"),("mute","Mute"),("shuffle","Shuffle"),("repeat","Repeat Queue"),("stopAtEnd","Stop at End"),("previous","Previous Track"),("next","Next Track"),("restart","Restart"),("resume","Resume"),("fadeOff","Fade Off"),("fadeShort","Short Fade"),("fadeLong","Long Fade"),("applyAll","Apply Fade to All"),("volume","Master Volume"),("volumeDown","Volume Down"),("volumeUp","Volume Up"),("mini","Mini Player"),("playlist","Playlist Window"),("lockSetup","Lock Setup"),("lock","Lock All Controls"),("settings","Open PATCH"),("themes","Open Themes"),("mappings","Open MIDI / Keys"),("backup","Open Backup"),("viewer","Open Web Viewer"),("editSelected","Edit Selected Track"),("nano","Nano Player"),("autoFit","Auto Fit Window"),("autoNano","Nano on Minimize"),("fullScreen","Full Screen"),("hints","Control Hints")]
    static var all: [MappedAction] { names.map { .init(rawValue:$0.0) } }
    var title: String {
        if rawValue.hasPrefix("track:") { return "Play · " + (Player.shared.tracks.first { $0.id == String(rawValue.dropFirst(6)) }?.title ?? URL(fileURLWithPath:String(rawValue.dropFirst(6))).deletingPathExtension().lastPathComponent) }
        return Self.names.first { $0.0 == rawValue }?.1 ?? rawValue
    }
    var supportsToggle: Bool { ["playPause","mute","shuffle","repeat","stopAtEnd","fadeShort","fadeLong","mini","playlist","lockSetup","nano","autoFit","autoNano","fullScreen","hints"].contains(rawValue) || rawValue.hasPrefix("track:") }
    var defaultBehavior: ButtonBehavior { ["playPause","mini","mute","shuffle","repeat","stopAtEnd","nano","autoFit","autoNano","fullScreen","hints"].contains(rawValue) ? .toggle : .trigger }
    var valid: Bool {
        if Self.names.contains(where:{$0.0 == rawValue}) {return true}
        guard rawValue.hasPrefix("track:"),rawValue.count<=4096 else {return false}
        let target=String(rawValue.dropFirst(6))
        return (target.hasPrefix("/") && !target.contains("\0")) || UUID(uuidString:target) != nil
    }
}
enum ButtonBehavior: String, Codable, CaseIterable { case trigger = "Trigger", toggle = "Toggle" }
enum MappingInput: String, Codable, CaseIterable { case keyboard = "Keyboard", midi = "MIDI" }
struct ControlBinding: Codable, Equatable, Identifiable {
    var action: MappedAction
    var input: MappingInput
    var label: String
    var key: UInt16? = nil
    var modifiers: UInt32? = nil
    var status: UInt8? = nil
    var channel: UInt8? = nil
    var number: UInt8? = nil
    var source: Int32? = nil
    var behavior: ButtonBehavior? = nil
    var effectiveBehavior: ButtonBehavior { behavior ?? action.defaultBehavior }
    var id: String { action.rawValue + input.rawValue }
    var valid: Bool {
        guard action.valid, label.count <= 300, effectiveBehavior != .toggle || action.supportsToggle else { return false }
        if action.rawValue == "volume" && (input != .midi || status != 0xB0) { return false }
        if input == .keyboard {
            guard let key, let modifiers, key <= 127, key != 53, modifiers & ~UInt32(cmdKey | optionKey | controlKey | shiftKey) == 0 else { return false }
            return !(modifiers & UInt32(cmdKey) != 0 && modifiers & UInt32(optionKey | controlKey) == 0) && !(key == 49 && modifiers == UInt32(cmdKey | optionKey))
        }
        return (status == 0x90 || status == 0xB0) && channel.map { $0 < 16 } == true && number.map { $0 < 128 } == true && source != nil
    }
    func sameSignal(as other: Self) -> Bool {
        input == other.input && (input == .keyboard ? key == other.key && modifiers == other.modifiers : status == other.status && channel == other.channel && number == other.number && source == other.source)
    }
}
struct ControlMapSet: Codable { var version = 2; var name: String; var bindings: [ControlBinding] }

struct MIDIStreamParser {
    private var status: UInt8?; private var values: [UInt8] = []
    mutating func feed(_ bytes: [UInt8]) -> [(UInt8,UInt8,UInt8)] {
        var messages: [(UInt8,UInt8,UInt8)] = []
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte >= 0x80 { status = byte < 0xF0 ? byte : nil; values = []; continue }
            guard let status else { continue }
            values.append(byte)
            let length = (status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0) ? 1 : 2
            if values.count == length {
                if length == 2 { messages.append((status,values[0],values[1])) }
                values = []
            }
        }
        return messages
    }
}

final class ControlMappings: ObservableObject {
    static let shared = ControlMappings()
    @Published var mapping = false { didSet { if !mapping { selected = nil }; registerKeys() } }
    @Published var input: MappingInput = .keyboard
    @Published private(set) var selected: MappedAction?
    @Published private(set) var bindings: [ControlBinding] = []
    @Published private(set) var setName = "My Controls"
    @Published private(set) var devices: [String] = []
    @Published private(set) var globalCount = 0
    @Published var message = "Choose Map, select an action, then press a key or MIDI control."
    private let defaults: UserDefaults
    private let liveIO: Bool
    private var executor: ((MappedAction)->Void)?
    private var settingsObserver: AnyCancellable?
    private var localMonitor: Any?
    private var hotkeys: [EventHotKeyRef] = []
    private var registered: [UInt32:ControlBinding] = [:]
    private var heldKeys: Set<UInt32> = []
    private var unmutedVolume: Double = 0.8
    private let suppliedPlayer: Player?
    private let setupLock: SetupLock
    private var player: Player { suppliedPlayer ?? Player.shared }
    private var handler: EventHandlerRef?
    private var client = MIDIClientRef(), port = MIDIPortRef()
    private var sources: [MIDIEndpointRef] = []
    private var parsers: [Int32:MIDIStreamParser] = [:]
    private var levels: [String:UInt8] = [:]
    init(defaults:UserDefaults = .standard, liveIO:Bool = true, player:Player? = nil, setupLock:SetupLock = .shared, executor:((MappedAction)->Void)? = nil) {
        self.suppliedPlayer = player; self.setupLock = setupLock
        self.defaults = defaults; self.liveIO = liveIO; self.executor = executor
        let restoredVolume = defaults.double(forKey:"unmutedVolume")
        if restoredVolume > 0 && restoredVolume <= 1 { unmutedVolume = restoredVolume }
        if let data = defaults.data(forKey:"controlMapSet"), let value = try? JSONDecoder().decode(ControlMapSet.self,from:data), Self.valid(value) {
            bindings = value.bindings; setName = value.name
        }
        if liveIO { startKeyboard(); startMIDI() }
        settingsObserver = setupLock.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { if let self, self.setupLock.settingsBlocked { self.mapping = false } }
        }
    }
    static func valid(_ set:ControlMapSet) -> Bool {
        guard (set.version == 1 || set.version == 2), set.name.count <= 200, set.bindings.count <= 2000, set.bindings.allSatisfy(\.valid) else { return false }
        var prior: [ControlBinding] = []
        for binding in set.bindings {
            guard !prior.contains(where: { $0.id == binding.id || $0.sameSignal(as:binding) }) else { return false }
            prior.append(binding)
        }
        return true
    }
    func learn(_ action:MappedAction, input:MappingInput? = nil) {
        guard !ControlLock.shared.isLocked, !setupLock.settingsBlocked else { return }
        if let input { self.input = input }; if action.rawValue == "volume" { self.input = .midi }; mapping = true; selected = action
        message = "\(action.title) — waiting for \(self.input.rawValue)…"
    }
    func assign(_ binding:ControlBinding) {
        guard binding.valid, !ControlLock.shared.isLocked, !setupLock.settingsBlocked else { return }
        let conflict = bindings.first { $0.sameSignal(as:binding) && $0.action != binding.action }
        var updated = binding
        if updated.behavior == nil { updated.behavior = bindings.first { $0.id == binding.id }?.effectiveBehavior ?? binding.action.defaultBehavior }
        bindings.removeAll { $0.id == binding.id || $0.sameSignal(as:binding) }; bindings.append(updated)
        selected = nil; persist(); registerKeys()
        message = "Assigned \(binding.label)" + (conflict.map { " · replaced \($0.action.title)" } ?? "")
    }
    func clear(_ action:MappedAction,input:MappingInput) {
        guard !ControlLock.shared.isLocked, !setupLock.settingsBlocked else { return }
        bindings.removeAll { $0.action == action && $0.input == input }; persist(); registerKeys()
    }
    func label(_ action:MappedAction,input:MappingInput) -> String { bindings.first { $0.action == action && $0.input == input }?.label ?? "Learn…" }
    private func persist() { defaults.set(try? JSONEncoder().encode(ControlMapSet(name:setName,bindings:bindings)),forKey:"controlMapSet") }
    func behavior(_ action:MappedAction, input:MappingInput) -> ButtonBehavior {
        bindings.first { $0.action == action && $0.input == input }?.effectiveBehavior ?? action.defaultBehavior
    }
    func hasBinding(_ action:MappedAction, input:MappingInput) -> Bool { bindings.contains { $0.action == action && $0.input == input } }
    func setBehavior(_ behavior:ButtonBehavior, for action:MappedAction, input:MappingInput) {
        guard !ControlLock.shared.isLocked, !setupLock.settingsBlocked, action.rawValue != "volume", behavior != .toggle || action.supportsToggle,
              let index = bindings.firstIndex(where:{$0.action == action && $0.input == input}) else { return }
        bindings[index].behavior = behavior; persist(); registerKeys()
        message = "\(action.title) · \(input.rawValue): \(behavior.rawValue)"
    }
    func isOn(_ action:MappedAction) -> Bool? {
        let p = player
        switch action.rawValue {
        case "playPause": return p.playing
        case "mute": return p.volume == 0
        case "shuffle": return p.shuffle
        case "repeat": return p.repeatAll
        case "stopAtEnd": return p.endMode == .stop
        case "fadeShort": return p.stageTransitionTrack.map { p.fadeMode(after:$0) == .short } ?? false
        case "fadeLong": return p.stageTransitionTrack.map { p.fadeMode(after:$0) == .long } ?? false
        case "mini": return (AppDelegate.shared?.miniWindow?.isVisible ?? false) && !(AppDelegate.shared?.miniWindow?.isMiniaturized ?? false)
        case "playlist": return (AppDelegate.shared?.playlistWindow?.isVisible ?? false) && !(AppDelegate.shared?.playlistWindow?.isMiniaturized ?? false)
        case "nano":return WindowPresentation.shared.nano
        case "autoFit":return WindowPresentation.shared.autoFit
        case "autoNano":return WindowPresentation.shared.nanoOnMinimize
        case "fullScreen":return WindowPresentation.shared.fullScreen
        case "hints":return HintPreferences.shared.enabled
        case "lockSetup": return setupLock.isLocked
        default: return action.rawValue.hasPrefix("track:") ? (p.currentID == String(action.rawValue.dropFirst(6)) && p.playing) : nil
        }
    }
    func refreshStates() { objectWillChange.send() }
    private func fire(_ binding:ControlBinding, value:UInt8? = nil) {
        trigger(binding.action,value:value,behavior:binding.effectiveBehavior)
    }
    func trigger(_ action:MappedAction, value:UInt8? = nil, behavior:ButtonBehavior? = nil) {
        guard !mapping, !ControlLock.shared.isLocked else { return }
        let mode = behavior ?? action.defaultBehavior
        guard mode != .toggle || action.supportsToggle else { return }
        if let executor { executor(action); return }
        let p = player, toggles = mode == .toggle
        switch action.rawValue {
        case "playPause": if toggles || !p.playing { p.toggle() }
        case "previous": p.previous()
        case "next": p.next()
        case "restart": p.restart()
        case "resume": p.resumeSaved()
        case "mute":
            guard !setupLock.playbackBlocked else { return }
            if toggles && p.volume == 0 { p.volume = unmutedVolume }
            else { if p.volume > 0 { unmutedVolume = p.volume; defaults.set(unmutedVolume,forKey:"unmutedVolume") }; p.volume = 0 }
        case "shuffle": if !setupLock.editsBlocked { p.shuffle = toggles ? !p.shuffle : true }
        case "repeat": if !setupLock.editsBlocked { p.repeatAll = toggles ? !p.repeatAll : true }
        case "stopAtEnd": if !setupLock.editsBlocked { p.endMode = toggles && p.endMode == .stop ? .next : .stop }
        case "fadeOff", "fadeShort", "fadeLong":
            if let track = p.stageTransitionTrack {
                let mode:FadeMode = action.rawValue == "fadeOff" ? .none : action.rawValue == "fadeShort" ? .short : .long
                p.setFadeMode(toggles && p.fadeMode(after:track) == mode ? .none : mode,after:track)
            }
        case "applyAll": if let track = p.stageTransitionTrack { p.setFadeModeForAll(p.fadeMode(after:track)) }
        case "volume": if !setupLock.playbackBlocked, let value { p.volume = Double(value)/127 }
        case "volumeDown": if !setupLock.playbackBlocked { p.volume = max(0,p.volume - 0.05) }
        case "volumeUp": if !setupLock.playbackBlocked { p.volume = min(1,p.volume + 0.05) }
        case "mini": if toggles && (AppDelegate.shared?.miniWindow?.isVisible ?? false) && !(AppDelegate.shared?.miniWindow?.isMiniaturized ?? false) { AppDelegate.shared.miniWindow.orderOut(nil) } else { AppDelegate.shared.showMini() }
        case "playlist": if toggles && (AppDelegate.shared?.playlistWindow?.isVisible ?? false) && !(AppDelegate.shared?.playlistWindow?.isMiniaturized ?? false) { AppDelegate.shared.playlistWindow.orderOut(nil) } else { PlaylistWindowState.shared.detach() }
        case "lockSetup": if toggles && setupLock.isLocked { setupLock.unlock() } else { setupLock.lock() }
        case "lock": AppDelegate.shared.lockControls()
        case "editSelected":
            if let track=p.selectedTrack ?? p.current {AppDelegate.shared?.showQuickEdit(track)}
        case "settings","themes","mappings","backup","viewer":
            if let section=action.workspaceSection {WorkspaceState.shared.open(section)}
        case "nano":if toggles || !WindowPresentation.shared.nano {AppDelegate.shared?.toggleNano()}
        case "autoFit":if !setupLock.settingsBlocked {WindowPresentation.shared.autoFit = toggles ? !WindowPresentation.shared.autoFit:true}
        case "autoNano":if !setupLock.settingsBlocked {WindowPresentation.shared.nanoOnMinimize = toggles ? !WindowPresentation.shared.nanoOnMinimize:true}
        case "fullScreen":if toggles || !WindowPresentation.shared.fullScreen {AppDelegate.shared?.toggleStageFullScreen()}
        case "hints":if !setupLock.settingsBlocked {HintPreferences.shared.enabled = toggles ? !HintPreferences.shared.enabled:true}
        default:
            if action.rawValue.hasPrefix("track:"), let track = p.tracks.first(where:{$0.id == String(action.rawValue.dropFirst(6))}), !setupLock.selectionBlocked {
                if toggles && p.currentID == track.id && p.playing { p.pause() } else { p.play(track) }
            }
        }
        message = "\(action.title): " + (toggles ? ((isOn(action) ?? false) ? "On" : "Off") : "Triggered")
    }
    private static func modifiers(_ event:NSEvent) -> UInt32 {
        var result:UInt32 = 0
        for (flag,carbon) in [(NSEvent.ModifierFlags.command,cmdKey),(.option,optionKey),(.control,controlKey),(.shift,shiftKey)] { if event.modifierFlags.contains(flag) { result |= UInt32(carbon) } }
        return result
    }
    private func startKeyboard() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self, !ControlLock.shared.isLocked else { return event }
            let mods = Self.modifiers(event)
            if self.mapping {
                if event.keyCode == 53 { self.selected = nil; self.message = "Selection cancelled"; return nil }
                guard self.input == .keyboard, let action = self.selected else { return event }
                let symbols = (mods & UInt32(controlKey) != 0 ? "⌃":"") + (mods & UInt32(optionKey) != 0 ? "⌥":"") + (mods & UInt32(shiftKey) != 0 ? "⇧":"") + (mods & UInt32(cmdKey) != 0 ? "⌘":"")
                let keyName = event.keyCode == 49 ? "Space" : (event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)")
                // The existing global transport and system/app menu commands remain reserved.
                if (mods & UInt32(cmdKey) != 0 && mods & UInt32(optionKey | controlKey) == 0) || (event.keyCode == 49 && mods == UInt32(cmdKey | optionKey)) {
                    self.message = "Reserved shortcut. Try ⌥, ⌃ or a single key."; return event
                }
                self.assign(.init(action:action,input:.keyboard,label:symbols+keyName,key:event.keyCode,modifiers:mods)); return nil
            }
            guard !event.isARepeat, !(event.window?.firstResponder is NSTextView) else { return event }
            if let binding = self.bindings.first(where:{$0.input == .keyboard && $0.key == event.keyCode && $0.modifiers == mods}) { self.fire(binding); return nil }
            return event
        }
        let specs = [EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed)),EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event!,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
            guard id.signature == 0x48504D50 else { return OSStatus(eventNotHandledErr) }
            let pressed = GetEventKind(event!) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async { ControlMappings.shared.globalKey(id.id,pressed:pressed) }; return noErr
        },specs.count,specs,nil,&handler)
        registerKeys()
    }
    private func globalKey(_ id:UInt32, pressed:Bool) {
        if !pressed { heldKeys.remove(id); return }
        guard heldKeys.insert(id).inserted, !(NSApp.isActive && NSApp.keyWindow?.firstResponder is NSTextView) else { return }
        if let binding = registered[id] { fire(binding) }
    }
    private func registerKeys() {
        guard liveIO else { return }
        for key in hotkeys { UnregisterEventHotKey(key) }; hotkeys = []; registered = [:]; heldKeys = []; globalCount = 0
        guard !mapping else { return }
        for (index,binding) in bindings.enumerated() where binding.input == .keyboard {
            guard let key = binding.key, let mods = binding.modifiers, mods & UInt32(cmdKey | optionKey | controlKey) != 0 else { continue }
            var ref:EventHotKeyRef?
            let id = UInt32(index + 100)
            if RegisterEventHotKey(UInt32(key),mods,EventHotKeyID(signature:0x48504D50,id:id),GetApplicationEventTarget(),0,&ref) == noErr, let ref { hotkeys.append(ref); registered[id] = binding; globalCount = registered.count }
            else { message = "Shortcut \(binding.label) is already in use; available inside HARDPLAY." }
        }
    }
    static func packetBytes(_ list:UnsafePointer<MIDIPacketList>) -> [UInt8] {
        var bytes:[UInt8] = []
        // MIDIPacketList is a variable-length C structure: read the original storage,
        // not a Swift copy of the first fixed-size packet.
        var packet = UnsafeRawPointer(list).advanced(by:MemoryLayout<MIDIPacketList>.offset(of:\.packet)!).assumingMemoryBound(to:MIDIPacket.self)
        for _ in 0..<list.pointee.numPackets {
            let data = UnsafeRawPointer(packet).advanced(by:MemoryLayout<MIDIPacket>.offset(of:\.data)!).assumingMemoryBound(to:UInt8.self)
            bytes += Array(UnsafeBufferPointer(start:data,count:Int(packet.pointee.length)))
            packet = UnsafePointer(MIDIPacketNext(packet))
        }
        return bytes
    }
    private func startMIDI() {
        let status = MIDIClientCreateWithBlock("HARDPLAY Controls" as CFString,&client) { [weak self] _ in DispatchQueue.main.async { self?.refreshMIDI() } }
        guard status == noErr else { message = "MIDI unavailable (\(status))"; return }
        let result = MIDIInputPortCreateWithBlock(client,"HARDPLAY MIDI In" as CFString,&port) { [weak self] list, context in
            let endpoint = MIDIEndpointRef(UInt(bitPattern:context))
            var uid:Int32 = 0; MIDIObjectGetIntegerProperty(endpoint,kMIDIPropertyUniqueID,&uid)
            let bytes = Self.packetBytes(list)
            DispatchQueue.main.async { self?.receiveMIDI(bytes,source:uid) }
        }
        if result == noErr { refreshMIDI() } else { message = "MIDI input unavailable (\(result))" }
    }
    func refreshMIDI() {
        guard port != 0 else { return }
        for source in sources { MIDIPortDisconnectSource(port,source) }; sources = []; devices = []; parsers = [:]; levels = [:]
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index); var name:Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source,kMIDIPropertyDisplayName,&name)
            if MIDIPortConnectSource(port,source,UnsafeMutableRawPointer(bitPattern:UInt(source))) == noErr {
                sources.append(source); devices.append(name?.takeRetainedValue() as String? ?? "MIDI \(index+1)")
            }
        }
    }
    func receiveMIDI(_ bytes:[UInt8],source:Int32) {
        var parser = parsers[source] ?? MIDIStreamParser()
        let messages = parser.feed(bytes); parsers[source] = parser
        for (status,number,value) in messages {
            let kind = status & 0xF0, channel = status & 0x0F
            guard kind == 0x90 || kind == 0x80 || kind == 0xB0 else { continue }
            let normalized:UInt8 = kind == 0x80 ? 0x90 : kind
            let signal = "\(source):\(normalized):\(channel):\(number)"
            let old = levels[signal] ?? 0, level:UInt8 = kind == 0x80 ? 0 : value
            levels[signal] = level
            if mapping {
                if input == .midi, let action = selected, kind == 0xB0 || (kind == 0x90 && value > 0) {
                    assign(.init(action:action,input:.midi,label:"\(kind == 0xB0 ? "CC":"Note") \(number) · Ch \(channel+1)",status:kind,channel:channel,number:number,source:source))
                }
                continue
            }
            guard let binding = bindings.first(where:{$0.input == .midi && $0.status == normalized && $0.channel == channel && $0.number == number && $0.source == source}) else { continue }
            if binding.action.rawValue == "volume", kind == 0xB0 { fire(binding,value:value) }
            else if level > 0, old == 0 { fire(binding) }
        }
    }
    func saveSet() {
        guard !ControlLock.shared.isLocked, !setupLock.settingsBlocked else { return }
        let panel = NSSavePanel(); panel.title = "Save Control Set"; panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = setName + ".json"
        if panel.runModal() == .OK, let url = panel.url, !ControlLock.shared.isLocked, !setupLock.settingsBlocked {
            do {
                let name = url.deletingPathExtension().lastPathComponent
                let data = try JSONEncoder().encode(ControlMapSet(name:name,bindings:bindings)); try data.write(to:url,options:.atomic)
                setName = name; persist(); message = "Control set saved"
            } catch { message = error.localizedDescription }
        }
    }
    func loadSet() {
        guard !ControlLock.shared.isLocked, !setupLock.settingsBlocked else { return }
        let panel = NSOpenPanel(); panel.title = "Open Control Set"; panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, !ControlLock.shared.isLocked, !setupLock.settingsBlocked {
            do {
                let data = try Data(contentsOf:url); guard data.count < 1_000_000 else { throw CocoaError(.fileReadCorruptFile) }
                let value = try JSONDecoder().decode(ControlMapSet.self,from:data)
                guard Self.valid(value) else { throw CocoaError(.fileReadCorruptFile) }
                bindings = value.bindings; setName = value.name; selected = nil; persist(); registerKeys(); message = "Control set loaded"
            } catch { message = "Unable to load set: " + error.localizedDescription }
        }
    }
}
