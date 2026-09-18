import AVFAudio

/// An error type representing failures that may occur during audio file writing.
public enum AudioFileWriterStreamError: Error {
    /// The provided sample array is empty or contains no channels.
    case noChannels

    /// Not all channels contain the same number of frames.
    case invalidLengths

    /// Failed to create an `AVAudioFormat` with the specified parameters.
    case failedToCreateFormat

    /// Failed to allocate an `AVAudioPCMBuffer` for writing audio data.
    case failedToCreateBuffer

    /// The audio buffer does not contain writable channel data.
    case noOutputChannelData

    /// The base address of the input sample buffer is nil.
    case noBaseAddress
}

/// A stream writer for creating and appending audio samples to a file using AVFoundation.
///
/// This struct allows writing multichannel float samples (e.g., mono or stereo)
/// to an audio file in a streaming fashion.
public struct AudioFileStreamWriter {
    private let outputFile: AVAudioFile
    private let format: AVAudioFormat
    private let channelCount: Int

    /// Creates a new stream writer for writing audio samples to the specified file URL.
    ///
    /// - Parameters:
    ///   - outputURL: The file URL where the audio will be written.
    ///   - sampleRate: The sample rate (in Hz) for the output audio file.
    ///   - channelCount: The number of channels (e.g., 1 for mono, 2 for stereo).
    /// - Throws: `AudioFileWriterStreamError` if the format could not be created,
    ///           or an error from `AVAudioFile` if the file could not be initialized.
    public init(to outputURL: URL, sampleRate: Double, channelCount: Int) throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount)
        ) else {
            throw AudioFileWriterStreamError.failedToCreateFormat
        }

        self.format = format
        self.channelCount = channelCount
        outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
    }

    /// Appends a block of multichannel float samples to the output audio file.
    ///
    /// - Parameter samples: A 2D array of float samples where each subarray represents a channel.
    /// - Throws: `AudioFileWriterStreamError` if the samples are invalid or buffering fails,
    ///           or an error from `AVAudioFile` if writing to the file fails.
    public func append(samples: [[Float]]) throws {
        guard let firstChannel = samples.first else {
            throw AudioFileWriterStreamError.noChannels
        }

        let frameCount = firstChannel.count

        guard samples.allSatisfy({ $0.count == frameCount }) else {
            throw AudioFileWriterStreamError.invalidLengths
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw AudioFileWriterStreamError.failedToCreateBuffer
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let floatChannelData = buffer.floatChannelData else {
            throw AudioFileWriterStreamError.noOutputChannelData
        }

        for (channelIndex, channelSamples) in samples.enumerated() {
            let channelPointer = floatChannelData[channelIndex]
            try channelSamples.withUnsafeBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else {
                    throw AudioFileWriterStreamError.noBaseAddress
                }
                channelPointer.update(from: baseAddress, count: frameCount)
            }
        }

        try outputFile.write(from: buffer)
    }
}
