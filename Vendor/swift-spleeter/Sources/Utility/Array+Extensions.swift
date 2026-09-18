extension Array where Element: Numeric {
    func paddedOrClamped(to targetLength: Int) -> [Element] {
        if count == targetLength {
            self
        } else if count < targetLength {
            self + Array(repeating: .zero, count: targetLength - count)
        } else {
            Array(prefix(targetLength))
        }
    }
}
