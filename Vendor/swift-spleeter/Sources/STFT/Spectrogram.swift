import Accelerate

/// Represents a complex spectrogram with real and imaginary parts.
///
/// The spectrogram is composed of frames, each containing frequency bins of real and imaginary values.
struct Spectrogram {
    /// Real part of the spectrogram with shape (timeFrames, frequencyBins).
    let realFrames: [[Float]]

    /// Imaginary part of the spectrogram with shape (timeFrames, frequencyBins).
    let imagFrames: [[Float]]

    /// Combines real and imaginary frames into an array of `Frame` structs.
    var frames: [Frame] {
        zip(realFrames, imagFrames).map(Frame.init)
    }

    /// A single frame of the spectrogram containing real and imaginary frequency components.
    struct Frame {
        /// Real frequency components of this frame.
        let real: [Float]

        /// Imaginary frequency components of this frame.
        let imag: [Float]

        /// Magnitude spectrum computed from real and imaginary components.
        var magnitude: [Float] {
            vDSP.hypot(real, imag)
        }
    }

    /// Magnitude spectrogram computed by extracting magnitudes from each frame.
    var magnitudeFrames: [[Float]] {
        frames.map(\.magnitude)
    }
}
