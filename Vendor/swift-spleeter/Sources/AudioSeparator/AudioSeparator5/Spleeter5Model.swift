import CoreML

struct Spleeter5Model: SpleeterModelProtocol {
    let model: MLModel

    var maskFeatureNames: Stems5<String> {
        Stems5(
            vocals: "vocalsMask",
            piano: "pianoMask",
            drums: "drumsMask",
            bass: "bassMask",
            other: "otherMask"
        )
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func mapStems(
        _ strings: Stems5<String>,
        _ transform: (String) throws -> MLTensor
    ) rethrows -> Stems5<MLTensor> {
        try strings.mapStems(transform)
    }
}
