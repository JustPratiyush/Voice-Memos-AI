import Foundation

public struct Recording: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var duration: TimeInterval
    public var filename: String
    public var waveform: [Float]
    public var folderID: UUID?
    public var isFavorite: Bool
    public var deletedAt: Date?
    public var playbackRate: Float
    public var skipSilence: Bool
    public var enhanceRecording: Bool
    public var originalFilename: String?
    public var originalDuration: TimeInterval?
    public var originalWaveform: [Float]?
    public var transcript: String?

    public init(id: UUID = UUID(), title: String, createdAt: Date = Date(),
                duration: TimeInterval, filename: String, waveform: [Float] = [],
                folderID: UUID? = nil, isFavorite: Bool = false, deletedAt: Date? = nil,
                playbackRate: Float = 1, skipSilence: Bool = false,
                enhanceRecording: Bool = false, originalFilename: String? = nil,
                originalDuration: TimeInterval? = nil, originalWaveform: [Float]? = nil,
                transcript: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.filename = filename
        self.waveform = waveform
        self.folderID = folderID
        self.isFavorite = isFavorite
        self.deletedAt = deletedAt
        self.playbackRate = playbackRate
        self.skipSilence = skipSilence
        self.enhanceRecording = enhanceRecording
        self.originalFilename = originalFilename
        self.originalDuration = originalDuration
        self.originalWaveform = originalWaveform
        self.transcript = transcript
    }
}

public struct RecordingFolder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public init(id: UUID = UUID(), title: String) { self.id = id; self.title = title }
}

public enum LibraryFilter: Hashable, Sendable {
    case all
    case favorites
    case recentlyDeleted
    case folder(UUID)
}

public struct CapturedRecording: Sendable {
    public let url: URL
    public let duration: TimeInterval
    public let waveform: [Float]
    public init(url: URL, duration: TimeInterval, waveform: [Float]) {
        self.url = url; self.duration = duration; self.waveform = waveform
    }
}

public typealias EditedAudio = CapturedRecording

public enum VoiceMemosError: LocalizedError {
    case microphoneDenied
    case recordingFailed
    case noAudio
    case invalidRange
    case corruptLibrary(String)
    case exportFailed(String)
    case libraryReadOnly

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is required to record. Allow access in System Settings or Settings → Privacy & Security → Microphone."
        case .recordingFailed: return "The microphone could not start recording."
        case .noAudio: return "This file does not contain readable audio."
        case .invalidRange: return "Choose a nonempty range inside the recording."
        case .corruptLibrary(let detail): return "The recording library could not be opened. Your audio files have been kept. \(detail)"
        case .exportFailed(let detail): return "Audio export failed. \(detail)"
        case .libraryReadOnly: return "The library could not be loaded, so changes are disabled to protect your recordings."
        }
    }
}

public enum RecordingTime {
    public static func string(_ seconds: TimeInterval, fractional: Bool = false) -> String {
        let value = seconds.isFinite ? max(0, seconds) : 0
        let hours = Int(value) / 3600
        let minutes = Int(value) / 60 % 60
        let whole = Int(value) % 60
        let base = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, whole)
            : String(format: "%d:%02d", minutes, whole)
        return fractional ? base + String(format: ".%02d", Int(value * 100) % 100) : base
    }
}
