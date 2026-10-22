import AppKit
import AVFoundation

@MainActor func runWaveformTests() async throws {
    precondition(StageWaveform.WaveView.time(x:-5,width:100,duration:12) == 0)
    precondition(StageWaveform.WaveView.time(x:50,width:100,duration:12) == 6)
    precondition(StageWaveform.WaveView.time(x:120,width:100,duration:12) == 12)
    precondition(StageWaveform.WaveView.time(x:20,width:0,duration:.nan) == 0)
    let screen=NSRect(x:0,y:0,width:1440,height:900)
    let frame=EmbeddedPlaylistLayout.frame(current:.init(x:100,y:100,width:520,height:680),visible:screen,tracks:2)
    precondition(frame.width>=600 && frame.height>=824 && screen.contains(frame))
    let large=NSRect(x:0,y:0,width:1000,height:880)
    precondition(EmbeddedPlaylistLayout.frame(current:large,visible:screen,tracks:2) == large)
    let snug=EmbeddedPlaylistLayout.fittedFrame(current:large,visible:screen,height:650)
    precondition(snug.height == 650 && snug.width == large.width && snug.maxY == large.maxY)
    precondition(EmbeddedPlaylistLayout.fittedFrame(current:snug,visible:screen,height:2000).height == screen.height)
    let small=NSRect(x:0,y:0,width:1280,height:720)
    let fit=EmbeddedPlaylistLayout.frame(current:frame,visible:small,tracks:2)
    precondition(fit.width>=840 && small.contains(fit))
    let suite="local.hardplay.waveform.\(UUID().uuidString)"
    let defaults=UserDefaults(suiteName:suite)!
    defer {defaults.removePersistentDomain(forName:suite)}
    let protection=SetupLock(defaults:defaults),player=Player(defaults:defaults,remoteCommands:false,setupLock:protection)
    let file=FileManager.default.temporaryDirectory.appendingPathComponent("hardplay-waveform-\(UUID().uuidString).wav")
    defer {try? FileManager.default.removeItem(at:file)}
    let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
    do {
        let out=try AVAudioFile(forWriting:file,settings:format.settings)
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:576000)!;buffer.frameLength=576000
        memset(buffer.floatChannelData![0],0,576000*MemoryLayout<Float>.size)
        try out.write(from:buffer)
    }
    let first=Track(url:file,occurrenceID:"one"),second=Track(url:file,occurrenceID:"two")
    player.tracks=[first,second];player.volume=0
    func waitLoaded() async throws {
        for _ in 0..<200 {if !player.isLoading {break};try await Task.sleep(nanoseconds:20_000_000)}
        precondition(!player.isLoading && player.error == nil)
    }
    player.load(first,autoplay:false);try await waitLoaded()
    player.waveformAction(first,seconds:4,duration:12,play:false)
    precondition(abs(player.elapsed-4)<0.05 && !player.playing)
    player.waveformAction(second,seconds:7,duration:12,play:false)
    precondition(player.currentID == first.id && !player.playing && player.stageRightTime == 7)
    protection.protectPlayback=true;protection.lock()
    player.waveformAction(first,seconds:8,duration:12,play:false)
    player.waveformAction(second,seconds:9,duration:12,play:true)
    precondition(player.currentID == first.id && player.waveformCues[second.id] == 7)
    protection.unlock()
    player.next(automatic:true);try await waitLoaded();player.pause()
    precondition(player.currentID == second.id && abs(player.elapsed-7)<0.3 && player.waveformCues[second.id] == nil)
    player.waveformAction(first,seconds:3,duration:12,play:true);try await waitLoaded()
    precondition(player.currentID == first.id && abs(player.elapsed-3)<0.3)
    player.pause()
    player.load(first,autoplay:false,position:1);try await waitLoaded()
    player.setFadeMode(.short,after:first)
    player.waveformAction(second,seconds:5,duration:12,play:false)
    player.toggle();player.play(second)
    for _ in 0..<200 {if player.isCrossfading {break};try await Task.sleep(nanoseconds:20_000_000)}
    precondition(player.isCrossfading && player.currentID == second.id && abs(player.elapsed-5)<0.5 && player.waveformCues[second.id] == nil)
    player.waveformAction(first,seconds:2,duration:12,play:false)
    precondition(player.isCrossfading && player.currentID == second.id)
    player.waveformAction(second,seconds:8,duration:12,play:false)
    precondition(!player.isCrossfading && abs(player.elapsed-8)<0.05)
    player.pause()
    player.waveformAction(first,seconds:.nan,duration:12,play:true)
    precondition(!player.isLoading)
    print("PASS: waveform time mapping, seek, non-interrupting NEXT cue, automatic cue consumption, explicit play, protection and embedded playlist sizing")
}
