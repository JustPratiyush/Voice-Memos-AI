import AVFoundation
import Combine
import Foundation

@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var recordings: [Recording] = []
    @Published public private(set) var folders: [RecordingFolder] = []
    @Published public var errorMessage: String?
    public let directory: URL
    private var isReadable = true
    private let fileManager = FileManager.default
    private var metadataURL: URL { directory.appendingPathComponent("Library.json") }
    private var audioDirectory: URL { directory.appendingPathComponent("Recordings", isDirectory: true) }

    private struct Library: Codable {
        var version: Int = 1
        var recordings: [Recording]
        var folders: [RecordingFolder]
    }

    /// This directory is entirely separate from the system Voice Memos library.
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.recreation.VoiceMemos", isDirectory: true)
        do {
            try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: metadataURL.path) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let library = try decoder.decode(Library.self, from: Data(contentsOf: metadataURL))
                guard library.version == 1 else {
                    throw VoiceMemosError.corruptLibrary("Unsupported library version \(library.version).")
                }
                try validate(library)
                recordings = library.recordings
                folders = library.folders
            }
        } catch {
            isReadable = false
            errorMessage = VoiceMemosError.corruptLibrary(error.localizedDescription).localizedDescription
        }
    }

    public func recordings(in filter: LibraryFilter, query: String = "") -> [Recording] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return recordings.filter { recording in
            let matches: Bool
            switch filter {
            case .all: matches = recording.deletedAt == nil
            case .favorites: matches = recording.deletedAt == nil && recording.isFavorite
            case .recentlyDeleted: matches = recording.deletedAt != nil
            case .folder(let id): matches = recording.deletedAt == nil && recording.folderID == id
            }
            return matches && (search.isEmpty || recording.title.localizedStandardContains(search)
                || recording.transcript?.localizedStandardContains(search) == true)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func recording(id: UUID) -> Recording? { recordings.first { $0.id == id } }
    public func url(for recording: Recording) -> URL {
        audioDirectory.appendingPathComponent(recording.filename.lastPathComponent)
    }

    /// Copies a caller-owned file into the library; the source is never removed.
    @discardableResult
    public func addRecording(url source: URL, title: String = "New Recording",
                             waveform: [Float] = [], folderID: UUID? = nil) async throws -> Recording {
        do {
            guard isReadable else { throw VoiceMemosError.libraryReadOnly }
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            let analysis = try await AudioAnalyzer.analyzeAsync(url: source)
            let filename = UUID().uuidString + "." + (source.pathExtension.isEmpty ? "m4a" : source.pathExtension)
            let destination = audioDirectory.appendingPathComponent(filename)
            try fileManager.copyItem(at: source, to: destination)
            let record = Recording(title: cleanTitle(title, fallback: "New Recording"),
                duration: analysis.duration, filename: filename,
                waveform: waveform.isEmpty ? analysis.waveform : waveform,
                folderID: folders.contains(where: { $0.id == folderID }) ? folderID : nil)
            do { try persist(recordings: recordings + [record], folders: folders) }
            catch { try? fileManager.removeItem(at: destination); throw error }
            return record
        } catch { errorMessage = error.localizedDescription; throw error }
    }

    public func rename(_ recording: Recording, to title: String) {
        modify(recording.id) { $0.title = cleanTitle(title, fallback: $0.title) }
    }
    public func toggleFavorite(_ recording: Recording) { modify(recording.id) { $0.isFavorite.toggle() } }
    public func move(_ recording: Recording, to folderID: UUID?) {
        guard folderID == nil || folders.contains(where: { $0.id == folderID }) else { return }
        modify(recording.id) { $0.folderID = folderID }
    }
    public func trash(_ recording: Recording) { modify(recording.id) { $0.deletedAt = Date() } }
    public func recover(_ recording: Recording) { modify(recording.id) { $0.deletedAt = nil } }
    public func update(_ recording: Recording) {
        modify(recording.id) { current in
            // File ownership and original-audio metadata are only changed by commitEdit/restoreOriginal.
            current.title = cleanTitle(recording.title, fallback: current.title)
            current.folderID = folders.contains(where: { $0.id == recording.folderID }) ? recording.folderID : nil
            current.isFavorite = recording.isFavorite
            current.playbackRate = recording.playbackRate.isFinite ? min(2, max(0.5, recording.playbackRate)) : 1
            current.skipSilence = recording.skipSilence
            current.enhanceRecording = recording.enhanceRecording
            current.transcript = recording.transcript
        }
    }

    public func permanentlyDelete(_ recording: Recording) {
        guard let current = self.recording(id: recording.id), current.deletedAt != nil else { return }
        do {
            try persist(recordings: recordings.filter { $0.id != current.id }, folders: folders)
            for filename in Set([current.filename, current.originalFilename].compactMap { $0 }) {
                let path = audioDirectory.appendingPathComponent(filename)
                if fileManager.fileExists(atPath: path.path) { try fileManager.removeItem(at: path) }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Applies the user's retention preference only to this application's trash.
    /// nil keeps deleted recordings indefinitely; zero removes them immediately.
    @discardableResult
    public func purgeExpiredDeleted(retentionDays: Int?, now: Date = Date()) -> Int {
        guard let retentionDays, retentionDays >= 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        let expired = recordings.filter { $0.deletedAt.map { $0 <= cutoff } ?? false }
        var removed = 0
        for recording in expired {
            permanentlyDelete(recording)
            if self.recording(id: recording.id) == nil { removed += 1 }
        }
        return removed
    }

    @discardableResult
    public func duplicate(_ recording: Recording) -> Recording? {
        guard let current = self.recording(id: recording.id) else { return nil }
        do {
            let filename = UUID().uuidString + "." + url(for: current).pathExtension
            let destination = audioDirectory.appendingPathComponent(filename)
            try fileManager.copyItem(at: url(for: current), to: destination)
            var duplicate = current
            duplicate.id = UUID()
            duplicate.title = current.title + " copy"
            duplicate.createdAt = Date()
            duplicate.filename = filename
            duplicate.deletedAt = nil
            duplicate.originalFilename = nil
            duplicate.originalDuration = nil
            duplicate.originalWaveform = nil
            do { try persist(recordings: recordings + [duplicate], folders: folders) }
            catch { try? fileManager.removeItem(at: destination); throw error }
            return duplicate
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    @discardableResult
    public func createFolder(title: String) -> RecordingFolder? {
        let folder = RecordingFolder(title: cleanTitle(title, fallback: "New Folder"))
        do { try persist(recordings: recordings, folders: folders + [folder]); return folder }
        catch { errorMessage = error.localizedDescription; return nil }
    }
    public func renameFolder(_ folder: RecordingFolder, to title: String) {
        var result = folders
        guard let index = result.firstIndex(where: { $0.id == folder.id }) else { return }
        result[index].title = cleanTitle(title, fallback: folder.title)
        do { try persist(recordings: recordings, folders: result) }
        catch { errorMessage = error.localizedDescription }
    }
    /// The folder and affected recordings change in a single metadata transaction.
    /// The caller chooses whether to keep recordings or move them to Recently Deleted.
    public func deleteFolder(_ folder: RecordingFolder, trashRecordings: Bool = false) {
        let deletionDate = Date()
        let result = recordings.map { item in
            var item = item
            if item.folderID == folder.id {
                item.folderID = nil
                if trashRecordings && item.deletedAt == nil { item.deletedAt = deletionDate }
            }
            return item
        }
        do { try persist(recordings: result, folders: folders.filter { $0.id != folder.id }) }
        catch { errorMessage = error.localizedDescription }
    }

    public func commitEdit(_ edit: EditedAudio, for recording: Recording) throws {
        guard var current = self.recording(id: recording.id) else { throw VoiceMemosError.noAudio }
        let filename = UUID().uuidString + "." + edit.url.pathExtension
        let destination = audioDirectory.appendingPathComponent(filename)
        try fileManager.copyItem(at: edit.url, to: destination)
        let oldFilename = current.filename
        if current.originalFilename == nil {
            current.originalFilename = current.filename
            current.originalDuration = current.duration
            current.originalWaveform = current.waveform
        }
        current.filename = filename
        current.duration = edit.duration
        current.waveform = edit.waveform
        current.transcript = nil
        do {
            try persist(recordings: recordings.map { $0.id == current.id ? current : $0 }, folders: folders)
            if oldFilename != current.originalFilename {
                try? fileManager.removeItem(at: audioDirectory.appendingPathComponent(oldFilename))
            }
        } catch {
            try? fileManager.removeItem(at: destination)
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func restoreOriginal(_ recording: Recording) {
        guard var current = self.recording(id: recording.id),
              let filename = current.originalFilename else { return }
        let editedFilename = current.filename
        current.filename = filename
        current.duration = current.originalDuration ?? current.duration
        current.waveform = current.originalWaveform ?? current.waveform
        current.originalFilename = nil
        current.originalDuration = nil
        current.originalWaveform = nil
        current.transcript = nil
        do {
            try persist(recordings: recordings.map { $0.id == current.id ? current : $0 }, folders: folders)
            if editedFilename != filename { try? fileManager.removeItem(at: audioDirectory.appendingPathComponent(editedFilename)) }
        } catch { errorMessage = error.localizedDescription }
    }

    public func export(_ recording: Recording, to destination: URL) throws {
        // Never silently overwrite a caller-owned file.
        let accessed = destination.startAccessingSecurityScopedResource()
        defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
        try fileManager.copyItem(at: url(for: recording), to: destination)
    }

    private func modify(_ id: UUID, _ change: (inout Recording) -> Void) {
        var result = recordings
        guard let index = result.firstIndex(where: { $0.id == id }) else { return }
        change(&result[index])
        do { try persist(recordings: result, folders: folders) }
        catch { errorMessage = error.localizedDescription }
    }
    private func persist(recordings: [Recording], folders: [RecordingFolder]) throws {
        guard isReadable else { throw VoiceMemosError.libraryReadOnly }
        let library = Library(recordings: recordings, folders: folders)
        try validate(library)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(library).write(to: metadataURL, options: .atomic)
        self.recordings = recordings
        self.folders = folders
    }
    private func validate(_ library: Library) throws {
        guard Set(library.recordings.map(\.id)).count == library.recordings.count,
              Set(library.folders.map(\.id)).count == library.folders.count else {
            throw VoiceMemosError.corruptLibrary("Duplicate identifiers.")
        }
        for recording in library.recordings {
            for filename in [recording.filename, recording.originalFilename].compactMap({ $0 }) {
                guard !filename.isEmpty, filename != ".", filename != "..",
                      filename == filename.lastPathComponent else {
                    throw VoiceMemosError.corruptLibrary("Invalid audio filename.")
                }
            }
            guard recording.duration.isFinite, recording.duration >= 0,
                  recording.waveform.allSatisfy({ $0.isFinite }),
                  recording.playbackRate.isFinite else {
                throw VoiceMemosError.corruptLibrary("Invalid audio metadata.")
            }
        }
    }
    private func cleanTitle(_ title: String, fallback: String) -> String {
        let result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? fallback : result
    }
}

private extension String {
    var lastPathComponent: String { (self as NSString).lastPathComponent }
}
