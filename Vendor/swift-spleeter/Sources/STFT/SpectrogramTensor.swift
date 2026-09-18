import CoreML

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
struct SpectrogramTensor {
    /// Complex spectrogram with shape (F, T, 2)
    let complex: MLTensor

    /// Magnitude spectrogram with shape (F, T)
    var magnitude: MLTensor {
        complex.squared().sum(alongAxes: 2).squareRoot()
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension SpectrogramTensor {
    /// - Parameters:
    ///   - realFrames: Real part of spectrogram with shape (T, F)
    ///   - imagFrames: Imaginary part of spectrogram with shape (T, F)
    init(realFrames: [[Float]], imagFrames: [[Float]]) {
        let realTensor = MLTensor(realFrames.map(MLTensor.init), alongAxis: 1) // (F, T)
        let imagTensor = MLTensor(imagFrames.map(MLTensor.init), alongAxis: 1) // (F, T)

        complex = MLTensor([realTensor, imagTensor], alongAxis: 2)
    }

    init(_ spectrogram: Spectrogram) {
        self.init(
            realFrames: spectrogram.realFrames,
            imagFrames: spectrogram.imagFrames
        )
    }
}
