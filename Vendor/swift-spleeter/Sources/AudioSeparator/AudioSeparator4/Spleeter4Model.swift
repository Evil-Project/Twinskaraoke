import CoreML

struct Spleeter4Model: SpleeterModelProtocol {
    let model: MLModel

    var maskFeatureNames: Stems4<String> {
        Stems4(
            vocals: "vocalsMask",
            drums: "drumsMask",
            bass: "bassMask",
            other: "otherMask"
        )
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func mapStems(
        _ strings: Stems4<String>,
        _ transform: (String) throws -> MLTensor
    ) rethrows -> Stems4<MLTensor> {
        try strings.mapStems(transform)
    }
}
