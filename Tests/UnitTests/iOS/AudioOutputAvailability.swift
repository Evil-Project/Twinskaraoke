import AVFoundation

/// Whether this machine can play audio at all. VMs and some CI runners have no
/// audio output device: `AVAudioEngine` can't start (error -10851), so a test
/// that needs real playback can't pass there. Only that error means "no
/// device"; any other failure to start returns true, so the test runs and
/// shows it. Starting the engine is the only reliable probe: without a device
/// the output node can't even be configured, and the audio session still
/// reports a built-in speaker.
nonisolated let audioOutputAvailable: Bool = {
    let engine = AVAudioEngine()
    _ = engine.mainMixerNode
    do {
        try engine.start()
        engine.stop()
        return true
    } catch let error as NSError where error.code == -10851 {
        return false
    } catch {
        return true
    }
}()
