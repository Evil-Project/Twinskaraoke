/// A generic container holding a pair of values representing separated audio stems: vocals and accompaniment.
public struct Stems2<Value>: StemsProtocol {
    /// The value associated with the vocals stem.
    public let vocals: Value

    /// The value associated with the accompaniment stem.
    public let accompaniment: Value

    /// Initializes a new instance with given vocals and accompaniment values.
    ///
    /// - Parameters:
    ///   - vocals: The value for the vocals stem.
    ///   - accompaniment: The value for the accompaniment stem.
    public init(vocals: Value, accompaniment: Value) {
        self.vocals = vocals
        self.accompaniment = accompaniment
    }
}

extension Stems2 {
    /// The values of the stems as an array.
    public var values: [Value] { [vocals, accompaniment] }

    /// Transforms both vocals and accompaniment values synchronously using a throwing closure.
    ///
    /// - Parameter transform: A closure that transforms a `Value` into another type.
    /// - Throws: Rethrows any error thrown by the transform closure.
    /// - Returns: A new `Stems2` instance with transformed values.
    public func mapStems<Transformed>(
        _ transform: (Value) throws -> Transformed
    ) rethrows -> Stems2<Transformed> {
        try Stems2<Transformed>(
            vocals: transform(vocals),
            accompaniment: transform(accompaniment)
        )
    }

    /// Transforms both vocals and accompaniment values asynchronously using a throwing closure.
    ///
    /// - Parameter transform: An async closure that transforms a `Value` into another type.
    /// - Throws: Rethrows any error thrown by the transform closure.
    /// - Returns: A new `Stems2` instance with asynchronously transformed values.
    public func asyncMapStems<Transformed>(
        _ transform: (Value) async throws -> Transformed
    ) async rethrows -> Stems2<Transformed> {
        try await Stems2<Transformed>(
            vocals: transform(vocals),
            accompaniment: transform(accompaniment)
        )
    }
}
