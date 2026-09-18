import CoreML

protocol InternalAudioSeparatorProtocol: AudioSeparatorProtocol {
    associatedtype SpleeterModel: SpleeterModelProtocol
    associatedtype AudioFileStreamWriterStems: StemsProtocol
        where AudioFileStreamWriterStems.Value == AudioFileStreamWriter

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    typealias MLTensorStems = SpleeterModel.MLTensorStems

    var model: SpleeterModel { get }
    var fftSize: Int { get }
    var frequencyLimit: Int { get }
    var clampingFrameCount: Int { get }

    init(
        model: SpleeterModel,
        fftSize: Int,
        frequencyLimit: Int,
        clampingFrameCount: Int
    ) throws

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func asyncMapStems(
        _ tensors: MLTensorStems,
        _ transform: (MLTensor) async throws -> [Float]
    ) async rethrows -> FloatArrayStems

    func mapStems(
        _ urls: URLStems,
        _ transform: (URL) throws -> AudioFileStreamWriter
    ) rethrows -> AudioFileStreamWriterStems
}

extension InternalAudioSeparatorProtocol {
    var hopLength: Int {
        fftSize / 4
    }

    var clampingLength: Int {
        hopLength * (clampingFrameCount - 1)
    }

    // swiftlint:disable:next missing_docs
    public init(
        modelURL: URL,
        fftSize: Int,
        frequencyLimit: Int,
        clampingFrameCount: Int
    ) throws {
        try self.init(
            model: SpleeterModel(contentsOf: modelURL),
            fftSize: fftSize,
            frequencyLimit: frequencyLimit,
            clampingFrameCount: clampingFrameCount
        )
    }

    /// Runs in the caller's task. Returning, including cancellation, means
    /// every writer and inference operation has finished using the output files.
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    public func separateFile(
        from inputURL: URL,
        to outputURLs: URLStems,
        onProgress: @Sendable (Progress) async -> Void
    ) async throws {
        #if os(iOS)
        if #available(iOS 27, *) {
            try await withMLTensorComputePolicy(.cpuOnly) {
                try await writeSeparatedFile(from: inputURL, to: outputURLs, onProgress: onProgress)
            }
            return
        }
        #endif
        try await writeSeparatedFile(from: inputURL, to: outputURLs, onProgress: onProgress)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    private func writeSeparatedFile(
        from inputURL: URL,
        to outputURLs: URLStems,
        onProgress: @Sendable (Progress) async -> Void
    ) async throws {
        try Task.checkCancellation()
        let audioFile = try AudioFile(forReading: inputURL)
        let writers = try mapStems(outputURLs) {
            try AudioFileStreamWriter(to: $0, sampleRate: audioFile.sampleRate, channelCount: 1)
        }
        let chunks = stride(from: 0, to: audioFile.length, by: clampingLength)
        await onProgress(Progress(total: chunks.underestimatedCount, current: 0))
        for (index, position) in chunks.enumerated() {
            try Task.checkCancellation()
            let chunk = try audioFile.readStereoSamples(in: position ..< min(position + clampingLength, audioFile.length))
            let output = try await separate(chunk: chunk)
            try Task.checkCancellation()
            for (writer, samples) in zip(writers.values, output.values) {
                try Task.checkCancellation()
                try writer.append(samples: [samples])
            }
            await onProgress(Progress(total: chunks.underestimatedCount, current: index + 1))
        }
        try Task.checkCancellation()
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    // swiftlint:disable:next missing_docs
    public func separate(
        from inputURL: URL,
        to outputURLs: URLStems
    ) -> AsyncThrowingStream<Progress, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let audioFile = try AudioFile(forReading: inputURL)

                    let sampleRate = audioFile.sampleRate

                    let fileWriters = try mapStems(outputURLs) {
                        try AudioFileStreamWriter(
                            to: $0,
                            sampleRate: sampleRate,
                            channelCount: 1
                        )
                    }

                    let stride = stride(from: 0, to: audioFile.length, by: clampingLength)

                    continuation.yield(Progress(total: stride.underestimatedCount, current: 0))

                    for (index, position) in stride.enumerated() {
                        let range = position ..< min(position + clampingLength, audioFile.length)

                        let chunk = try audioFile.readStereoSamples(in: range)

                        let output = try await separate(chunk: chunk)

                        for (writer, samples) in zip(fileWriters.values, output.values) {
                            try writer.append(samples: [samples])
                        }

                        continuation.yield(Progress(total: stride.underestimatedCount, current: index + 1))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    // swiftlint:disable:next missing_docs
    public func separate(
        _ waveform: StereoValues<[Float]>
    ) -> AsyncThrowingStream<(FloatArrayStems?, Progress), any Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let length = max(waveform.left.count, waveform.right.count)
                    let stride = stride(from: 0, to: length, by: clampingLength)

                    continuation.yield((
                        nil,
                        Progress(total: stride.underestimatedCount, current: 0)
                    ))

                    for (index, position) in stride.enumerated() {
                        let range = position ..< min(position + clampingLength, length)

                        let chunk = waveform.mapChannels { Array($0[range]) }

                        let output = try await separate(chunk: chunk)

                        continuation.yield((
                            output,
                            Progress(total: stride.underestimatedCount, current: index + 1)
                        ))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Performs separation on a single chunk of stereo waveform using the pretrained Core ML model.
    ///
    /// - Parameter chunk: A chunk of stereo waveform samples.
    ///
    /// - Returns: Separated stems as monaural waveforms with lengths clamped to the input length.
    ///
    /// - Throws: An error if the model prediction or inverse STFT fails.
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    private func separate(
        chunk: StereoValues<[Float]>
    ) async throws -> FloatArrayStems {
        let stft = try STFT(fftSize: 4096, hopLength: 1024, frequencyLimit: 1024)

        let spectrograms = try chunk.mapChannels {
            let spectrogram = try stft.forward(waveform: $0.paddedOrClamped(to: 1024 * 215).map(\.self))
            return SpectrogramTensor(spectrogram)
        }

        let magnitude = MLTensor(spectrograms.mapChannels(\.magnitude))

        let masks = try await model.prediction(magnitude: magnitude)

        return try await asyncMapStems(masks) { mask in
            let complex = MLTensor(spectrograms.mapChannels(\.complex))
            let masked = mask * complex
            let monauralMasked = masked.mean(alongAxes: 0)
            let monauralMaskedWaveform = try await stft.inverse(
                Spectrogram(
                    realFrames: monauralMasked[..., 0].transposed().array2d(),
                    imagFrames: monauralMasked[..., 1].transposed().array2d()
                )
            )

            let maxLength = max(chunk.left.count, chunk.right.count)
            let clamped = monauralMaskedWaveform.prefix(maxLength)
            return Array(clamped)
        }
    }
}
