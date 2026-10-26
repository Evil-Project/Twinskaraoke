import Accelerate
@preconcurrency import AVFoundation
import Foundation

nonisolated enum BPMDetector {
    static func detect(url: URL) async -> Double? {
        let worker = Task.detached(priority: .utility) { () -> Double? in
            let asset = AVURLAsset(url: url)
            guard !Task.isCancelled,
                  let track = try? await asset.loadTracks(withMediaType: .audio).first
            else { return nil }
            let duration = await (try? asset.load(.duration)) ?? .invalid
            guard !Task.isCancelled else { return nil }
            return detectSync(asset: asset, track: track, duration: duration)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static let analysisSR: Double = 22050

    private static let hopSize: Int = 256

    private static let windowSize: Int = 1024

    private static let analysisSeconds: Double = 30

    private static let minBPM: Double = 60

    private static let maxBPM: Double = 200

    private static let confidenceThreshold: Float = 1.4

    private static func detectSync(asset: AVURLAsset, track: AVAssetTrack, duration: CMTime) -> Double? {
        guard !Task.isCancelled else { return nil }
        guard let samples = loadMonoSamples(asset: asset, track: track, duration: duration) else { return nil }
        guard !Task.isCancelled, samples.count > windowSize else { return nil }

        let envelope = onsetEnvelope(samples)
        guard !Task.isCancelled, envelope.count > 2 else { return nil }

        return bpmFromAutocorrelation(envelope)
    }

    private static func loadMonoSamples(asset: AVURLAsset, track: AVAssetTrack, duration: CMTime) -> [Float]? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: analysisSR,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)

        let totalSeconds = duration.seconds
        guard totalSeconds.isFinite, totalSeconds > 0 else {
            let cap = Int(analysisSeconds * analysisSR) + 8192
            return readAllSamples(reader: reader, output: output, maxFrames: cap)
        }
        guard totalSeconds > 5 else {
            let cap = Int(totalSeconds * analysisSR) + 8192
            return readAllSamples(reader: reader, output: output, maxFrames: cap)
        }
        let analysisLen = min(analysisSeconds, totalSeconds * 0.6)
        let startTime = max(0, (totalSeconds - analysisLen) / 2)
        let endTime = startTime + analysisLen
        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 44100),
            end: CMTime(seconds: endTime, preferredTimescale: 44100)
        )
        reader.timeRange = timeRange

        let maxFrames = Int(analysisLen * analysisSR) + 8192
        return readAllSamples(reader: reader, output: output, maxFrames: maxFrames)
    }

    private static func readAllSamples(
        reader: AVAssetReader, output: AVAssetReaderTrackOutput, maxFrames: Int?
    ) -> [Float]? {
        guard reader.startReading() else { return nil }
        var all = [Float]()
        let cap = maxFrames ?? Int.max
        while reader.status == .reading {
            guard !Task.isCancelled else {
                reader.cancelReading()
                return nil
            }
            guard let sb = output.copyNextSampleBuffer(),
                  let bb = CMSampleBufferGetDataBuffer(sb)
            else { break }
            let sampleCount = CMSampleBufferGetNumSamples(sb)
            var length = 0
            var dataPtr: UnsafeMutablePointer<Int8>?
            guard
                CMBlockBufferGetDataPointer(
                    bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                    dataPointerOut: &dataPtr
                ) == noErr,
                let dataPtr
            else { continue }
            let availableSamples = length / MemoryLayout<Float>.stride
            let toAppend = min(sampleCount, availableSamples, cap - all.count)
            guard toAppend > 0 else { break }
            let floatPtr = UnsafeRawPointer(dataPtr).bindMemory(to: Float.self, capacity: toAppend)
            all.append(contentsOf: UnsafeBufferPointer(start: floatPtr, count: toAppend))
            if all.count >= cap { break }
        }
        return all.isEmpty ? nil : all
    }

    private static func onsetEnvelope(_ samples: [Float]) -> [Float] {
        let frameCount = (samples.count - windowSize) / hopSize + 1
        guard frameCount > 1 else { return [] }

        var rms = [Float](repeating: 0, count: frameCount)
        for i in 0 ..< frameCount {
            guard !Task.isCancelled else { return [] }
            let offset = i * hopSize
            let end = min(offset + windowSize, samples.count)
            let count = end - offset
            guard count > 0 else { continue }
            var val: Float = 0
            samples.withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress! + offset, 1, &val, vDSP_Length(count))
            }
            rms[i] = val
        }

        var onset = [Float](repeating: 0, count: frameCount - 1)
        for i in 0 ..< onset.count {
            let diff = rms[i + 1] - rms[i]
            onset[i] = max(0, diff)
        }
        return onset
    }

    private static func bpmFromAutocorrelation(_ envelope: [Float]) -> Double? {
        let n = envelope.count
        let onsetSR = analysisSR / Double(hopSize)

        let minLag = Int(onsetSR * 60.0 / maxBPM)
        let maxLag = Int(onsetSR * 60.0 / minBPM)
        guard minLag >= 1, maxLag < n, minLag < maxLag else { return nil }

        let lagCount = maxLag - minLag + 1
        var acf = [Float](repeating: 0, count: lagCount)

        envelope.withUnsafeBufferPointer { buf in
            for i in 0 ..< lagCount {
                guard !Task.isCancelled else { return }
                let lag = minLag + i
                let overlapLen = n - lag
                guard overlapLen > 0 else { continue }
                var dot: Float = 0
                vDSP_dotpr(
                    buf.baseAddress!, 1,
                    buf.baseAddress! + lag, 1,
                    &dot,
                    vDSP_Length(overlapLen)
                )
                acf[i] = dot / Float(overlapLen)
            }
        }
        guard !Task.isCancelled else { return nil }

        var peakVal: Float = 0
        var peakIdx: vDSP_Length = 0
        vDSP_maxvi(acf, 1, &peakVal, &peakIdx, vDSP_Length(lagCount))

        var sorted = acf
        vDSP_vsort(&sorted, vDSP_Length(lagCount), 1)
        let medianVal = sorted[lagCount / 2]
        guard medianVal > 0, peakVal / medianVal >= confidenceThreshold else { return nil }

        let bestLag = minLag + Int(peakIdx)
        guard bestLag > 0 else { return nil }
        let bpm = onsetSR * 60.0 / Double(bestLag)

        return normalizedBPM(bpm)
    }

    private static func normalizedBPM(_ raw: Double) -> Double? {
        if raw >= minBPM, raw <= maxBPM { return raw }
        let doubled = raw * 2
        if doubled >= minBPM, doubled <= maxBPM { return doubled }
        let halved = raw / 2
        if halved >= minBPM, halved <= maxBPM { return halved }
        return nil
    }
}
