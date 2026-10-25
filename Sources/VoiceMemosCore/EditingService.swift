import AVFoundation
import Foundation

/// Edits always create a new temporary audio file. Source recordings remain untouched.
public enum EditingService {
    public static func trim(url: URL, range: Range<TimeInterval>) async throws -> EditedAudio {
        let source = try await Source(url: url)
        let selected = try validated(range, duration: source.duration)
        return try await render(segments: [(source, selected)])
    }

    public static func remove(url: URL, range: Range<TimeInterval>) async throws -> EditedAudio {
        let source = try await Source(url: url)
        let selected = try validated(range, duration: source.duration)
        var segments: [(Source, Range<TimeInterval>)] = []
        if selected.lowerBound > 0 { segments.append((source, 0..<selected.lowerBound)) }
        if selected.upperBound < source.duration { segments.append((source, selected.upperBound..<source.duration)) }
        guard !segments.isEmpty else { throw VoiceMemosError.invalidRange }
        return try await render(segments: segments)
    }

    /// Replaces the selected interval, allowing an empty interval for insertion or append.
    public static func replace(url: URL, range: Range<TimeInterval>, with replacementURL: URL) async throws -> EditedAudio {
        let source = try await Source(url: url)
        let replacement = try await Source(url: replacementURL)
        let selected = try validated(range, duration: source.duration, allowEmpty: true)
        var segments: [(Source, Range<TimeInterval>)] = []
        if selected.lowerBound > 0 { segments.append((source, 0..<selected.lowerBound)) }
        segments.append((replacement, 0..<replacement.duration))
        if selected.upperBound < source.duration { segments.append((source, selected.upperBound..<source.duration)) }
        return try await render(segments: segments)
    }

    private struct Source {
        let asset: AVURLAsset
        let track: AVAssetTrack
        let duration: TimeInterval
        init(url: URL) async throws {
            asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                throw VoiceMemosError.noAudio
            }
            self.track = track
            duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw VoiceMemosError.noAudio }
        }
    }
    private static func validated(_ range: Range<TimeInterval>, duration: TimeInterval,
                                  allowEmpty: Bool = false) throws -> Range<TimeInterval> {
        guard range.lowerBound.isFinite, range.upperBound.isFinite,
              range.lowerBound >= 0, range.upperBound <= duration + 0.05,
              allowEmpty ? range.lowerBound <= range.upperBound : range.lowerBound < range.upperBound else {
            throw VoiceMemosError.invalidRange
        }
        let start = min(duration, range.lowerBound)
        let end = min(duration, range.upperBound)
        guard allowEmpty || end - start >= 0.01 else { throw VoiceMemosError.invalidRange }
        return start..<end
    }
    private static func render(segments: [(Source, Range<TimeInterval>)]) async throws -> EditedAudio {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid) else { throw VoiceMemosError.noAudio }
        var cursor = CMTime.zero
        for (source, range) in segments {
            let start = CMTime(seconds: range.lowerBound, preferredTimescale: 44_100)
            let duration = CMTime(seconds: range.upperBound - range.lowerBound, preferredTimescale: 44_100)
            try track.insertTimeRange(CMTimeRange(start: start, duration: duration), of: source.track, at: cursor)
            cursor = cursor + duration
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw VoiceMemosError.exportFailed("No compatible audio exporter is available.")
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-edit-\(UUID().uuidString).m4a")
        exporter.outputURL = destination
        exporter.outputFileType = .m4a
        let operation = ExportOperation(exporter)
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    operation.session.exportAsynchronously {
                        switch operation.session.status {
                        case .completed: continuation.resume()
                        case .cancelled: continuation.resume(throwing: CancellationError())
                        default: continuation.resume(throwing: VoiceMemosError.exportFailed(
                            operation.session.error?.localizedDescription ?? "The system audio exporter did not complete."))
                        }
                    }
                }
            } onCancel: { operation.session.cancelExport() }
            let analysis = try await AudioAnalyzer.analyzeAsync(url: destination)
            return EditedAudio(url: destination, duration: analysis.duration, waveform: analysis.waveform)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    // Configuration happens before sharing. Completion reads status only once export
    // finishes; cancellation uses AVFoundation's supported cancelExport entry point.
    private final class ExportOperation: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ session: AVAssetExportSession) { self.session = session }
    }
}
