/// A generic container holding values representing 4 separated audio stems: vocals, drums, bass and other.
public struct Stems4<Value>: StemsProtocol {
    /// The value associated with the vocals stem.
    public let vocals: Value

    /// The value associated with the drums stem.
    public let drums: Value

    /// The value associated with the bass stem.
    public let bass: Value

    /// The value associated with the other stem.
    public let other: Value

    /// Initializes a new instance with given vocals, drums, bass and other values.
    ///
    /// - Parameters:
    ///   - vocals: The value for the vocals stem.
    ///   - drums: The value for the drums stem.
    ///   - bass: The value for the bass stem.
    ///   - other: The value for the other stem.
    public init(vocals: Value, drums: Value, bass: Value, other: Value) {
        self.vocals = vocals
        self.drums = drums
        self.bass = bass
        self.other = other
    }
}

extension Stems4 {
    /// The values of the stems as an array.
    public var values: [Value] { [vocals, drums, bass, other] }

    /// Transforms all stem values synchronously using a throwing closure.
    ///
    /// - Parameter transform: A closure that transforms a `Value` into another type.
    /// - Throws: Rethrows any error thrown by the transform closure.
    /// - Returns: A new `Stems4` instance with transformed values.
    public func mapStems<Transformed>(
        _ transform: (Value) throws -> Transformed
    ) rethrows -> Stems4<Transformed> {
        try Stems4<Transformed>(
            vocals: transform(vocals),
            drums: transform(drums),
            bass: transform(bass),
            other: transform(other)
        )
    }

    /// Transforms all stem values asynchronously using a throwing closure.
    ///
    /// - Parameter transform: An async closure that transforms a `Value` into another type.
    /// - Throws: Rethrows any error thrown by the transform closure.
    /// - Returns: A new `Stems4` instance with asynchronously transformed values.
    public func asyncMapStems<Transformed>(
        _ transform: (Value) async throws -> Transformed
    ) async rethrows -> Stems4<Transformed> {
        try await Stems4<Transformed>(
            vocals: transform(vocals),
            drums: transform(drums),
            bass: transform(bass),
            other: transform(other)
        )
    }
}
