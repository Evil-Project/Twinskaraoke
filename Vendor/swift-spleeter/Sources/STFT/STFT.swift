import Accelerate
import Foundation

/// Errors thrown by STFT during FFT setup or buffer operations.
public enum STFTError: Error {
    /// Failed to create the FFT setup object.
    case failedToCreateFFT

    /// The base address of the input sample buffer is nil.
    case noBaseAddress
}

/// Short-Time Fourier Transform (STFT) utility for converting waveforms to spectrograms and vice versa.
///
/// Supports configurable FFT size, hop length, and frequency bin limits.
/// Uses a Hann window and vDSP for FFT computations.
struct STFT {
    /// Size of the FFT window (must be a power of two).
    let fftSize: Int

    /// Number of samples between adjacent FFT windows.
    let hopLength: Int

    /// Maximum frequency bin index to keep (must be <= Nyquist frequency).
    let frequencyLimit: Int

    /// Window function applied to each frame before FFT.
    let window: [Float]

    private let fft: vDSP.FFT<DSPSplitComplex>

    /// Initializes STFT parameters and prepares the FFT setup.
    ///
    /// - Parameters:
    ///   - fftSize: FFT size, must be a power of two.
    ///   - hopLength: Step size between consecutive frames.
    ///   - frequencyLimit: Number of frequency bins to retain (<= fftSize/2 + 1).
    /// - Throws: `STFTError.failedToCreateFFT` if the FFT object could not be created.
    init(fftSize: Int, hopLength: Int, frequencyLimit: Int) throws {
        precondition(frequencyLimit <= fftSize / 2 + 1, "frequencyLimit must be <= Nyquist")
        precondition((fftSize > 0) && (fftSize & (fftSize - 1) == 0), "fftSize must be power of two")

        self.fftSize = fftSize
        self.hopLength = hopLength
        self.frequencyLimit = frequencyLimit

        window = vDSP
            .window(ofType: Float.self, usingSequence: .hanningNormalized, count: fftSize, isHalfWindow: false)

        guard let fft = vDSP.FFT(
            log2n: vDSP_Length(log2(Double(fftSize))),
            radix: .radix2,
            ofType: DSPSplitComplex.self
        ) else {
            throw STFTError.failedToCreateFFT
        }
        self.fft = fft
    }

    /// Performs the forward STFT on a waveform, returning a complex spectrogram.
    ///
    /// - Parameter waveform: The input audio signal samples.
    /// - Returns: A `Spectrogram` containing complex frequency-domain frames.
    /// - Throws: `STFTError.noBaseAddress` if an internal buffer's base address is nil.
    func forward(waveform: [Float]) throws -> Spectrogram {
        let pad = fftSize / 2
        let paddedWaveform = [Float](repeating: 0, count: pad) + waveform + [Float](repeating: 0, count: pad)

        let frameCount = (paddedWaveform.count - fftSize) / hopLength + 1
        var realFrames: [[Float]] = []
        var imagFrames: [[Float]] = []

        for i in 0 ..< frameCount {
            let start = i * hopLength
            let frame = Array(paddedWaveform[start ..< start + fftSize])

            // Apply window
            let windowed = vDSP.multiply(frame, window)

            var real = [Float](repeating: 0, count: fftSize / 2)
            var imag = [Float](repeating: 0, count: fftSize / 2)

            try real.withUnsafeMutableBufferPointer { realPtr in
                try imag.withUnsafeMutableBufferPointer { imagPtr in
                    guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else {
                        throw STFTError.noBaseAddress
                    }
                    var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                    try windowed.withUnsafeBufferPointer { inputPtr in
                        guard let inputBase = inputPtr.baseAddress else {
                            throw STFTError.noBaseAddress
                        }
                        inputBase.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                        }
                        fft.forward(input: splitComplex, output: &splitComplex)
                    }
                }
            }

            realFrames.append(Array(real.prefix(frequencyLimit)))
            imagFrames.append(Array(imag.prefix(frequencyLimit)))
        }

        return Spectrogram(
            realFrames: realFrames,
            imagFrames: imagFrames
        )
    }

    /// Performs the inverse STFT, reconstructing a time-domain waveform from a spectrogram.
    ///
    /// - Parameter spectrogram: The complex spectrogram to invert.
    /// - Returns: The reconstructed time-domain waveform.
    /// - Throws: `STFTError.noBaseAddress` if an internal buffer's base address is nil.
    func inverse(_ spectrogram: Spectrogram) throws -> [Float] {
        let frameCount = spectrogram.realFrames.count
        let outputLength = hopLength * (frameCount - 1) + fftSize
        var output = [Float](repeating: 0, count: outputLength)
        var windowSum = [Float](repeating: 0, count: outputLength)

        for (i, frame) in spectrogram.frames.enumerated() {
            var real = frame.real + [Float](repeating: 0, count: fftSize / 2 - frame.real.count)
            var imag = frame.imag + [Float](repeating: 0, count: fftSize / 2 - frame.imag.count)
            try real.withUnsafeMutableBufferPointer { realPtr in
                try imag.withUnsafeMutableBufferPointer { imagPtr in
                    guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else {
                        throw STFTError.noBaseAddress
                    }
                    var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                    fft.inverse(input: splitComplex, output: &splitComplex)
                }
            }

            // Scaling
            let scale = Float(1.0 / Float(fftSize))
            let scaledReal = vDSP.multiply(scale, real)
            let scaledImag = vDSP.multiply(scale, imag)

            // [real, real, ...], [imag, imag, ...] -> [real, imag, real, imag, ...]
            var inverseTime = [Float](repeating: 0, count: fftSize)
            for k in 0 ..< fftSize / 2 {
                inverseTime[k * 2] = scaledReal[k]
                inverseTime[k * 2 + 1] = scaledImag[k]
            }

            // Overlap-add windowed signals
            let windowed = vDSP.multiply(inverseTime, window)

            let start = i * hopLength
            for j in 0 ..< fftSize where start + j < output.count {
                output[start + j] += windowed[j]
                windowSum[start + j] += window[j] * window[j]
            }
        }

        // Window scaling
        for i in 0 ..< output.count where windowSum[i] > 1e-8 {
            output[i] /= windowSum[i]
        }

        // Padding trimming and constant scaling
        let pad = fftSize / 2
        return Array(output[pad ..< output.count - pad])
    }
}
