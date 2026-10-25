import AVFoundation
import Combine
import Foundation

@MainActor
public final class AudioController: NSObject, ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var isPaused = false
    @Published public private(set) var isPlaying = false
    @Published public private(set) var isPreparingPlayback = false
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0
    @Published public private(set) var levels: [Float] = []
    @Published public var errorMessage: String?
    @Published public private(set) var activeRecordingID: UUID?
    @Published public private(set) var rate: Float = 1
    @Published public private(set) var skipSilence = false
    @Published public private(set) var enhanceRecording = false

    private var recorder: AVAudioRecorder?
    private var captureURL: URL?
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    private var silentRanges: [Range<TimeInterval>] = []
    private var playbackRequest: UUID?
    private var enhancedURL: URL?
    private var playingSourceURL: URL?
    private var playingRecording: Recording?
    private var isRequestingMicrophone = false
    private var recordingRequest: UUID?

    public override init() {
        super.init()
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: nil)
        #endif
    }

    deinit { ticker?.cancel(); NotificationCenter.default.removeObserver(self) }

    public func startRecording(lossless: Bool = false) async {
        guard !isRecording, !isRequestingMicrophone else { return }
        errorMessage = nil
        isRequestingMicrophone = true
        let request = UUID()
        recordingRequest = request
        defer { isRequestingMicrophone = false }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard recordingRequest == request, !Task.isCancelled else { return }
        guard granted else { errorMessage = VoiceMemosError.microphoneDenied.localizedDescription; return }
        stopPlayback()
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            #endif
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-capture-\(UUID().uuidString).m4a")
            let recordingURL = lossless ? url.deletingPathExtension().appendingPathExtension("caf") : url
            captureURL = recordingURL
            let settings: [String: Any] = lossless ? [
                AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ] : [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else { throw VoiceMemosError.recordingFailed }
            self.recorder = recorder
            captureURL = recordingURL
            currentTime = 0
            duration = 0
            levels = []
            isRecording = true
            isPaused = false
            startTicker()
        } catch { cancelRecording(); errorMessage = error.localizedDescription }
    }

    public func pauseRecording() {
        guard isRecording, !isPaused else { return }
        recorder?.pause()
        isPaused = true
        ticker?.cancel()
    }
    public func resumeRecording() {
        guard isRecording, isPaused else { return }
        guard recorder?.record() == true else {
            errorMessage = VoiceMemosError.recordingFailed.localizedDescription
            return
        }
        isPaused = false
        startTicker()
    }

    /// The returned temporary file belongs to the caller and can be removed after importing.
    public func finishRecording() async -> CapturedRecording? {
        recordingRequest = nil
        guard isRecording, let url = captureURL else { return nil }
        recorder?.stop()
        recorder = nil
        captureURL = nil
        isRecording = false
        isPaused = false
        ticker?.cancel()
        deactivateAudioSession()
        do {
            let analysis = try await AudioAnalyzer.analyzeAsync(url: url)
            duration = analysis.duration
            currentTime = 0
            return CapturedRecording(url: url, duration: analysis.duration, waveform: analysis.waveform)
        } catch {
            errorMessage = error.localizedDescription
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    public func cancelRecording() {
        recordingRequest = nil
        recorder?.stop()
        recorder = nil
        if let captureURL { try? FileManager.default.removeItem(at: captureURL) }
        captureURL = nil
        isRecording = false
        isPaused = false
        currentTime = 0
        duration = 0
        levels = []
        ticker?.cancel()
        deactivateAudioSession()
    }

    public func play(_ recording: Recording, url: URL) {
        guard !isRecording else { return }
        let resumeTime = activeRecordingID == recording.id && currentTime < duration - 0.02 ? currentTime : 0
        if activeRecordingID == recording.id, playingSourceURL == url,
           enhanceRecording == recording.enhanceRecording, let player {
            rate = min(2, max(0.5, recording.playbackRate))
            player.rate = rate
            skipSilence = recording.skipSilence
            playingRecording = recording
            player.currentTime = resumeTime
            do {
                try activatePlaybackSession()
                isPlaying = player.play()
                if !isPlaying { throw VoiceMemosError.noAudio }
                startTicker()
            } catch { errorMessage = error.localizedDescription }
            return
        }
        stopPlayback()
        activeRecordingID = recording.id
        playingSourceURL = url
        playingRecording = recording
        duration = recording.duration
        currentTime = resumeTime
        rate = min(2, max(0.5, recording.playbackRate))
        skipSilence = recording.skipSilence
        enhanceRecording = recording.enhanceRecording
        isPreparingPlayback = true
        let request = UUID()
        playbackRequest = request
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let analysis = try AudioAnalyzer.analyze(url: url)
                    let enhanced = recording.enhanceRecording ? try SpeechEnhancer.render(url: url) : nil
                    return (analysis, enhanced)
                }.value
                guard playbackRequest == request else {
                    if let url = result.1 { try? FileManager.default.removeItem(at: url) }
                    return
                }
                try activatePlaybackSession()
                enhancedURL = result.1
                silentRanges = result.0.silentRanges
                let player = try AVAudioPlayer(contentsOf: result.1 ?? url)
                player.delegate = self
                player.enableRate = true
                player.rate = rate
                player.currentTime = min(currentTime, player.duration)
                player.prepareToPlay()
                self.player = player
                duration = player.duration
                isPlaying = player.play()
                isPreparingPlayback = false
                if !isPlaying { throw VoiceMemosError.noAudio }
                startTicker()
            } catch {
                guard playbackRequest == request else { return }
                isPreparingPlayback = false
                isPlaying = false
                deactivateAudioSession()
                errorMessage = error.localizedDescription
            }
        }
    }

    public func pausePlayback() {
        player?.pause()
        isPlaying = false
        if !isRecording { ticker?.cancel() }
        if isPreparingPlayback {
            playbackRequest = nil
            isPreparingPlayback = false
        }
    }
    public func seek(to time: TimeInterval) {
        guard time.isFinite else { return }
        currentTime = min(duration, max(0, time))
        player?.currentTime = currentTime
    }
    public func skip(seconds: TimeInterval) { seek(to: currentTime + seconds) }
    public func stopPlayback() {
        playbackRequest = nil
        player?.stop()
        player = nil
        isPlaying = false
        isPreparingPlayback = false
        if !isRecording {
            currentTime = 0
            duration = 0
        }
        activeRecordingID = nil
        playingSourceURL = nil
        playingRecording = nil
        silentRanges = []
        if !isRecording {
            ticker?.cancel()
            deactivateAudioSession()
        }
        if let enhancedURL { try? FileManager.default.removeItem(at: enhancedURL) }
        enhancedURL = nil
    }
    public func setRate(_ rate: Float) {
        guard rate.isFinite else { return }
        self.rate = min(2, max(0.5, rate))
        player?.rate = self.rate
    }
    public func setSkipSilence(_ enabled: Bool) { skipSilence = enabled }
    public func setEnhanceRecording(_ enabled: Bool) {
        guard enhanceRecording != enabled else { return }
        enhanceRecording = enabled
        guard var recording = playingRecording, let url = playingSourceURL else { return }
        recording.enhanceRecording = enabled
        recording.playbackRate = rate
        recording.skipSilence = skipSilence
        let wasPlaying = isPlaying || isPreparingPlayback
        let savedTime = currentTime
        // Force reprocessing after changing the DSP option.
        player?.stop()
        player = nil
        if wasPlaying {
            play(recording, url: url)
            seek(to: savedTime)
        } else {
            playingRecording = recording
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                self?.tick()
                do { try await Task.sleep(nanoseconds: 50_000_000) }
                catch { return }
            }
        }
    }
    private func tick() {
        if isRecording, !isPaused, let recorder {
            recorder.updateMeters()
            currentTime = recorder.currentTime
            duration = currentTime
            levels.append(min(1, max(0.015, pow(10, recorder.averagePower(forChannel: 0) / 40))))
        } else if isPlaying, let player {
            var time = player.currentTime
            if skipSilence, let range = silentRanges.first(where: { $0.contains(time) }),
               time >= range.lowerBound + 0.08, time < range.upperBound - 0.08 {
                time = max(time, range.upperBound - 0.06)
                player.currentTime = time
            }
            currentTime = time
        }
    }
    private func activatePlaybackSession() throws {
        #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    #if os(iOS)
    @objc private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        if isRecording { pauseRecording() }
        pausePlayback()
    }
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        pausePlayback()
    }
    #endif
}

extension AudioController: AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == identity else { return }
            self.isPlaying = false
            self.currentTime = self.duration
            self.ticker?.cancel()
            self.deactivateAudioSession()
        }
    }
    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let identity = ObjectIdentifier(player)
        let message = error?.localizedDescription ?? "This recording could not be played."
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == identity else { return }
            self.pausePlayback()
            self.deactivateAudioSession()
            self.errorMessage = message
        }
    }
    nonisolated public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let identity = ObjectIdentifier(recorder)
        let message = error?.localizedDescription ?? "Recording was interrupted by an audio encoding error."
        Task { @MainActor [weak self] in
            guard let self, self.recorder.map(ObjectIdentifier.init) == identity else { return }
            self.pauseRecording()
            self.errorMessage = message
        }
    }
    nonisolated public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, self.recorder.map(ObjectIdentifier.init) == identity, self.isRecording else { return }
            self.isPaused = true
            self.errorMessage = "Recording stopped unexpectedly. Choose Done to save the audio captured so far."
        }
    }
}
