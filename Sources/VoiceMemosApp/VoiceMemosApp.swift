import SwiftUI
import VoiceMemosCore

@main
struct VoiceMemosApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var audio = AudioController()
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("clearDeletedDays") private var clearDeletedDays = 30
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
        let directory = isDemo
            ? FileManager.default.temporaryDirectory.appendingPathComponent("VoiceMemosReplica-Demo", isDirectory: true)
            : nil
        _library = StateObject(wrappedValue: LibraryStore(directory: directory))
    }

    var body: some Scene {
        WindowGroup("Voice Memos") {
            LibraryView()
                .environmentObject(library)
                .environmentObject(audio)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .task {
                    applyRetention()
                    if ProcessInfo.processInfo.arguments.contains("--demo") {
                        await DemoLibrary.populate(library)
                    }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active { applyRetention() } }
                .onChange(of: clearDeletedDays) { _, _ in applyRetention() }
                .onReceive(library.$recordings) { items in
                    if clearDeletedDays == -1, items.contains(where: { $0.deletedAt != nil }) {
                        Task { @MainActor in applyRetention() }
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 720)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") { NotificationCenter.default.post(name: .newRecording, object: nil) }
                    .keyboardShortcut("n")
                Button("New Folder…") { NotificationCenter.default.post(name: .newFolder, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Import Audio…") { NotificationCenter.default.post(name: .importAudio, object: nil) }
                    .keyboardShortcut("o")
            }
            CommandMenu("Controls") {
                Button(audio.isPlaying ? "Pause" : "Play") {
                    NotificationCenter.default.post(name: .togglePlayback, object: nil)
                }.keyboardShortcut(.space, modifiers: [])
                Button("Skip Backward") { audio.skip(seconds: -15) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Skip Forward") { audio.skip(seconds: 15) }.keyboardShortcut(.rightArrow, modifiers: .command)
                Divider()
                Button("Edit Recording") { NotificationCenter.default.post(name: .editRecording, object: nil) }
                    .keyboardShortcut("e")
                Button("Duplicate") { NotificationCenter.default.post(name: .duplicateRecording, object: nil) }
                    .keyboardShortcut("d")
                Button("Delete Recording") { NotificationCenter.default.post(name: .deleteRecording, object: nil) }
                    .keyboardShortcut(.delete, modifiers: [])
            }
            SidebarCommands()
        }
        #endif
        #if os(macOS)
        Settings { SettingsView().environmentObject(library) }
        #endif
    }

    private func applyRetention() {
        library.purgeExpiredDeleted(retentionDays: clearDeletedDays == 0 ? nil : max(0, clearDeletedDays))
    }
}

extension Notification.Name {
    static let newRecording = Notification.Name("VoiceMemos.NewRecording")
    static let newFolder = Notification.Name("VoiceMemos.NewFolder")
    static let importAudio = Notification.Name("VoiceMemos.Import")
    static let togglePlayback = Notification.Name("VoiceMemos.TogglePlayback")
    static let editRecording = Notification.Name("VoiceMemos.Edit")
    static let duplicateRecording = Notification.Name("VoiceMemos.Duplicate")
    static let deleteRecording = Notification.Name("VoiceMemos.Delete")
}

enum MemoStyle {
    #if os(macOS)
    static let background = Color(nsColor: .windowBackgroundColor)
    #else
    static let background = Color(uiColor: .systemBackground)
    #endif
    static let waveform = Color.primary.opacity(0.065)
    static let red = Color(red: 1, green: 0.23, blue: 0.27)
}

func timeLabel(_ seconds: TimeInterval, precise: Bool = false) -> String {
    let value = max(0, seconds.isFinite ? seconds : 0)
    let total = Int(value)
    if precise {
        return String(format: "%02d:%02d.%02d", total / 60, total % 60, Int(value * 100) % 100)
    }
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
    return String(format: "%d:%02d", total / 60, total % 60)
}

func dateLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
        return date.formatted(.dateTime.weekday(.wide))
    }
    return date.formatted(date: .abbreviated, time: .omitted)
}

extension View {
    @ViewBuilder func desktopSheetSize(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        self.frame(minWidth: width, minHeight: height)
        #else
        self
        #endif
    }
}
