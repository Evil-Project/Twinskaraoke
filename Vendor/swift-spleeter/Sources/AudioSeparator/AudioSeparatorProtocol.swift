import CoreML

/// Protocol defining the interface for audio separators.
public protocol AudioSeparatorProtocol {
    /// The type of stems containing URLs.
    associatedtype URLStems: StemsProtocol where URLStems.Value == URL

    /// The type of stems containing float arrays.
    associatedtype FloatArrayStems: StemsProtocol where FloatArrayStems.Value == [Float]

    /// Initializes the audio separator with a compiled Spleeter2 Core ML model and STFT parameters.
    ///
    /// - Parameters:
    ///   - modelURL: URL pointing to the compiled Core ML model (.mlmodelc).
    ///   - fftSize: FFT size for Short-Time Fourier Transform (STFT). Must match the model's configuration.
    ///   - frequencyLimit: Number of frequency bins retained in the STFT output. Must match the model's configuration.
    ///   - clampingFrameCount: Number of STFT time frames processed per model inference.
    ///                         Must match the model's configuration.
    ///
    /// - Throws: An error if the model fails to load from the provided URL.
    init(
        modelURL: URL,
        fftSize: Int,
        frequencyLimit: Int,
        clampingFrameCount: Int
    ) throws

    /// Separates vocals and accompaniment from an audio file located at `inputURL`, and writes
    /// the separated stems to the corresponding URLs in `outputURLs`.
    ///
    /// This method reads the input file in chunks, processes each chunk asynchronously,
    /// and streams progress updates.
    ///
    /// - Parameters:
    ///   - inputURL: The URL of the audio file to separate.
    ///   - outputURLs: Destination URLs for the separated vocals and accompaniment audio files.
    ///
    /// - Returns: An `AsyncThrowingStream` that emits `Progress` updates and may throw errors.
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func separate(
        from inputURL: URL,
        to outputURLs: URLStems
    ) -> AsyncThrowingStream<Progress, any Error>

    /// Separates a file in the caller's task; cancellation waits for writers.
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func separateFile(
        from inputURL: URL,
        to outputURLs: URLStems,
        onProgress: @Sendable (Progress) async -> Void
    ) async throws

    /// Separates vocals and accompaniment from a stereo waveform.
    ///
    /// This method asynchronously processes the waveform in chunks and streams progress
    /// updates along with partial separation results.
    ///
    /// - Parameter waveform: The input stereo waveform represented as `StereoValues<[Float]>`.
    ///
    /// - Returns: An `AsyncThrowingStream` that emits tuples of optional separated stems and progress updates.
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func separate(
        _ waveform: StereoValues<[Float]>
    ) -> AsyncThrowingStream<(FloatArrayStems?, Progress), any Error>
}

extension AudioSeparatorProtocol {
    /// Initializes the audio separator with a compiled Spleeter2 Core ML model and STFT parameters.
    ///
    /// - Parameters:
    ///   - modelURL: URL pointing to the compiled Core ML model (.mlmodelc).
    ///   - fftSize: FFT size for Short-Time Fourier Transform (STFT). Must match the model's configuration.
    ///   - frequencyLimit: Number of frequency bins retained in the STFT output. Must match the model's configuration.
    ///   - clampingFrameCount: Number of STFT time frames processed per model inference.
    ///                         Must match the model's configuration.
    ///
    /// - Throws: An error if the model fails to load from the provided URL.
    public init(
        modelURL: URL,
        fftSize: Int = 4096,
        frequencyLimit: Int = 1024,
        clampingFrameCount: Int = 216
    ) throws {
        try self.init(
            modelURL: modelURL,
            fftSize: fftSize,
            frequencyLimit: frequencyLimit,
            clampingFrameCount: clampingFrameCount
        )
    }
}

/// Represents progress updates emitted during asynchronous separation operations.
public struct Progress: Sendable {
    /// Total number of chunks or steps to be processed.
    public let total: Int

    /// Current completed chunk or step index.
    public let current: Int

    public var fraction: Float {
        Float(current) / Float(total)
    }
}
