/// A generic container holding values representing 5 separated audio stems: vocals, piano, drums, bass and other.
public struct Stems5<Value>: StemsProtocol {
    /// The value associated with the vocals stem.
    public let vocals: Value

    /// The value associated with the drums stem.
    public let piano: Value

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
    ///   - piano: The value for the piano stem.
    ///   - drums: The value for the drums stem.
    ///   - bass: The value for the bass stem.
    ///   - other: The value for the other stem.
    public init(vocals: Value, piano: Value, drums: Value, bass: Value, other: Value) {
        self.vocals = vocals
        self.piano = piano
        self.drums = drums
        self.bass = bass
        self.other = other
    }
}

extension Stems5 {
    /// The values of the stems as an array.
    public var values: [Value] { [vocals, piano, drums, bass, other] }

    /// Transforms all stem values synchronously using a throwing closure.
    ///
    /// - Parameter transform: A closure that transforms a `Value` into another type.
    /// - Throws: Rethrows any error thrown by the transform closure.
    /// - Returns: A new `Stems5` instance with transformed values.
    public func mapStems<Transformed>(
        _ transform: (Value) throws -> Transformed
    ) rethrows -> Stems5<Transformed> {
        try Stems5<Transformed>(
            vocals: transform(vocals),
            piano: transform(piano),
            drums: transform(drums),
            bass: transform(bass),
            other: transform(other)
        )
    }

    /// Transforms all stem values asynchronously using a throwing closure.
    ///
    /// - Parameter transform: An async closure that transforms a `Value` into another type.
    /// - Throws: Rethrows any error thrown by the transform closure.
    /// - Returns: A new `Stems5` instance with asynchronously transformed values.
    public func asyncMapStems<Transformed>(
        _ transform: (Value) async throws -> Transformed
    ) async rethrows -> Stems5<Transformed> {
        try await Stems5<Transformed>(
            vocals: transform(vocals),
            piano: transform(piano),
            drums: transform(drums),
            bass: transform(bass),
            other: transform(other)
        )
    }
}
