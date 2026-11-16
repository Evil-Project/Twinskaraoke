import Foundation

extension BandleAudioEffect {
    var title: String {
        switch self {
        case .none: String(localized: "Original Audio")
        case .reverse: String(localized: "Reversed Audio")
        case .pitchShift: String(localized: "Pitch Shifted")
        case .speedChange: String(localized: "Speed Changed")
        case .lowPassFilter: String(localized: "Muffled Audio")
        case .audioMix: String(localized: "Mixed Audio")
        case .gradualReveal: String(localized: "Gradual Reveal")
        case .vocalsOnly: String(localized: "Vocals Only")
        case .distortion: String(localized: "Distorted Audio")
        case .echo: String(localized: "Echo")
        case .chorus: String(localized: "Chorus")
        case .flanger: String(localized: "Flanger")
        case .telephoneReverb: String(localized: "Telephone Reverb")
        case .pitchShiftSlowMotion: String(localized: "Slow Motion")
        case .stutterCut: String(localized: "Stutter Cut")
        case .theVoices: String(localized: "The Voices")
        case .shuffle: String(localized: "Shuffled Audio")
        case .whisperMode: String(localized: "Whisper Mode")
        case .bitCrush: String(localized: "Bit Crush")
        case .bandPassFilter: String(localized: "Band-Pass Filter")
        case .cassetteDamage: String(localized: "Cassette Damage")
        case .robotize: String(localized: "Robotize")
        case .loopShortSegment: String(localized: "Loop Stutter")
        }
    }
}
