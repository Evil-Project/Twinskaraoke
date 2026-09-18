import Accelerate
import AVFAudio

/// An error type representing failures that can occur during audio file operations.
public enum AudioFileError: Error {
    case audioDataUnavailable
    case failedToCreateAudioBuffer
}

/// A utility for reading audio samples from a file using AVFoundation.
///
/// This struct supports reading raw, monaural, or stereo audio samples from a local file.
/// Internally, it wraps `AVAudioFile` and uses `AVAudioPCMBuffer` for buffer management.
public struct AudioFile {
    private var avAudioFile: AVAudioFile

    /// Creates an `AudioFile` instance for reading audio data from a file.
    ///
    /// - Parameter url: The URL of the audio file to read.
    /// - Throws: An error if the file cannot be opened.
    public init(forReading url: URL) throws {
        avAudioFile = try AVAudioFile(forReading: url)
    }

    /// The total number of audio frames in the file.
    public var length: Int {
        Int(avAudioFile.length)
    }

    /// The number of channels in the audio file (e.g., 1 for mono, 2 for stereo).
    public var channelCount: Int {
        Int(avAudioFile.processingFormat.channelCount)
    }

    /// The sample rate (in Hz) of the audio file.
    public var sampleRate: Double {
        avAudioFile.processingFormat.sampleRate
    }

    /// Reads raw audio samples for all channels within the specified range.
    ///
    /// - Parameter range: The range of audio frames to read. If `nil`, reads the entire file.
    /// - Returns: A 2D array of samples, where each subarray corresponds to a channel.
    /// - Throws: An error if reading fails or audio data is unavailable.
    public func readSamples(in range: Range<Int>? = nil) throws -> [[Float]] {
        let totalLength = Int(avAudioFile.length)
        let readRange = range ?? 0 ..< totalLength
        let clampedRange = readRange.clamped(to: 0 ..< totalLength)

        guard !clampedRange.isEmpty else {
            return Array(repeating: [], count: channelCount)
        }

        avAudioFile.framePosition = AVAudioFramePosition(clampedRange.lowerBound)

        let framesToRead = AVAudioFrameCount(clampedRange.count)

        guard let audioBuffer = AVAudioPCMBuffer(
            pcmFormat: avAudioFile.processingFormat,
            frameCapacity: framesToRead
        ) else {
            throw AudioFileError.failedToCreateAudioBuffer
        }

        try avAudioFile.read(into: audioBuffer, frameCount: framesToRead)

        guard let channelData = audioBuffer.floatChannelData else {
            throw AudioFileError.audioDataUnavailable
        }

        let actualFrameLength = Int(audioBuffer.frameLength)

        return (0 ..< channelCount).map { channelIndex in
            let pointer = channelData[channelIndex]
            return Array(UnsafeBufferPointer(start: pointer, count: actualFrameLength))
        }
    }

    /// Reads audio samples as monaural (single-channel) data.
    ///
    /// If the file is stereo, this method averages the left and right channels.
    ///
    /// - Parameter range: The range of audio frames to read. If `nil`, reads the entire file.
    /// - Returns: An array of monaural samples.
    /// - Throws: An error if reading fails or audio data is unavailable.
    public func readMonauralSamples(in range: Range<Int>? = nil) throws -> [Float] {
        let allSamples = try readSamples(in: range)

        if channelCount == 1 {
            return allSamples[0]
        }

        let sumSamples = allSamples.reduce([Float](repeating: 0, count: length), vDSP.multiply)
        let meanSamples = vDSP.divide(sumSamples, Float(channelCount))
        return meanSamples
    }

    /// Reads audio samples as stereo data.
    ///
    /// If the file is monaural, the same samples are returned for both left and right channels.
    ///
    /// - Parameter range: The range of audio frames to read. If `nil`, reads the entire file.
    /// - Returns: A `StereoValues` struct containing left and right channel samples.
    /// - Throws: An error if reading fails or audio data is unavailable.
    public func readStereoSamples(in range: Range<Int>? = nil) throws -> StereoValues<[Float]> {
        if channelCount == 1 {
            let monauralSamples = try readMonauralSamples(in: range)
            return StereoValues(left: monauralSamples, right: monauralSamples)
        } else {
            let allSamples = try readSamples(in: range)
            return StereoValues(left: allSamples[0], right: allSamples[1])
        }
    }
}
