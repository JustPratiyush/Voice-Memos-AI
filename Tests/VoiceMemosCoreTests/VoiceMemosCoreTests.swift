import AVFoundation
#if !CORE_STANDALONE_TESTS
import XCTest
@testable import VoiceMemosCore
#endif

final class VoiceMemosCoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceMemosTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func audio(in directory: URL, duration: Double = 2,
                       sample: (Double) -> Float = { Float(sin($0 * 2 * .pi * 440) * 0.3) }) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(duration * 44_100))!
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            buffer.floatChannelData![0][frame] = sample(Double(frame) / 44_100)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func testAnalysisIdentifiesSilenceAndProducesBoundedWaveform() throws {
        let directory = try temporaryDirectory()
        let url = try audio(in: directory) { time in
            time > 0.5 && time < 1.5 ? 0 : Float(sin(time * 2 * .pi * 440) * 0.4)
        }
        let result = try AudioAnalyzer.analyze(url: url, peakCount: 200)
        XCTAssertEqual(result.duration, 2, accuracy: 0.001)
        XCTAssertEqual(result.waveform.count, 200)
        XCTAssertTrue(result.waveform.allSatisfy { (0...1).contains($0) })
        XCTAssertEqual(result.silentRanges.count, 1)
        XCTAssertTrue(result.silentRanges[0].contains(1))
        XCTAssertLessThan(result.waveform[100], 0.001)
        XCTAssertGreaterThan(result.waveform[10], 0.4)
    }

    @MainActor
    func testLibraryPersistsFoldersSearchFavoritesAndRecovery() async throws {
        let directory = try temporaryDirectory()
        let libraryDirectory = directory.appendingPathComponent("Library")
        let store = LibraryStore(directory: libraryDirectory)
        let source = try audio(in: directory)
        let sourceBytes = try Data(contentsOf: source)
        let folder = try XCTUnwrap(store.createFolder(title: "  Interviews  "))
        let record = try await store.addRecording(url: source, title: "  Project discussion  ", folderID: folder.id)
        XCTAssertEqual(record.title, "Project discussion")
        XCTAssertEqual(folder.title, "Interviews")
        XCTAssertNotEqual(source, store.url(for: record))
        var changed = record
        changed.transcript = "The delivery deadline is Friday."
        store.update(changed)
        store.toggleFavorite(record)
        XCTAssertEqual(store.recordings(in: .all, query: "FRIDAY").count, 1)
        XCTAssertEqual(store.recordings(in: .favorites).count, 1)
        XCTAssertEqual(store.recordings(in: .folder(folder.id)).count, 1)
        store.trash(record)
        XCTAssertTrue(store.recordings(in: .all).isEmpty)
        XCTAssertEqual(store.recordings(in: .recentlyDeleted).count, 1)
        store.recover(record)
        store.deleteFolder(folder)
        let reloaded = LibraryStore(directory: libraryDirectory)
        XCTAssertNil(reloaded.errorMessage)
        XCTAssertTrue(reloaded.folders.isEmpty)
        XCTAssertNil(reloaded.recordings.first?.folderID)
        XCTAssertTrue(reloaded.recordings.first?.isFavorite == true)
        XCTAssertEqual(reloaded.recordings.first?.transcript, changed.transcript)
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
        let disposableFolder = try XCTUnwrap(reloaded.createFolder(title: "Archive"))
        reloaded.move(record, to: disposableFolder.id)
        reloaded.deleteFolder(disposableFolder, trashRecordings: true)
        let afterFolderDeletion = LibraryStore(directory: libraryDirectory)
        XCTAssertTrue(afterFolderDeletion.folders.isEmpty)
        XCTAssertEqual(afterFolderDeletion.recordings(in: .recentlyDeleted).map(\.id), [record.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: afterFolderDeletion.url(for: record).path))
    }

    @MainActor
    func testDuplicateOwnsItsAudioAndPermanentDeleteRequiresTrash() async throws {
        let directory = try temporaryDirectory()
        let store = LibraryStore(directory: directory.appendingPathComponent("Library"))
        let record = try await store.addRecording(url: audio(in: directory), title: "Interview")
        let copy = try XCTUnwrap(store.duplicate(record))
        XCTAssertNotEqual(record.id, copy.id)
        XCTAssertNotEqual(record.filename, copy.filename)
        XCTAssertEqual(try Data(contentsOf: store.url(for: record)), try Data(contentsOf: store.url(for: copy)))
        store.permanentlyDelete(record)
        XCTAssertEqual(store.recordings.count, 2)
        store.trash(record)
        store.permanentlyDelete(record)
        XCTAssertEqual(store.recordings.map(\.id), [copy.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: record).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: copy).path))
    }

    @MainActor
    func testFailedMetadataWriteLeavesInMemoryStateUnchanged() throws {
        let directory = try temporaryDirectory()
        let store = LibraryStore(directory: directory)
        let metadata = directory.appendingPathComponent("Library.json")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: false)
        XCTAssertNil(store.createFolder(title: "Must not persist"))
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testCorruptLibraryCannotBeOverwritten() throws {
        let directory = try temporaryDirectory()
        let metadata = directory.appendingPathComponent("Library.json")
        let damaged = Data("unreadable library - preserve me".utf8)
        try damaged.write(to: metadata)
        let store = LibraryStore(directory: directory)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.createFolder(title: "No overwrite"))
        XCTAssertEqual(try Data(contentsOf: metadata), damaged)
    }

    @MainActor
    func testTrashRetentionKeepsActiveAndUnexpiredAudio() async throws {
        let directory = try temporaryDirectory()
        let store = LibraryStore(directory: directory.appendingPathComponent("Library"))
        let active = try await store.addRecording(url: audio(in: directory), title: "Keep")
        let expired = try XCTUnwrap(store.duplicate(active))
        store.trash(expired)
        let deletedAt = try XCTUnwrap(store.recording(id: expired.id)?.deletedAt)
        XCTAssertEqual(store.purgeExpiredDeleted(retentionDays: nil, now: deletedAt.addingTimeInterval(999_999)), 0)
        XCTAssertEqual(store.purgeExpiredDeleted(retentionDays: 1, now: deletedAt.addingTimeInterval(86_399)), 0)
        XCTAssertEqual(store.purgeExpiredDeleted(retentionDays: 1, now: deletedAt.addingTimeInterval(86_400)), 1)
        XCTAssertEqual(store.recordings.map(\.id), [active.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: active).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: expired).path))
        store.trash(active)
        XCTAssertEqual(store.purgeExpiredDeleted(retentionDays: 0), 1)
        XCTAssertTrue(store.recordings.isEmpty)
    }

    @MainActor
    func testLibraryRejectsPathTraversalMetadata() async throws {
        let directory = try temporaryDirectory()
        let libraryDirectory = directory.appendingPathComponent("Library")
        let store = LibraryStore(directory: libraryDirectory)
        _ = try await store.addRecording(url: audio(in: directory), title: "Safe")
        let metadata = libraryDirectory.appendingPathComponent("Library.json")
        var document = try JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as! [String: Any]
        var records = document["recordings"] as! [[String: Any]]
        records[0]["filename"] = "../../other-file.caf"
        document["recordings"] = records
        try JSONSerialization.data(withJSONObject: document).write(to: metadata)
        let invalid = LibraryStore(directory: libraryDirectory)
        XCTAssertTrue(invalid.recordings.isEmpty)
        XCTAssertNotNil(invalid.errorMessage)
        XCTAssertNil(invalid.createFolder(title: "Blocked"))
    }

    @MainActor
    func testTrimRetainsOriginalAndRestoreRecoversExactAudio() async throws {
        let directory = try temporaryDirectory()
        let store = LibraryStore(directory: directory.appendingPathComponent("Library"))
        let record = try await store.addRecording(url: audio(in: directory), title: "Original")
        let originalBytes = try Data(contentsOf: store.url(for: record))
        let edit = try await EditingService.trim(url: store.url(for: record), range: 0.5..<1.5)
        defer { try? FileManager.default.removeItem(at: edit.url) }
        XCTAssertEqual(edit.duration, 1, accuracy: 0.04)
        try store.commitEdit(edit, for: record)
        let edited = try XCTUnwrap(store.recording(id: record.id))
        XCTAssertEqual(edited.originalFilename, record.filename)
        XCTAssertNotEqual(edited.filename, record.filename)
        XCTAssertEqual(try Data(contentsOf: store.url(for: record)), originalBytes)
        store.restoreOriginal(edited)
        let restored = try XCTUnwrap(store.recording(id: record.id))
        XCTAssertNil(restored.originalFilename)
        XCTAssertEqual(restored.duration, record.duration, accuracy: 0.001)
        XCTAssertEqual(try Data(contentsOf: store.url(for: restored)), originalBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: edited).path))
    }

    func testDeleteAndReplaceAudioIntervals() async throws {
        let directory = try temporaryDirectory()
        let source = try audio(in: directory)
        let replacement = try audio(in: directory, duration: 0.5) { Float(sin($0 * 2 * .pi * 880) * 0.3) }
        let removed = try await EditingService.remove(url: source, range: 0.5..<1.5)
        let replaced = try await EditingService.replace(url: source, range: 0.5..<1.5, with: replacement)
        defer {
            try? FileManager.default.removeItem(at: removed.url)
            try? FileManager.default.removeItem(at: replaced.url)
        }
        XCTAssertEqual(removed.duration, 1, accuracy: 0.04)
        XCTAssertEqual(replaced.duration, 1.5, accuracy: 0.04)
        let file = try AVAudioFile(forReading: replaced.url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = buffer.floatChannelData![0]
        func power(at time: Double, frequency: Double) -> Double {
            let start = Int(time * file.processingFormat.sampleRate)
            var real = 0.0
            var imaginary = 0.0
            for frame in start..<(start + 2_048) {
                let phase = Double(frame) / file.processingFormat.sampleRate * 2 * .pi * frequency
                real += Double(samples[frame]) * cos(phase)
                imaginary += Double(samples[frame]) * sin(phase)
            }
            return real * real + imaginary * imaginary
        }
        XCTAssertGreaterThan(power(at: 0.15, frequency: 440), power(at: 0.15, frequency: 880) * 10)
        XCTAssertGreaterThan(power(at: 0.65, frequency: 880), power(at: 0.65, frequency: 440) * 10)
        XCTAssertGreaterThan(power(at: 1.15, frequency: 440), power(at: 1.15, frequency: 880) * 10)
        do {
            _ = try await EditingService.remove(url: source, range: 0..<2)
            XCTFail("Removing the complete recording should be rejected")
        } catch { XCTAssertTrue(error is VoiceMemosError) }
        do {
            _ = try await EditingService.trim(url: source, range: -1..<1)
            XCTFail("Negative ranges should be rejected")
        } catch { XCTAssertTrue(error is VoiceMemosError) }
    }

    func testSpeechEnhancementCreatesSeparateProcessedAudio() throws {
        let directory = try temporaryDirectory()
        let source = try audio(in: directory) { Float(sin($0 * 2 * .pi * 30) * 0.4) }
        let sourceBytes = try Data(contentsOf: source)
        let enhanced = try SpeechEnhancer.render(url: source)
        defer { try? FileManager.default.removeItem(at: enhanced) }
        let original = try AudioAnalyzer.analyze(url: source)
        let processed = try AudioAnalyzer.analyze(url: enhanced)
        XCTAssertEqual(original.duration, processed.duration, accuracy: 0.001)
        XCTAssertLessThan(processed.waveform[100], original.waveform[100] * 0.8)
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
    }

    @MainActor
    func testPlaybackTransportAndCancelledPreparation() async throws {
        let directory = try temporaryDirectory()
        // Silence verifies the real playback transport without emitting sound.
        let source = try audio(in: directory) { _ in 0 }
        let recording = Recording(title: "Transport", duration: 2, filename: source.lastPathComponent)
        let audio = AudioController()
        audio.play(recording, url: source)
        for _ in 0..<100 {
            if !audio.isPreparingPlayback { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(audio.errorMessage)
        XCTAssertTrue(audio.isPlaying)
        XCTAssertEqual(audio.activeRecordingID, recording.id)
        audio.pausePlayback()
        XCTAssertFalse(audio.isPlaying)
        audio.seek(to: 0.75)
        XCTAssertEqual(audio.currentTime, 0.75, accuracy: 0.001)
        audio.skip(seconds: -15)
        XCTAssertEqual(audio.currentTime, 0, accuracy: 0.001)
        audio.skip(seconds: 15)
        XCTAssertEqual(audio.currentTime, 2, accuracy: 0.001)
        audio.setRate(4)
        XCTAssertEqual(audio.rate, 2)
        audio.setRate(-1)
        XCTAssertEqual(audio.rate, 0.5)
        audio.seek(to: 0.5)
        audio.play(recording, url: source)
        XCTAssertTrue(audio.isPlaying)
        XCTAssertEqual(audio.currentTime, 0.5, accuracy: 0.001)
        audio.stopPlayback()
        XCTAssertFalse(audio.isPlaying)
        XCTAssertNil(audio.activeRecordingID)
        XCTAssertEqual(audio.currentTime, 0, accuracy: 0.001)
        audio.play(recording, url: source)
        audio.stopPlayback()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(audio.isPlaying)
        XCTAssertFalse(audio.isPreparingPlayback)
        XCTAssertNil(audio.activeRecordingID)
    }
}
