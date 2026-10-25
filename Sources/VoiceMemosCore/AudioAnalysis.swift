import AVFoundation
import Foundation

public struct AudioAnalysis: Sendable {
    public let duration: TimeInterval
    public let waveform: [Float]
    public let silentRanges: [Range<TimeInterval>]
}

/// Audio is read in fixed-size blocks, keeping analysis memory independent of file size.
public enum AudioAnalyzer {
    public static func analyze(url: URL, peakCount: Int = 400) throws -> AudioAnalysis {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard file.length > 0, format.sampleRate > 0, format.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
            throw VoiceMemosError.noAudio
        }
        let duration = Double(file.length) / format.sampleRate
        let count = max(1, min(peakCount, Int(file.length)))
        var peaks = [Float](repeating: 0, count: count)
        var silentStart: TimeInterval?
        var silentRanges: [Range<TimeInterval>] = []
        while file.framePosition < file.length {
            let position = file.framePosition
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
                throw VoiceMemosError.noAudio
            }
            var squareSum: Double = 0
            for frame in 0..<Int(buffer.frameLength) {
                var peak: Float = 0
                for channel in 0..<Int(format.channelCount) {
                    peak = max(peak, abs(channels[channel][frame]))
                }
                let index = min(count - 1, Int((position + Int64(frame)) * Int64(count) / file.length))
                peaks[index] = max(peaks[index], peak)
                squareSum += Double(peak * peak)
            }
            let time = Double(position) / format.sampleRate
            let rms = sqrt(squareSum / Double(buffer.frameLength))
            if rms < 0.009 {
                if silentStart == nil { silentStart = time }
            } else if let start = silentStart {
                if time - start >= 0.4 { silentRanges.append(start..<time) }
                silentStart = nil
            }
        }
        if let start = silentStart, duration - start >= 0.4 {
            silentRanges.append(start..<duration)
        }
        // A square-root scale makes quiet speech visible without changing the audio.
        peaks = peaks.map { min(1, sqrt($0)) }
        return AudioAnalysis(duration: duration, waveform: peaks, silentRanges: silentRanges)
    }

    public static func analyzeAsync(url: URL, peakCount: Int = 400) async throws -> AudioAnalysis {
        try await Task.detached(priority: .userInitiated) {
            try analyze(url: url, peakCount: peakCount)
        }.value
    }
}

/// Local speech enhancement: high-pass rumble removal, low-pass hiss reduction,
/// and a gently smoothed noise gate. This is independent of Apple's private DSP.
enum SpeechEnhancer {
    static func render(url: URL) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
            throw VoiceMemosError.noAudio
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-enhanced-\(UUID().uuidString).caf")
        let output = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        let channelCount = Int(format.channelCount)
        let highRC = 1 / (2 * Double.pi * 95)
        let lowRC = 1 / (2 * Double.pi * 7_000)
        let dt = 1 / format.sampleRate
        let highAlpha = Float(highRC / (highRC + dt))
        let lowAlpha = Float(dt / (lowRC + dt))
        var lastInput = [Float](repeating: 0, count: channelCount)
        var high = lastInput
        var low = lastInput
        var envelope: Float = 0
        var gain: Float = 1
        do {
            while input.framePosition < input.length {
                try input.read(into: buffer)
                guard let channels = buffer.floatChannelData else { throw VoiceMemosError.noAudio }
                for frame in 0..<Int(buffer.frameLength) {
                    var peak: Float = 0
                    for channel in 0..<channelCount { peak = max(peak, abs(channels[channel][frame])) }
                    envelope = max(peak, envelope * 0.9995)
                    let target: Float = envelope < 0.012 ? 0.28 : 1
                    gain += (target - gain) * (target > gain ? 0.01 : 0.0005)
                    for channel in 0..<channelCount {
                        let sample = channels[channel][frame]
                        high[channel] = highAlpha * (high[channel] + sample - lastInput[channel])
                        lastInput[channel] = sample
                        low[channel] += lowAlpha * (high[channel] - low[channel])
                        channels[channel][frame] = tanh(low[channel] * gain * 1.3)
                    }
                }
                try output.write(from: buffer)
            }
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
