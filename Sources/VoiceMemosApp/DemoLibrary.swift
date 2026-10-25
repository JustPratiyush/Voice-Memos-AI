import AVFoundation
import Foundation
import VoiceMemosCore

/// Explicit opt-in demo data, stored in a separate temporary library.
/// The audio is synthesized locally; no user's Voice Memos library is touched.
@MainActor
enum DemoLibrary {
    static func populate(_ library: LibraryStore) async {
        guard library.recordings.isEmpty else { return }
        let ideas = library.createFolder(title: "Ideas")
        let work = library.createFolder(title: "Work")
        let examples: [(String, Double, UUID?, Bool)] = [
            ("Morning thoughts", 28.4, ideas?.id, true),
            ("Design review", 42.8, work?.id, false),
            ("A new idea", 16.2, ideas?.id, false),
            ("Weekend plans", 36.6, nil, true)
        ]
        for (index, example) in examples.enumerated() {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString).wav")
            do {
                try await Task.detached { try synthesize(to: url, duration: example.1, seed: index) }.value
                var item = try await library.addRecording(url: url, title: example.0, waveform: [], folderID: example.2)
                item.createdAt = Calendar.current.date(byAdding: .day, value: -index, to: Date()) ?? Date()
                item.isFavorite = example.3
                if index == 0 { item.transcript = "Demo recording. The audio in this sample is a locally generated tone used to test playback, waveform rendering, and editing." }
                library.update(item)
                try? FileManager.default.removeItem(at: url)
            } catch { library.errorMessage = "Could not prepare demo audio: \(error.localizedDescription)" }
        }
    }

    nonisolated private static func synthesize(to url: URL, duration: Double, seed: Int) throws {
        let sampleRate = 22_050.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = Int(duration * sampleRate)
        let capacity = 4096
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity))!
        var offset = 0
        while offset < frames {
            let count = min(capacity, frames - offset)
            buffer.frameLength = AVAudioFrameCount(count)
            let samples = buffer.floatChannelData![0]
            for i in 0..<count {
                let t = Double(offset + i) / sampleRate
                let phrase = sin(t * 1.8 + Double(seed)) * sin(t * 0.47 + 1)
                let syllable = pow(abs(sin(t * 9.3)), 1.4)
                let silence = t.truncatingRemainder(dividingBy: 7) > 5.5
                let envelope = silence ? 0.001 : (0.08 + abs(phrase) * 0.65) * (0.15 + syllable * 0.85)
                let tone = sin(2 * .pi * (170 + Double(seed * 37)) * t)
                    + 0.3 * sin(2 * .pi * 342 * t) + 0.12 * sin(2 * .pi * 681 * t)
                samples[i] = Float(tone * envelope * 0.55)
            }
            try file.write(from: buffer)
            offset += count
        }
    }
}
