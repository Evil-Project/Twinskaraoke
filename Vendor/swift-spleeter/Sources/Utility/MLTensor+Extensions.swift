import CoreML

enum MLTensorConversionError: Error {
    case invalidShape([Int])
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension MLTensor {
    init(_ stereoTensors: StereoValues<MLTensor>) {
        self.init([
            stereoTensors.left,
            stereoTensors.right,
        ])
    }

    func array2d<Scalar: MLShapedArrayScalar & MLTensorScalar>(
        of scalarType: Scalar.Type = Scalar.self
    ) async throws -> [[Scalar]] {
        guard shape.count == 2 else {
            throw MLTensorConversionError.invalidShape(shape)
        }

        return await (0 ..< shape[0]).asyncMap { i in
            await self[i].shapedArray(of: scalarType).scalars
        }
    }
}
