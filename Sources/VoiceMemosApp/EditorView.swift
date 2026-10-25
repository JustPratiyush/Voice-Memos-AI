import SwiftUI
import VoiceMemosCore

struct EditorView: View {
    let recording: Recording
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var audio: AudioController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("audioQuality") private var quality = "Compressed"
    @State private var history: [EditedAudio] = []
    @State private var redoHistory: [EditedAudio] = []
    @State private var trimming = false
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var position = 0.0
    @State private var replaceAt = 0.0
    @State private var busy = false
    @State private var error: String?
    @State private var saveOptions = false
    @State private var discard = false
    @State private var pendingReplacement: CapturedRecording?

    private var working: Recording {
        var item = recording
        if let edit = history.last { item.duration = edit.duration; item.waveform = edit.waveform }
        return item
    }
    private var url: URL { history.last?.url ?? library.url(for: recording) }
    private var binding: Binding<Double> {
        Binding(get: { audio.activeRecordingID == recording.id ? audio.currentTime : position },
                set: { position = $0; if audio.activeRecordingID == recording.id { audio.seek(to: $0) } })
    }
    private var selectedRange: ClosedRange<Double>? { trimming ? start...max(start, end) : nil }
    private var canEdit: Bool { end - start >= 0.02 && !busy && !audio.isRecording }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(recording.title).font(.title3.bold())
                    Text("\(dateLabel(recording.createdAt))  \(timeLabel(working.duration))")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 24)
                if audio.isRecording {
                    WaveformView(samples: audio.levels, duration: max(0.1, audio.duration),
                                 position: .constant(audio.currentTime), live: true).frame(minHeight: 180)
                } else {
                    WaveformView(samples: working.waveform, duration: working.duration,
                                 position: binding, selection: selectedRange).frame(minHeight: 180)
                }
                VStack(spacing: 10) {
                    overview
                    HStack {
                        Text(timeLabel(trimming ? start : 0))
                        Spacer()
                        Text(timeLabel(trimming ? end : working.duration))
                    }.font(.caption).foregroundStyle(.secondary)
                    if trimming {
                        HStack(spacing: 20) {
                            VStack(alignment: .leading) {
                                Text("Start").font(.caption)
                                Slider(value: $start, in: 0...max(0.01, end - 0.01)).accessibilityLabel("Trim Beginning")
                            }
                            VStack(alignment: .leading) {
                                Text("End").font(.caption)
                                Slider(value: $end, in: min(working.duration, start + 0.01)...max(working.duration, start + 0.01)).accessibilityLabel("Trim End")
                            }
                        }.tint(.yellow)
                    }
                    Text(timeLabel(audio.isRecording ? replaceAt + audio.currentTime : binding.wrappedValue, precise: true))
                        .font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit().padding(.vertical, 8)
                    HStack(spacing: 28) {
                        Button { binding.wrappedValue = max(0, binding.wrappedValue - 15) } label: { Image(systemName: "gobackward.15") }
                        Button(action: togglePlayback) { Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 30)) }
                            .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
                        Button { binding.wrappedValue = min(working.duration, binding.wrappedValue + 15) } label: { Image(systemName: "goforward.15") }
                    }.font(.system(size: 24)).buttonStyle(.plain).disabled(audio.isRecording || busy)
                    editorActions.padding(.top, 15)
                    if busy { ProgressView("Processing Audio…") }
                }.padding(24)
            }
            .navigationTitle(trimming ? "Trim" : "Edit Recording")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if !history.isEmpty || audio.isRecording || pendingReplacement != nil { discard = true } else { close() } }
                        .disabled(busy)
                }
                ToolbarItemGroup {
                    Button {
                        audio.stopPlayback()
                        if let last = history.popLast() { redoHistory.append(last) }
                        position = 0; start = 0; end = working.duration
                    } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .disabled(history.isEmpty || busy || audio.isRecording)
                        .keyboardShortcut("z")
                    Button {
                        audio.stopPlayback()
                        if let edit = redoHistory.popLast() { history.append(edit) }
                        position = 0; start = 0; end = working.duration
                    } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                        .disabled(redoHistory.isEmpty || busy || audio.isRecording)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                    Button { trimming.toggle(); start = 0; end = working.duration } label: { Label("Trim", systemImage: "crop") }
                        .disabled(busy || audio.isRecording)
                        .keyboardShortcut("t")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if audio.isRecording || pendingReplacement != nil { Task { await finishReplacement() } }
                        else if history.isEmpty { close() } else { saveOptions = true }
                    }.disabled(busy).fontWeight(.semibold).keyboardShortcut("s")
                }
            }
        }
        .desktopSheetSize(width: 520, height: 600)
        .interactiveDismissDisabled(!history.isEmpty || audio.isRecording || busy || pendingReplacement != nil)
        .onAppear { audio.stopPlayback(); end = recording.duration }
        .onDisappear { audio.cancelRecording(); audio.stopPlayback(); cleanup() }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlayback)) { _ in
            guard !audio.isRecording, !busy else { return }
            togglePlayback()
        }
        .onReceive(audio.$currentTime) { time in
            if trimming, audio.activeRecordingID == recording.id, audio.isPlaying, time >= end {
                audio.pausePlayback(); audio.seek(to: end)
            }
        }
        .onReceive(audio.$errorMessage) { if let message = $0 { error = message } }
        .confirmationDialog("Save Recording", isPresented: $saveOptions, titleVisibility: .visible) {
            Button("Save Recording") { Task { await save(asNew: false) } }
            Button("Save as New Recording") { Task { await save(asNew: true) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Discard changes?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { audio.cancelRecording(); close() }
        }
        .alert("Unable to Edit Recording", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var overview: some View {
        WaveformView(samples: working.waveform, duration: working.duration, position: binding, overview: true, selection: selectedRange)
            .frame(height: 48)
            .overlay {
                if trimming {
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let left = CGFloat(start / max(0.01, working.duration)) * width
                        let right = CGFloat(end / max(0.01, working.duration)) * width
                        Rectangle().strokeBorder(.yellow, lineWidth: 2).frame(width: max(1, right - left)).offset(x: left)
                        trimHandle("chevron.left").position(x: left, y: 24)
                            .gesture(DragGesture(coordinateSpace: .named("trim")).onChanged {
                                start = max(0, min(end - 0.02, $0.location.x / width * working.duration))
                            })
                        trimHandle("chevron.right").position(x: right, y: 24)
                            .gesture(DragGesture(coordinateSpace: .named("trim")).onChanged {
                                end = min(working.duration, max(start + 0.02, $0.location.x / width * working.duration))
                            })
                    }.coordinateSpace(name: "trim")
                }
            }.clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func trimHandle(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 12, weight: .black)).foregroundStyle(.black)
            .frame(width: 18, height: 48).background(.yellow)
    }

    @ViewBuilder private var editorActions: some View {
        if trimming {
            HStack {
                Button("Trim") { Task { await apply(remove: false) } }
                    .disabled(!canEdit || (start < 0.01 && end >= working.duration - 0.01))
                Button("Delete") { Task { await apply(remove: true) } }
                    .disabled(!canEdit || end - start >= working.duration - 0.01)
                Spacer()
                Button("Cancel Trim") { trimming = false }
            }.buttonStyle(.bordered)
        } else {
            HStack {
                Button {
                    Task {
                        if audio.isRecording || pendingReplacement != nil { await finishReplacement() }
                        else {
                            replaceAt = binding.wrappedValue
                            audio.stopPlayback()
                            await audio.startRecording(lossless: quality == "Lossless")
                            if !audio.isRecording { error = audio.errorMessage }
                        }
                    }
                } label: {
                    Text(audio.isRecording ? "PAUSE" : pendingReplacement != nil ? "RETRY REPLACE" : position >= working.duration - 0.01 ? "RESUME" : "REPLACE")
                        .fontWeight(.semibold).padding(.horizontal, 15).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(MemoStyle.red, in: Capsule())
                .disabled(busy)
                Spacer()
                if recording.originalFilename != nil && history.isEmpty {
                    Button("Revert to Original") { library.restoreOriginal(recording); close() }
                        .disabled(audio.isRecording)
                }
            }
        }
    }

    private func togglePlayback() {
        if audio.isPlaying { audio.pausePlayback() }
        else {
            let target = trimming
                ? ((binding.wrappedValue >= start && binding.wrappedValue < end) ? binding.wrappedValue : start)
                : binding.wrappedValue
            audio.play(working, url: url)
            audio.seek(to: target >= working.duration ? 0 : target)
        }
    }

    private func apply(remove: Bool) async {
        busy = true; audio.stopPlayback()
        defer { busy = false }
        do {
            let edit = try await (remove ? EditingService.remove(url: url, range: start..<end) : EditingService.trim(url: url, range: start..<end))
            clearRedo(); history.append(edit); position = 0; trimming = false; start = 0; end = edit.duration
        } catch { self.error = error.localizedDescription }
    }

    private func finishReplacement() async {
        busy = true
        defer { busy = false }
        if pendingReplacement == nil { pendingReplacement = await audio.finishRecording() }
        guard let capture = pendingReplacement else { error = audio.errorMessage; return }
        do {
            let replacedEnd = min(working.duration, replaceAt + capture.duration)
            let edit = try await EditingService.replace(url: url, range: replaceAt..<replacedEnd, with: capture.url)
            clearRedo(); history.append(edit); position = min(edit.duration, replaceAt + capture.duration)
            try? FileManager.default.removeItem(at: capture.url); pendingReplacement = nil
            start = 0; end = edit.duration
        } catch { self.error = error.localizedDescription }
    }

    private func save(asNew: Bool) async {
        guard let edit = history.last else { close(); return }
        busy = true; audio.stopPlayback()
        defer { busy = false }
        do {
            if asNew {
                _ = try await library.addRecording(url: edit.url, title: recording.title + " Copy", waveform: edit.waveform, folderID: recording.folderID)
            } else { try library.commitEdit(edit, for: recording) }
            close()
        } catch { self.error = error.localizedDescription }
    }

    private func cleanup() {
        for edit in history + redoHistory { try? FileManager.default.removeItem(at: edit.url) }
        if let capture = pendingReplacement { try? FileManager.default.removeItem(at: capture.url) }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func clearRedo() {
        for edit in redoHistory { try? FileManager.default.removeItem(at: edit.url) }
        redoHistory = []
    }
}
