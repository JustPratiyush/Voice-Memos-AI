import SwiftUI
import VoiceMemosCore

struct RecordingView: View {
    var folderID: UUID? = nil
    var onSave: (UUID) -> Void
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var audio: AudioController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("locationNaming") private var locationNaming = false
    @AppStorage("audioQuality") private var quality = "Compressed"
    @StateObject private var location = LocationNamingService()
    @State private var title = "New Recording"
    @State private var started = false
    @State private var saving = false
    @State private var captured: CapturedRecording?
    @State private var error: String?
    @State private var discard = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("New Recording", text: $title)
                    .font(.title2.bold()).multilineTextAlignment(.center).textFieldStyle(.plain)
                    .padding(.top, 25)
                Text(Date(), format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 6).padding(.bottom, 28)
                WaveformView(samples: audio.levels, duration: max(audio.duration, 0.1),
                             position: .constant(audio.currentTime), live: true)
                    .frame(minHeight: 180)
                Text(timeLabel(captured?.duration ?? audio.currentTime, precise: true))
                    .font(.system(size: 42, weight: .light, design: .rounded)).monospacedDigit()
                    .padding(.top, 28)
                Text(audio.isPaused ? "Paused" : audio.isRecording ? "Recording" : captured == nil ? "Ready to Record" : "Ready to Save")
                    .font(.subheadline).foregroundStyle(audio.isRecording && !audio.isPaused ? MemoStyle.red : .secondary)
                    .padding(.top, 7)
                HStack {
                    Button("Cancel") { if audio.isRecording || captured != nil { discard = true } else { dismiss() } }
                        .disabled(saving)
                    Spacer()
                    Button {
                        if audio.isRecording {
                            audio.isPaused ? audio.resumeRecording() : audio.pauseRecording()
                        } else { Task { await audio.startRecording(lossless: quality == "Lossless") } }
                    } label: {
                        Image(systemName: audio.isRecording && !audio.isPaused ? "pause.fill" : "record.circle")
                            .font(.system(size: 30)).foregroundStyle(MemoStyle.red)
                            .frame(width: 66, height: 66).background(MemoStyle.red.opacity(0.1), in: Circle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(audio.isPaused ? "Resume" : audio.isRecording ? "Pause" : "Record")
                        .disabled(saving || captured != nil)
                    Spacer()
                    Button("Done") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled((!audio.isRecording && captured == nil) || saving)
                }.padding(28)
                if saving { ProgressView("Saving…").padding(.bottom, 15) }
            }
            .navigationTitle("New Recording")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .desktopSheetSize(width: 420, height: 520)
        .interactiveDismissDisabled(audio.isRecording || captured != nil || saving)
        .task {
            guard !started else { return }; started = true
            await audio.startRecording(lossless: quality == "Lossless")
            if let message = audio.errorMessage { error = message }
            if locationNaming, let name = await location.recordingName(), title == "New Recording" { title = name }
        }
        .confirmationDialog("Discard this recording?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard Recording", role: .destructive) {
                audio.cancelRecording()
                if let captured { try? FileManager.default.removeItem(at: captured.url) }
                dismiss()
            }
        }
        .alert("Recording", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onDisappear { location.cancel(); audio.cancelRecording() }
        .onReceive(audio.$errorMessage) { if let message = $0 { error = message } }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        if captured == nil { captured = await audio.finishRecording() }
        guard let captured else { error = audio.errorMessage; return }
        do {
            let item = try await library.addRecording(url: captured.url, title: title, waveform: captured.waveform, folderID: folderID)
            try? FileManager.default.removeItem(at: captured.url)
            onSave(item.id)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
