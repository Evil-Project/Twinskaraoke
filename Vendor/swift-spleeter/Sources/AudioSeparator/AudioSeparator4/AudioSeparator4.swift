import CoreML

/// Audio separator that separates a music into 4 stems (vocals, drums, bass and others)
/// by using a pretrained Spleeter Core ML model.
public struct AudioSeparator4: AudioSeparatorProtocol, InternalAudioSeparatorProtocol {
    typealias SpleeterModel = Spleeter4Model

    public typealias FloatArrayStems = Stems4<[Float]>
    public typealias URLStems = Stems4<URL>
    typealias AudioFileStreamWriterStems = Stems4<AudioFileStreamWriter>

    let model: Spleeter4Model
    let fftSize: Int
    let frequencyLimit: Int
    let clampingFrameCount: Int

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func asyncMapStems(
        _ tensors: MLTensorStems,
        _ transform: (MLTensor) async throws -> [Float]
    ) async rethrows -> Stems4<[Float]> {
        try await tensors.asyncMapStems(transform)
    }

    func mapStems(
        _ urls: Stems4<URL>,
        _ transform: (URL) throws -> AudioFileStreamWriter
    ) rethrows -> Stems4<AudioFileStreamWriter> {
        try urls.mapStems(transform)
    }
}
