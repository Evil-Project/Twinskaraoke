import CoreML

/// Audio separator that separates a music into 5 stems (vocals, piano, drums, bass and others)
/// by using a pretrained Spleeter Core ML model.
public struct AudioSeparator5: AudioSeparatorProtocol, InternalAudioSeparatorProtocol {
    typealias SpleeterModel = Spleeter5Model

    public typealias FloatArrayStems = Stems5<[Float]>
    public typealias URLStems = Stems5<URL>
    typealias AudioFileStreamWriterStems = Stems5<AudioFileStreamWriter>

    let model: Spleeter5Model
    let fftSize: Int
    let frequencyLimit: Int
    let clampingFrameCount: Int

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func asyncMapStems(
        _ tensors: MLTensorStems,
        _ transform: (MLTensor) async throws -> [Float]
    ) async rethrows -> Stems5<[Float]> {
        try await tensors.asyncMapStems(transform)
    }

    func mapStems(
        _ urls: Stems5<URL>,
        _ transform: (URL) throws -> AudioFileStreamWriter
    ) rethrows -> Stems5<AudioFileStreamWriter> {
        try urls.mapStems(transform)
    }
}
