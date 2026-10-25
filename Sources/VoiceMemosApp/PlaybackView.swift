import SwiftUI
import VoiceMemosCore

struct PlaybackView: View {
    let recording: Recording
    var onEdit: () -> Void
    var onDelete: () -> Void
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var audio: AudioController
    @State private var position = 0.0
    @State private var title = ""
    @State private var options = false
    @State private var transcript = false
    @FocusState private var titleFocused: Bool

    private var currentPosition: Binding<Double> {
        Binding(get: { audio.activeRecordingID == recording.id ? audio.currentTime : position },
                set: { position = $0; if audio.activeRecordingID == recording.id { audio.seek(to: $0) } })
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                TextField("New Recording", text: $title)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center).textFieldStyle(.plain)
                    .focused($titleFocused)
                    .onSubmit { library.rename(recording, to: title) }
                    .accessibilityLabel("Recording title")
                Text("\(dateLabel(recording.createdAt))  \(timeLabel(recording.duration))")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.top, 22).padding(.bottom, 30).padding(.horizontal, 20)
            WaveformView(samples: recording.waveform, duration: recording.duration, position: currentPosition)
                .frame(minHeight: 150)
            VStack(spacing: 0) {
                WaveformView(samples: recording.waveform, duration: recording.duration, position: currentPosition, overview: true)
                    .frame(height: 48).clipShape(RoundedRectangle(cornerRadius: 4))
                HStack {
                    Text("0:00"); Spacer(); Text(timeLabel(recording.duration))
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 7)
                Text(timeLabel(currentPosition.wrappedValue, precise: true))
                    .font(.system(size: 33, weight: .semibold, design: .rounded)).monospacedDigit().padding(.top, 15)
                TransportControls(recording: recording, position: currentPosition)
                    .padding(.top, 24).padding(.bottom, 25)
            }.padding(.horizontal, 22).padding(.top, 35)
        }
        .background(MemoStyle.background)
        .toolbar {
            ToolbarItemGroup {
                ShareLink(item: library.url(for: recording)) { Image(systemName: "square.and.arrow.up") }.help("Share")
                Button { library.toggleFavorite(recording) } label: { Image(systemName: recording.isFavorite ? "heart.fill" : "heart") }.help("Favorite")
                Button(action: onDelete) { Image(systemName: "trash") }.help("Delete")
            }
            ToolbarItemGroup {
                Button { options = true } label: { Image(systemName: "slider.horizontal.3") }.help("Options")
                Button { transcript = true } label: { Image(systemName: "text.bubble") }.help("Transcription")
                Button(action: onEdit) { Image(systemName: "waveform") }.help("Edit Recording")
            }
        }
        .sheet(isPresented: $options) { PlaybackOptionsView(recording: recording) }
        .sheet(isPresented: $transcript) { TranscriptView(recording: recording) }
        .onAppear { title = recording.title }
        .onChange(of: recording.id) { _, _ in position = 0; title = recording.title }
        .onChange(of: recording.title) { _, value in title = value }
        .onChange(of: titleFocused) { _, focused in
            if !focused, title != recording.title { library.rename(recording, to: title) }
        }
    }
}

struct TransportControls: View {
    let recording: Recording
    @Binding var position: Double
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var audio: AudioController

    private var isPlaying: Bool { audio.activeRecordingID == recording.id && audio.isPlaying }

    var body: some View {
        HStack(spacing: 30) {
            Button { seek(-15) } label: { Image(systemName: "gobackward.15").font(.system(size: 23)) }
                .accessibilityLabel("Rewind, 15 seconds").help("Rewind 15 seconds")
            Button {
                if isPlaying { audio.pausePlayback() }
                else {
                    let target = position
                    audio.play(recording, url: library.url(for: recording))
                    if target < recording.duration { audio.seek(to: target) }
                }
            } label: {
                if audio.activeRecordingID == recording.id && audio.isPreparingPlayback {
                    ProgressView().frame(width: 35, height: 38)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 31)).frame(width: 35, height: 38)
                }
            }.accessibilityLabel(isPlaying ? "Pause" : "Play").help(isPlaying ? "Pause" : "Play")
            Button { seek(15) } label: { Image(systemName: "goforward.15").font(.system(size: 23)) }
                .accessibilityLabel("Fast Forward, 15 seconds").help("Fast forward 15 seconds")
        }
        .buttonStyle(.plain).foregroundStyle(.primary)
    }

    private func seek(_ amount: Double) {
        position = min(recording.duration, max(0, position + amount))
        if audio.activeRecordingID == recording.id { audio.seek(to: position) }
    }
}

