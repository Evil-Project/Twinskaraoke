import AVFoundation
import CoreMedia
import Foundation

/// A reader source owns a snapshot of the asset and mix. They are configured
/// before publication and are never mutated by the serial rendering worker.
nonisolated struct AirPlaySampleSource: @unchecked Sendable {
    private let asset: AVAsset
    private let tracks: [AVAssetTrack]
    private let mix: AVAudioMix?
    let duration: TimeInterval
    let timing: AirPlayTransitionTiming?

    static func song(_ url: URL) async throws -> Self {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        guard !tracks.isEmpty, duration.isFinite, duration > 0 else { throw Failure.invalidAudio }
        return Self(asset: asset, tracks: tracks, mix: nil, duration: duration, timing: nil)
    }

    @MainActor
    static func transition(
        outgoing: URL, incoming: URL, fade: TimeInterval, equalPower: Bool, startingAt: TimeInterval = 0
    ) async throws -> Self? {
        guard let prepared = try await AirPlayTransition.prepare(
            outgoing: outgoing, incoming: incoming, fade: fade, equalPower: equalPower, startingAt: startingAt
        ) else { return nil }
        return Self(
            asset: prepared.asset, tracks: prepared.tracks, mix: prepared.mix,
            duration: prepared.duration, timing: prepared.timing
        )
    }

    func makeCursor(at position: CMTime) throws -> Cursor {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.audioMix = mix
        guard reader.canAdd(output) else { throw Failure.invalidAudio }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: position, duration: .positiveInfinity)
        guard reader.startReading() else { throw reader.error ?? Failure.invalidAudio }
        return Cursor(reader: reader, output: output)
    }

    final class Cursor {
        private let reader: AVAssetReader
        private let output: AVAssetReaderAudioMixOutput

        fileprivate init(reader: AVAssetReader, output: AVAssetReaderAudioMixOutput) {
            self.reader = reader
            self.output = output
        }

        func nextBuffer() throws -> CMSampleBuffer? {
            if let buffer = output.copyNextSampleBuffer() { return buffer }
            if reader.status == .failed { throw reader.error ?? Failure.invalidAudio }
            return nil
        }

        func cancel() { reader.cancelReading() }
    }

    enum Failure: Error {
        case invalidAudio
    }
}
