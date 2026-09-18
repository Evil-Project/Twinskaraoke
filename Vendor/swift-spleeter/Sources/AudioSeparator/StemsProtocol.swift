/// Protocol defining audio stems.
public protocol StemsProtocol {
    /// The type of value contained in the stems.
    associatedtype Value

    /// The values of the stems as an array.
    var values: [Value] { get }
}