struct CompactPlaybackView: View {
    let recording: Recording
    var onEdit: () -> Void
    var onDelete: () -> Void
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var audio: AudioController
    @State private var position = 0.0
    @State private var options = false
    @State private var transcript = false
    private var binding: Binding<Double> {
        Binding(get: { audio.activeRecordingID == recording.id ? audio.currentTime : position },
                set: { position = $0; if audio.activeRecordingID == recording.id { audio.seek(to: $0) } })
    }
    var body: some View {
        VStack(spacing: 15) {
            WaveformView(samples: recording.waveform, duration: recording.duration, position: binding, overview: true).frame(height: 48)
            HStack {
                Text(timeLabel(binding.wrappedValue)); Spacer(); Text(timeLabel(recording.duration))
            }.font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { options = true } label: { Image(systemName: "slider.horizontal.3") }
                Spacer()
                TransportControls(recording: recording, position: binding)
                Spacer()
                Button(action: onDelete) { Image(systemName: "trash") }
            }
            HStack {
                Button("Edit Recording", action: onEdit)
                Spacer()
                Button { transcript = true } label: { Image(systemName: "text.bubble") }
                ShareLink(item: library.url(for: recording)) { Image(systemName: "square.and.arrow.up") }
            }.font(.subheadline)
        }
        .sheet(isPresented: $options) { PlaybackOptionsView(recording: recording) }
        .sheet(isPresented: $transcript) { TranscriptView(recording: recording) }
    }
}

struct PlaybackOptionsView: View {
    let recording: Recording
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var audio: AudioController
    @Environment(\.dismiss) private var dismiss
    private var current: Recording { library.recordings.first { $0.id == recording.id } ?? recording }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Options").font(.headline)
                HStack {
                    Button("Reset") {
                        update { $0.playbackRate = 1; $0.skipSilence = false; $0.enhanceRecording = false }
                        if audio.activeRecordingID == recording.id {
                            audio.setRate(1); audio.setSkipSilence(false); audio.setEnhanceRecording(false)
                        }
                    }.buttonStyle(.bordered)
                        .disabled(current.playbackRate == 1 && !current.skipSilence && !current.enhanceRecording)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "checkmark").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 36, height: 36).background(.blue, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Done")
                }
            }.padding(20)
            VStack(alignment: .leading, spacing: 12) {
                Text("Playback Speed").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 20)
                VStack(spacing: 0) {
                    Slider(value: Binding(get: { Double(current.playbackRate) }, set: { value in
                        update { $0.playbackRate = Float(value) }
                        if audio.activeRecordingID == recording.id { audio.setRate(Float(value)) }
                    }), in: 0.5...2, step: 0.25)
                        .accessibilityLabel("Playback Speed")
                        .accessibilityValue(String(format: "%.2g times", current.playbackRate))
                        .padding(.vertical, 16)
                    Divider()
                    Toggle("Skip Silence", isOn: Binding(get: { current.skipSilence }, set: { value in
                        update { $0.skipSilence = value }
                        if audio.activeRecordingID == recording.id { audio.setSkipSilence(value) }
                    })).padding(.vertical, 14)
                }.padding(.horizontal, 20).background(MemoStyle.waveform, in: RoundedRectangle(cornerRadius: 14))
                VStack {
                    Toggle("Enhance Recording", isOn: Binding(get: { current.enhanceRecording }, set: { value in
                        update { $0.enhanceRecording = value }
                        if audio.activeRecordingID == recording.id { audio.setEnhanceRecording(value) }
                    })).padding(.horizontal, 20).padding(.vertical, 16)
                }.background(MemoStyle.waveform, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 4)
            }.padding(.horizontal, 20).toggleStyle(.switch)
            Spacer(minLength: 20)
        }
        .background(MemoStyle.background)
        .desktopSheetSize(width: 580, height: 540)
        .presentationDetents([.medium])
    }

    private func update(_ mutation: (inout Recording) -> Void) {
        var value = current; mutation(&value); library.update(value)
    }
}

struct TranscriptView: View {
    let recording: Recording
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var transcription = TranscriptionService()
    @State private var message: String?
    private var saved: String? { library.recordings.first { $0.id == recording.id }?.transcript }

    var body: some View {
        NavigationStack {
            Group {
                if let text = saved, !text.isEmpty {
                    ScrollView { Text(text).font(.title3).lineSpacing(7).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(24) }
                } else if transcription.isTranscribing {
                    VStack(spacing: 20) {
                        ProgressView("Transcribing…")
                        if !transcription.text.isEmpty { ScrollView { Text(transcription.text).padding(24).textSelection(.enabled) } }
                    }.padding()
                } else {
                    ContentUnavailableView {
                        Label("Transcription", systemImage: "text.bubble")
                    } description: {
                        Text(message ?? "Create a transcript using on-device speech recognition.")
                    } actions: {
                        Button("Transcribe Recording") {
                            Task {
                                if let text = await transcription.transcribe(url: library.url(for: recording)) {
                                    guard var latest = library.recordings.first(where: { $0.id == recording.id }) else { return }
                                    latest.transcript = text; library.update(latest)
                                } else { message = transcription.errorMessage }
                            }
                        }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Transcription")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if let saved {
                    ToolbarItem { ShareLink(item: saved) { Image(systemName: "square.and.arrow.up") } }
                }
            }
        }
        .desktopSheetSize(width: 400, height: 400)
        .onDisappear { transcription.cancel() }
    }
}
