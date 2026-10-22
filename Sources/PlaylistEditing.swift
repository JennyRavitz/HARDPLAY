import AppKit

struct QueueClipboard:Codable {
    struct Entry:Codable {var track:Track;var fade:FadeMode;var bookmark:Data?}
    var version=1
    var entries:[Entry]
    static let type=NSPasteboard.PasteboardType("local.hardplay.queue-selection")
    static func read(_ board:NSPasteboard)->QueueClipboard? {
        guard let data=board.data(forType:type),data.count<=32_000_000,
              let value=try? JSONDecoder().decode(Self.self,from:data),value.version==1,
              !value.entries.isEmpty,value.entries.count<=10_000,
              value.entries.allSatisfy({$0.track.url.isFileURL}) else {return nil}
        return value
    }
}
extension Notification.Name {static let queueRename=Notification.Name("HardPlayQueueRename")}
extension AppDelegate:NSMenuItemValidation {
    var queueKeyboardContext:Bool {
        guard let window=NSApp.keyWindow,window.attachedSheet == nil,
              !(window.firstResponder is NSTextView),!ControlMappings.shared.mapping else {return false}
        return window === playlistWindow || window === miniWindow || (window === mainWindow && WorkspaceState.shared.section == nil)
    }
    private var canEditQueue:Bool {queueKeyboardContext && !ControlLock.shared.isLocked && !SetupLock.shared.editsBlocked}
    @objc func selectAll(_ sender:Any?) {if let text=NSApp.keyWindow?.firstResponder as? NSTextView {text.selectAll(sender);return};guard queueKeyboardContext else{return};Player.shared.selectAllQueue()}
    @objc func copy(_ sender:Any?) {if let text=NSApp.keyWindow?.firstResponder as? NSTextView {text.copy(sender);return};guard queueKeyboardContext else{return};Player.shared.copyQueue(to:.general)}
    @objc func cut(_ sender:Any?) {if let text=NSApp.keyWindow?.firstResponder as? NSTextView {text.cut(sender);return};guard canEditQueue else{return};Player.shared.cutQueue(to:.general)}
    @objc func paste(_ sender:Any?) {if let text=NSApp.keyWindow?.firstResponder as? NSTextView {text.paste(sender);return};guard canEditQueue else{return};Player.shared.pasteQueue(from:.general)}
    @objc func delete(_ sender:Any?) {if let text=NSApp.keyWindow?.firstResponder as? NSTextView {text.delete(sender);return};guard canEditQueue else{return};Player.shared.removeSelectedQueue()}
    @objc func undo(_ sender:Any?) {if let text=NSApp.keyWindow?.firstResponder as? NSTextView {text.undoManager?.undo();return};guard canEditQueue else{return};Player.shared.undoEdit()}
    @objc func redo(_ sender:Any?) {if let text=NSApp.keyWindow?.firstResponder as? NSTextView {text.undoManager?.redo();return};guard canEditQueue else{return};Player.shared.redoEdit()}
    @objc func duplicateSelection(_ sender:Any?) {guard canEditQueue else{return};Player.shared.duplicateSelectedQueue()}
    @objc func renameSelection(_ sender:Any?) {
        guard canEditQueue,Player.shared.selectedQueueTracks.count==1,let track=Player.shared.selectedQueueTracks.first else{return}
        NotificationCenter.default.post(name:.queueRename,object:track.id)
    }
    @objc func deselectQueue(_ sender:Any?) {guard queueKeyboardContext else{return};Player.shared.clearQueueSelection()}
    @objc func moveSelectionUp(_ sender:Any?) {guard canEditQueue else{return};Player.shared.moveSelectedQueue(by:-1)}
    @objc func moveSelectionDown(_ sender:Any?) {guard canEditQueue else{return};Player.shared.moveSelectedQueue(by:1)}
    func validateMenuItem(_ item:NSMenuItem)->Bool {
        if let text=NSApp.keyWindow?.firstResponder as? NSTextView {
            switch item.action {
            case #selector(undo(_:)):return text.undoManager?.canUndo ?? false
            case #selector(redo(_:)):return text.undoManager?.canRedo ?? false
            case #selector(copy(_:)):return text.selectedRange().length>0
            case #selector(cut(_:)),#selector(delete(_:)):return text.isEditable && text.selectedRange().length>0
            case #selector(paste(_:)):return text.isEditable
            case #selector(selectAll(_:)):return !text.string.isEmpty
            default:return false
            }
        }
        let p=Player.shared,hasSelection = !p.selectedQueueTracks.isEmpty
        switch item.action {
        case #selector(copy(_:)):return queueKeyboardContext && !ControlLock.shared.isLocked && hasSelection
        case #selector(selectAll(_:)),#selector(deselectQueue(_:)):return queueKeyboardContext && !SetupLock.shared.selectionBlocked && !ControlLock.shared.isLocked && !p.tracks.isEmpty
        case #selector(paste(_:)):return canEditQueue && (QueueClipboard.read(.general) != nil || NSPasteboard.general.canReadObject(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]))
        case #selector(cut(_:)),#selector(delete(_:)),#selector(duplicateSelection(_:)):return canEditQueue && hasSelection
        case #selector(renameSelection(_:)):return canEditQueue && p.selectedQueueTracks.count==1
        case #selector(moveSelectionUp(_:)),#selector(moveSelectionDown(_:)):return canEditQueue && hasSelection
        case #selector(undo(_:)):return canEditQueue && p.canUndoEdit
        case #selector(redo(_:)):return canEditQueue && p.canRedoEdit
        default:return true
        }
    }
    /// Control aliases supplement the standard Command menu shortcuts. Never intercept text editing.
    func queueKeyEvent(_ event:NSEvent)->Bool {
        guard queueKeyboardContext else{return false}
        let mods=event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock,.numericPad,.function])
        if mods == .control || mods == [.control,.shift] || mods == .command || mods == [.command,.shift] {
            let shifted=mods.contains(.shift),key=event.charactersIgnoringModifiers?.lowercased() ?? ""
            let actions:[String:Selector] = ["a":shifted ? #selector(deselectQueue(_:)):#selector(selectAll(_:)),"c":#selector(copy(_:)),"x":#selector(cut(_:)),"v":#selector(paste(_:)),"d":#selector(duplicateSelection(_:)),"z":shifted ? #selector(redo(_:)):#selector(undo(_:))]
            if let action=actions[key] {NSApp.sendAction(action,to:self,from:self);return true}
        }
        if (mods.isEmpty || mods == .command) && (event.keyCode==51 || event.keyCode==117) {delete(nil);return true}
        if mods.isEmpty && event.keyCode==36 {renameSelection(nil);return true}
        if (mods.isEmpty || mods == .shift) && (event.keyCode==125 || event.keyCode==126) {
            Player.shared.navigateQueue(by:event.keyCode==125 ? 1:-1,extend:mods == .shift);return true
        }
        return false
    }
    func addQueueEditMenu(to menu:NSMenu) {
        let item=NSMenuItem();item.title="Edit";let edit=NSMenu(title:"Edit");item.submenu=edit;menu.addItem(item)
        func add(_ title:String,_ action:Selector,_ key:String,_ mods:NSEvent.ModifierFlags = .command) {let entry=edit.addItem(withTitle:title,action:action,keyEquivalent:key);entry.keyEquivalentModifierMask=mods;entry.target=self}
        add("Undo",#selector(undo(_:)),"z");add("Redo",#selector(redo(_:)),"z",[.command,.shift]);edit.addItem(.separator())
        add("Cut",#selector(cut(_:)),"x");add("Copy",#selector(copy(_:)),"c");add("Paste",#selector(paste(_:)),"v")
        add("Select All",#selector(selectAll(_:)),"a");add("Deselect All",#selector(deselectQueue(_:)),"a",[.command,.shift]);edit.addItem(.separator())
        add("Duplicate Tracks",#selector(duplicateSelection(_:)),"d");add("Rename Track",#selector(renameSelection(_:)),"\r",[])
        add("Remove from Playlist",#selector(delete(_:)),"\u{8}");edit.items.last?.keyEquivalentModifierMask = .command
        add("Move Tracks Up",#selector(moveSelectionUp(_:)),"\u{f700}",[.command,.option]);add("Move Tracks Down",#selector(moveSelectionDown(_:)),"\u{f701}",[.command,.option])
    }
}
