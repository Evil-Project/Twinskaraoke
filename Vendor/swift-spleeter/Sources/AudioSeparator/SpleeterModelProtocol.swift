import CoreML

protocol SpleeterModelProtocol {
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    associatedtype MLTensorStems: StemsProtocol where MLTensorStems.Value == MLTensor
    associatedtype StringStems: StemsProtocol where StringStems.Value == String

    var model: MLModel { get }

    /// Construct Spleeter2Model instance with an existing MLModel object.
    ///
    /// Usually the application does not use this initializer unless it makes a subclass of Spleeter2Model.
    /// Such application may want to use `MLModel(contentsOfURL:configuration:)`
    /// and `Spleeter2Model.urlOfModelInThisBundle` to create a MLModel object to pass-in.
    ///
    /// - Parameter model: MLModel object
    init(model: MLModel)

    var maskFeatureNames: StringStems { get }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func mapStems(
        _ strings: StringStems,
        _ transform: (String) throws -> MLTensor
    ) rethrows -> MLTensorStems
}

public enum SpleeterModelError: Error {
    case invalidFeatureName(_ featureName: String)
}

/// Model Prediction Input Type
final class SpleeterModelInput: MLFeatureProvider {
    /// magnitude as 2 × frequencyLimit × length 3-dimensional array of floats
    var magnitude: MLMultiArray

    var featureNames: Set<String> { ["magnitude"] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "magnitude" {
            return MLFeatureValue(multiArray: magnitude)
        }
        return nil
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    init(magnitude: MLTensor) async {
        let shapedArray = await magnitude.shapedArray(of: Float.self)
        self.magnitude = MLMultiArray(shapedArray)
    }
}

/// Model Prediction Output Type
class SpleeterModelOutput: MLFeatureProvider {
    /// Source provided by CoreML
    private let provider: MLFeatureProvider

    /// Output mask as 2 × frequencyLimit × length × 1 4-dimensional array of floats
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func maskTensor(for featureName: String) throws -> MLTensor {
        guard let multiArray = provider.featureValue(for: featureName)?.multiArrayValue else {
            throw SpleeterModelError.invalidFeatureName(featureName)
        }
        let shapedArray = MLShapedArray<Float>(multiArray)
        let tensor = MLTensor(shapedArray)
        return tensor
    }

    var featureNames: Set<String> {
        provider.featureNames
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        provider.featureValue(for: featureName)
    }

    required init(features: MLFeatureProvider) {
        provider = features
    }
}

/// Class for model loading and prediction
extension SpleeterModelProtocol {
    /// Construct Spleeter2Model instance with explicit path to mlmodelc file
    /// - Parameter modelURL: The file url of the model
    /// - Throws: An error that describes the problem
    init(contentsOf modelURL: URL) throws {
        let configuration = MLModelConfiguration()
        #if os(iOS)
        if #available(iOS 27, *) { configuration.computeUnits = .cpuOnly }
        #endif
        try self.init(model: MLModel(contentsOf: modelURL, configuration: configuration))
    }

    /// Make an asynchronous prediction using the structured interface
    ///
    /// It uses the default function if the model has multiple functions.
    ///
    /// - Parameters:
    ///   - magnitude: 2 × frequencyLimit × length 3-dimensional tensor of floats
    ///   - options: Prediction options
    /// - Throws: An error that describes the problem
    /// - Returns: The result of the prediction as Spleeter2ModelOutput
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func prediction(
        magnitude: MLTensor,
        options: MLPredictionOptions = MLPredictionOptions()
    ) async throws -> MLTensorStems {
        let input = await SpleeterModelInput(magnitude: magnitude)
        let outFeatures = try await model.prediction(from: input, options: options)
        let output = SpleeterModelOutput(features: outFeatures)
        return try mapStems(maskFeatureNames) {
            try output.maskTensor(for: $0)
        }
    }
}
