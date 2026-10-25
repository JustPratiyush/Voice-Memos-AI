import SwiftUI
import VoiceMemosCore

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("audioQuality") private var quality = "Compressed"
    @AppStorage("locationNaming") private var locationNaming = false
    @AppStorage("clearDeletedDays") private var clearDeleted = 30
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Form {
            Section {
                Picker("Clear Deleted", selection: $clearDeleted) {
                    Text("Immediately").tag(-1)
                    Text("After 1 Day").tag(1)
                    Text("After 7 Days").tag(7)
                    Text("After 30 Days").tag(30)
                    Text("Never").tag(0)
                }
                Picker("Audio Quality", selection: $quality) {
                    Text("Compressed").tag("Compressed")
                    Text("Lossless").tag("Lossless")
                }
                Toggle("Location-based Naming", isOn: $locationNaming)
            } footer: {
                Text("Location-based naming uses your location to name new recordings. Permission is requested when you record.")
            }
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
            Section {
                LabeledContent("Recordings", value: "\(library.recordings(in: .all).count)")
                LabeledContent("Storage", value: "On this device")
            }
            #if os(iOS)
            Button("Done") { dismiss() }
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle("Voice Memos Settings")
        #if os(macOS)
        .frame(width: 430, height: 350)
        #endif
    }
}
