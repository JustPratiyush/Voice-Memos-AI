import Combine
import Foundation
import Speech

/// Transcribes a local recording with Apple's on-device speech recognizer.
/// Unsupported devices or languages never fall back to server recognition.
@MainActor
public final class TranscriptionService: ObservableObject {
    @Published public private(set) var text = ""
    @Published public private(set) var isTranscribing = false
    @Published public private(set) var errorMessage: String?

    private var operationID: UUID?
    private var continuation: CheckedContinuation<String?, Never>?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?

    public init() {}

    /// Starting another transcription cancels the previous one.
    /// Cancellation and failures return nil; partial text remains available for display.
    public func transcribe(url: URL) async -> String? {
        guard !Task.isCancelled else { return nil }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                cancel()
                self.operationID = id
                self.continuation = continuation
                self.text = ""
                self.errorMessage = nil
                self.isTranscribing = true

                guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
                    complete(id, error: "The recording could not be opened.")
                    return
                }

                // This also bounds an unanswered authorization request or a stalled recognizer.
                timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: 180_000_000_000)
                    } catch {
                        return
                    }
                    self?.complete(id, error: "Transcription took too long. Please try again.")
                }

                switch SFSpeechRecognizer.authorizationStatus() {
                case .notDetermined:
                    SFSpeechRecognizer.requestAuthorization { [weak self] status in
                        Task { @MainActor [weak self] in
                            self?.handleAuthorization(status, url: url, id: id)
                        }
                    }
                case let status:
                    handleAuthorization(status, url: url, id: id)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.complete(id)
            }
        }
    }

    public func cancel() {
        guard let id = operationID else { return }
        complete(id)
    }

    private func handleAuthorization(
        _ status: SFSpeechRecognizerAuthorizationStatus,
        url: URL,
        id: UUID
    ) {
        guard operationID == id else { return }
        switch status {
        case .authorized:
            startRecognition(url: url, id: id)
        case .denied:
            complete(id, error: "Allow Speech Recognition in Settings to transcribe recordings.")
        case .restricted:
            complete(id, error: "Speech recognition is restricted on this device.")
        case .notDetermined:
            complete(id, error: "Speech recognition permission has not been granted.")
        @unknown default:
            complete(id, error: "Speech recognition authorization is unavailable.")
        }
    }

    private func startRecognition(url: URL, id: UUID) {
        guard operationID == id else { return }
        guard let recognizer = SFSpeechRecognizer(locale: .current) else {
            complete(id, error: "Speech recognition is unavailable for your current language.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            complete(id, error: "On-device transcription is unavailable for this language or device. Your recording has not been uploaded.")
            return
        }
        guard recognizer.isAvailable else {
            complete(id, error: "On-device speech recognition is currently unavailable. Please try again later.")
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.recognizer = recognizer
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Only send immutable values to the main actor, not the framework's result object.
            let transcription = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.operationID == id else { return }
                if let transcription {
                    self.text = transcription
                }
                if isFinal {
                    let finalText = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if finalText.isEmpty {
                        self.complete(id, error: "No speech was recognized in this recording.")
                    } else {
                        self.complete(id, value: finalText)
                    }
                } else if let failure {
                    self.complete(id, error: "On-device transcription failed. \(failure)")
                }
            }
        }
    }

    /// Invalidating the operation before cancelling its task makes late callbacks harmless.
    /// Every completion path takes and clears the single continuation before resuming it.
    private func complete(_ id: UUID, value: String? = nil, error: String? = nil) {
        guard operationID == id else { return }
        operationID = nil
        let pendingContinuation = continuation
        continuation = nil
        let pendingTask = recognitionTask
        recognitionTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        recognizer = nil
        isTranscribing = false
        errorMessage = error
        pendingTask?.cancel()
        pendingContinuation?.resume(returning: value)
    }
}
