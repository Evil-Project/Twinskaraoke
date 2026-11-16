import Foundation

nonisolated enum BandleAudioEffect: Int, Codable, Sendable {
    case none = 0
    case reverse = 1
    case pitchShift = 2
    case speedChange = 3
    case lowPassFilter = 4
    case audioMix = 5
    case gradualReveal = 6
    case vocalsOnly = 7
    case distortion = 8
    case echo = 9
    case chorus = 10
    case flanger = 11
    case telephoneReverb = 12
    case pitchShiftSlowMotion = 13
    case stutterCut = 14
    case theVoices = 15
    case shuffle = 16
    case whisperMode = 17
    case bitCrush = 18
    case bandPassFilter = 19
    case cassetteDamage = 20
    case robotize = 21
    case loopShortSegment = 22
}
