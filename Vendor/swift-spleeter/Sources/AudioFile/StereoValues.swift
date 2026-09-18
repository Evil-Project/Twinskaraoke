/// A generic container representing paired values for left and right audio channels.
public struct StereoValues<Value> {
    /// The value for the left audio channel.
    public let left: Value

    /// The value for the right audio channel.
    public let right: Value
}

extension StereoValues {
    /// Applies a transformation function to both left and right channel values,
    /// returning a new `StereoValues` instance with transformed values.
    ///
    /// - Parameter transform: A closure that takes a `Value` and returns a transformed value.
    /// - Returns: A new `StereoValues` instance containing the transformed left and right values.
    public func mapChannels<Transformed>(
        _ transform: (Value) throws -> Transformed
    ) rethrows -> StereoValues<Transformed> {
        try .init(
            left: transform(left),
            right: transform(right)
        )
    }
}
