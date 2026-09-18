import CoreML

struct Spleeter2Model: SpleeterModelProtocol {
    let model: MLModel

    var maskFeatureNames: Stems2<String> {
        Stems2(
            vocals: "vocalsMask",
            accompaniment: "accompanimentMask"
        )
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func mapStems(
        _ strings: Stems2<String>,
        _ transform: (String) throws -> MLTensor
    ) rethrows -> Stems2<MLTensor> {
        try strings.mapStems(transform)
    }
}
