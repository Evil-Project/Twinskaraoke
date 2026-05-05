import AVFoundation
import MediaToolbox

/// Wraps `MTAudioProcessingTap` to provide center-channel ("vocal") attenuation
/// on an `AVPlayerItem`. Stereo recordings typically pan the lead vocal dead
/// center, so subtracting the side-content's mid component reduces it.
///
/// This is a global processor (single attenuation value) because the tap's
/// process callback must be `@convention(c)` and cannot capture state.
enum KaraokeAudioProcessor {
  /// 0 = vocals untouched, 1 = vocals fully cancelled.
  static var vocalAttenuation: Float = 0
  static func attachVocalCancel(to playerItem: AVPlayerItem) {
    Task.detached {
      let asset = playerItem.asset
      let tracks: [AVAssetTrack]
      if #available(iOS 15.0, *) {
        tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
      } else {
        tracks = asset.tracks(withMediaType: .audio)
      }
      guard let track = tracks.first else { return }
      var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: nil,
        init: nil,
        finalize: nil,
        prepare: nil,
        unprepare: nil,
        process: karaokeTapProcess
      )
      var unmanagedTap: Unmanaged<MTAudioProcessingTap>?
      let status = withUnsafeMutablePointer(to: &unmanagedTap) { ptr -> OSStatus in
        ptr.withMemoryRebound(to: Optional<MTAudioProcessingTap>.self, capacity: 1) { rebound in
          MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            rebound
          )
        }
      }
      guard status == noErr, let tap = unmanagedTap?.takeRetainedValue() else { return }
      let mix = AVMutableAudioMix()
      let params = AVMutableAudioMixInputParameters(track: track)
      params.audioTapProcessor = tap
      mix.inputParameters = [params]
      await MainActor.run { playerItem.audioMix = mix }
    }
  }
}
private let karaokeTapProcess: MTAudioProcessingTapProcessCallback = {
  tap, numFrames, _, bufferList, framesProcessedOut, flagsOut in
  var timeRange = CMTimeRange()
  let status = MTAudioProcessingTapGetSourceAudio(
    tap, numFrames, bufferList, flagsOut, &timeRange, framesProcessedOut)
  guard status == noErr else { return }
  let attenuation = KaraokeAudioProcessor.vocalAttenuation
  guard attenuation > 0.001 else { return }
  let abl = UnsafeMutableAudioBufferListPointer(bufferList)
  guard abl.count >= 2 else { return }
  let frames = Int(framesProcessedOut.pointee)
  guard frames > 0 else { return }
  guard let l = abl[0].mData?.assumingMemoryBound(to: Float.self),
    let r = abl[1].mData?.assumingMemoryBound(to: Float.self)
  else { return }
  let keep = 1.0 - attenuation
  for i in 0..<frames {
    let mid = (l[i] + r[i]) * 0.5
    let side = (l[i] - r[i]) * 0.5
    let scaledMid = mid * keep
    l[i] = scaledMid + side
    r[i] = scaledMid - side
  }
}
