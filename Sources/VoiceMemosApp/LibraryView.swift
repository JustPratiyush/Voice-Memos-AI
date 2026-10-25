import SwiftUI
import UniformTypeIdentifiers
import VoiceMemosCore

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var audio: AudioController
    @State private var filter: LibraryFilter = .all
    @State private var selectedID: UUID?
    @State private var query = ""
    @State private var importing = false
    @State private var newFolder = false
    @State private var folderName = ""
    @State private var renamingFolder: RecordingFolder?
    @State private var renaming: Recording?
    @State private var newTitle = ""
    @State private var moving: [Recording] = []
    @State private var showingMove = false
    @State private var permanentDelete: [Recording] = []
    @State private var confirmDelete = false
    @State private var showingRecorder = false
    @State private var editing: Recording?
    @State private var showingSettings = false
    @State private var selectedItems: Set<UUID> = []
    @State private var selecting = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var error: String?
    @State private var isImporting = false
    @State private var showingFolders = false
    @State private var folderToDelete: RecordingFolder?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let titleFont = Font.body.weight(.semibold)
    private let subtitleFont = Font.subheadline
    #else
    private let titleFont = Font.system(size: 14, weight: .semibold)
    private let subtitleFont = Font.system(size: 12)
    #endif

    private var recordings: [Recording] { library.recordings(in: filter, query: query) }
    private var selected: Recording? { library.recordings.first { $0.id == selectedID } }
    private var title: String {
        switch filter {
        case .all: return "All Recordings"
        case .favorites: return "Favorites"
        case .recentlyDeleted: return "Recently Deleted"
        case .folder(let id): return library.folders.first { $0.id == id }?.title ?? "Folder"
        }
    }
    private var isTrash: Bool { filter == .recentlyDeleted }
    private var recordingFolderID: UUID? {
        if case .folder(let id) = filter { return id }
        return nil
    }

    var body: some View {
        platformBody
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): importFiles(urls)
                case .failure(let error): self.error = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingRecorder) {
                RecordingView(folderID: recordingFolderID) { id in
                    if recordingFolderID == nil { filter = .all }
                    selectedID = id
                }
                    .environmentObject(library).environmentObject(audio)
            }
            #if os(iOS)
            .sheet(item: $editing) { recording in
                EditorView(recording: recording)
                    .environmentObject(library).environmentObject(audio)
            }
            #endif
            .sheet(isPresented: $showingMove) { moveSheet }
            .sheet(isPresented: $showingFolders) {
                NavigationStack {
                    folders.navigationTitle("Voice Memos")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFolders = false } }
                            ToolbarItem(placement: .cancellationAction) { Button("New Folder") { showingFolders = false; folderName = ""; newFolder = true } }
                        }
                }.presentationDetents([.large])
            }
            .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(library) }
            .alert(renamingFolder == nil ? "New Folder" : "Rename Folder", isPresented: $newFolder) {
                TextField("Name", text: $folderName)
                Button("Cancel", role: .cancel) { renamingFolder = nil }
                Button("Save") {
                    if let folder = renamingFolder { library.renameFolder(folder, to: folderName) }
                    else { library.createFolder(title: folderName) }
                    renamingFolder = nil
                }.disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert("Rename Recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newTitle)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    if let item = renaming { library.rename(item, to: newTitle) }
                    renaming = nil
                }.disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .confirmationDialog("Delete permanently?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Forever", role: .destructive) {
                    for item in permanentDelete { library.permanentlyDelete(item) }
                    permanentDelete = []
                    selectedID = nil
                }
                Button("Cancel", role: .cancel) { permanentDelete = [] }
            } message: { Text("These recordings will be permanently deleted. This action cannot be undone.") }
            .confirmationDialog("Delete Folder?", isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }), titleVisibility: .visible) {
                Button("Delete Folder", role: .destructive) {
                    if let folder = folderToDelete {
                        library.deleteFolder(folder, trashRecordings: true); filter = .all
                    }
                    folderToDelete = nil
                }
            } message: { Text("The folder’s recordings will move to Recently Deleted.") }
            .alert("Unable to Complete Action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .onReceive(library.$errorMessage) { if let message = $0 { error = message; library.errorMessage = nil } }
            .onReceive(audio.$errorMessage) {
                if !showingRecorder, editing == nil, let message = $0 { error = message; audio.errorMessage = nil }
            }
            .onReceive(NotificationCenter.default.publisher(for: .newRecording)) { _ in beginRecording() }
            .onReceive(NotificationCenter.default.publisher(for: .newFolder)) { _ in folderName = ""; newFolder = true }
            .onReceive(NotificationCenter.default.publisher(for: .importAudio)) { _ in importing = true }
            .onReceive(NotificationCenter.default.publisher(for: .togglePlayback)) { _ in
                if editing == nil, !showingRecorder, let selected { play(selected) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .editRecording)) { _ in
                if editing == nil, !showingRecorder, let selected, selected.deletedAt == nil { editing = selected }
            }
            .onReceive(NotificationCenter.default.publisher(for: .duplicateRecording)) { _ in
                if editing == nil, !showingRecorder, let selected, selected.deletedAt == nil,
                   let copy = library.duplicate(selected) { selectedID = copy.id }
            }
            .onReceive(NotificationCenter.default.publisher(for: .deleteRecording)) { _ in
                if editing == nil, !showingRecorder, let selected, selected.deletedAt == nil { delete(selected) }
            }
            .onChange(of: filter) { _, _ in
                if let selectedID, !recordings.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
                selecting = false; selectedItems = []; showingFolders = false
            }
            .onChange(of: recordings.map(\.id)) { _, ids in
                if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
                selectedItems.formIntersection(ids)
            }
            .onOpenURL { url in if url.isFileURL { importFiles([url]) } }
    }

    @ViewBuilder private var platformBody: some View {
        #if os(macOS)
        if let editing {
            EditorView(recording: editing, onClose: { self.editing = nil })
                .frame(minWidth: 976, minHeight: 600)
        } else {
            splitLibrary.frame(minWidth: 976, minHeight: 500)
        }
        #else
        if sizeClass == .regular {
            splitLibrary
        } else {
            phoneLibrary
        }
        #endif
    }

    private var splitLibrary: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            folders
                .navigationSplitViewColumnWidth(min: 165, ideal: 210, max: 280)
                .toolbar {
                    ToolbarItem {
                        Button { folderName = ""; newFolder = true } label: { Image(systemName: "folder.badge.plus") }
                            .help("New Folder")
                    }
                }
        } content: {
            recordingList
                .navigationSplitViewColumnWidth(min: 240, ideal: 310, max: 420)
        } detail: {
            if let selected, selected.deletedAt == nil {
                PlaybackView(recording: selected, onEdit: { editing = selected }, onDelete: { delete(selected) })
            } else if let selected {
                deletedDetail(selected)
            } else {
                Text("No Recording Selected").font(.system(size: 25, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(title)
        .searchable(text: $query, placement: .toolbar, prompt: "Titles, Transcripts")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button(selecting ? "Done Selecting" : "Select Recordings") { selecting.toggle(); selectedItems = [] }
                    Button("Import Audio…") { importing = true }
                    #if os(iOS)
                    Button("Settings") { showingSettings = true }
                    #endif
                } label: { Image(systemName: "ellipsis.circle") }
                .help("Library Actions")
            }
        }
    }

    #if os(iOS)
    private var phoneLibrary: some View {
        NavigationStack {
            recordingList
                .navigationTitle(title)
                .searchable(text: $query, prompt: "Titles, Transcripts")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingFolders = true } label: { Label("Folders", systemImage: "chevron.left") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(selecting ? "Done" : "Select Recordings") { selecting.toggle(); selectedItems = [] }
                            Button("Import Audio", systemImage: "square.and.arrow.down") { importing = true }
                            Button("Settings", systemImage: "gear") { showingSettings = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
        }
    }
    #endif

    private var folders: some View {
        List(selection: $filter) {
            folderRow("All Recordings", icon: "waveform", filter: .all)
            if !library.recordings(in: .favorites, query: "").isEmpty { folderRow("Favorites", icon: "heart", filter: .favorites) }
            if !library.recordings(in: .recentlyDeleted, query: "").isEmpty { folderRow("Recently Deleted", icon: "trash", filter: .recentlyDeleted) }
            if !library.folders.isEmpty {
                Section("My Folders") {
                    ForEach(library.folders) { folder in
                        folderRow(folder.title, icon: "folder", filter: .folder(folder.id))
                            .contextMenu {
                                Button("Rename Folder") { showingFolders = false; renamingFolder = folder; folderName = folder.title; newFolder = true }
                                Button("Delete Folder", role: .destructive) { showingFolders = false; folderToDelete = folder }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func folderRow(_ title: String, icon: String, filter value: LibraryFilter) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 20)
            Text(title)
            Spacer(minLength: 2)
            Text("\(library.recordings(in: value, query: "").count)").foregroundStyle(.secondary).monospacedDigit()
        }.padding(.vertical, 5).tag(value)
    }

    private var recordingList: some View {
        VStack(spacing: 0) {
            if recordings.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? (isTrash ? "No Deleted Recordings" : "No Recordings") : "No Results",
                          systemImage: query.isEmpty ? "waveform" : "magnifyingglass")
                } description: {
                    Text(query.isEmpty ? (isTrash ? "Deleted recordings appear here." : "Tap the record button to start a new recording.") : "Try a different title or transcript.")
                }.frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(recordings) { item in
                            recordingRow(item)
                        }
                    }.padding(.horizontal, 10).padding(.top, 2)
                }
            }
            if isImporting { ProgressView("Importing Audio…").padding() }
            if selecting {
                HStack {
                    Button("Select All") { selectedItems = Set(recordings.map(\.id)) }
                    Spacer()
                    if isTrash {
                        Button("Recover") { for item in chosen { library.recover(item) }; selectedItems = [] }
                    } else {
                        Button("Move") { moving = chosen; showingMove = true }
                    }
                    Button(role: .destructive) {
                        if isTrash { permanentDelete = chosen; confirmDelete = true }
                        else { for item in chosen { library.trash(item) }; selectedItems = [] }
                    } label: { Image(systemName: "trash") }
                    .disabled(selectedItems.isEmpty)
                }.padding()
            } else if isTrash {
                HStack {
                    Button("Recover All") { for item in recordings { library.recover(item) } }
                    Spacer()
                    Button("Delete All", role: .destructive) { permanentDelete = recordings; confirmDelete = true }
                }.padding().disabled(recordings.isEmpty)
            } else {
                RecordButton(action: beginRecording).padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
        .background(MemoStyle.background)
    }

    private var chosen: [Recording] { recordings.filter { selectedItems.contains($0.id) } }

    private func recordingRow(_ item: Recording) -> some View {
        let active = selectedID == item.id
        return VStack(spacing: 0) {
            Button {
                if selecting {
                    if selectedItems.contains(item.id) { selectedItems.remove(item.id) } else { selectedItems.insert(item.id) }
                } else {
                    if selectedID != item.id { audio.stopPlayback() }
                    selectedID = item.id
                }
            } label: {
                HStack(spacing: 10) {
                    if selecting { Image(systemName: selectedItems.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.blue) }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.title).font(titleFont).lineLimit(1)
                            if item.isFavorite { Image(systemName: "heart.fill").font(.system(size: 10)) }
                        }
                        HStack(spacing: 6) {
                            Text(dateLabel(item.createdAt))
                            if item.transcript != nil { Image(systemName: "text.bubble").font(.system(size: 11)) }
                            Spacer()
                            Text(timeLabel(item.duration)).monospacedDigit()
                        }.font(subtitleFont).opacity(0.65)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 11).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .foregroundStyle(active && !selecting ? Color.white : Color.primary)
            .background(active && !selecting ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 9))
            #endif
            .contextMenu { recordingMenu(item) }
            #if os(iOS)
            if active && !selecting && sizeClass != .regular {
                if isTrash { deletedDetail(item).frame(height: 100) }
                else {
                    CompactPlaybackView(recording: item, onEdit: { editing = item }, onDelete: { delete(item) })
                        .padding(.horizontal, 10).padding(.bottom, 16)
                }
            }
            #endif
            Divider().padding(.horizontal, 10).opacity(active ? 0 : 1)
        }
    }

    @ViewBuilder private func recordingMenu(_ item: Recording) -> some View {
        if item.deletedAt != nil {
            Button("Recover") { library.recover(item) }
            Button("Delete Forever", role: .destructive) { permanentDelete = [item]; confirmDelete = true }
        } else {
            Button("Edit Recording", systemImage: "waveform") { editing = item }
            Button("Rename", systemImage: "pencil") { renaming = item; newTitle = item.title }
            Button(item.isFavorite ? "Remove from Favorites" : "Favorite", systemImage: item.isFavorite ? "heart.slash" : "heart") { library.toggleFavorite(item) }
            Button("Duplicate", systemImage: "plus.square.on.square") { library.duplicate(item) }
            Button("Move to Folder", systemImage: "folder") { moving = [item]; showingMove = true }
            ShareLink(item: library.url(for: item)) { Label("Share", systemImage: "square.and.arrow.up") }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
        }
    }

    private func deletedDetail(_ item: Recording) -> some View {
        VStack(spacing: 16) {
            Text(item.title).font(.title3.bold())
            Text("This recording has been deleted.").foregroundStyle(.secondary)
            HStack {
                Button("Recover") { library.recover(item) }.buttonStyle(.borderedProminent)
                Button("Delete Forever", role: .destructive) { permanentDelete = [item]; confirmDelete = true }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var moveSheet: some View {
        NavigationStack {
            List {
                Button { for item in moving { library.move(item, to: nil) }; showingMove = false } label: { Label("All Recordings", systemImage: "waveform") }
                ForEach(library.folders) { folder in
                    Button { for item in moving { library.move(item, to: folder.id) }; showingMove = false } label: { Label(folder.title, systemImage: "folder") }
                }
            }.navigationTitle("Move to Folder")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingMove = false } } }
        }
        .frame(minWidth: 300, minHeight: 300)
    }

    private func beginRecording() {
        guard !audio.isRecording, editing == nil else { return }
        audio.stopPlayback()
        showingRecorder = true
    }

    private func delete(_ item: Recording) {
        if audio.activeRecordingID == item.id { audio.stopPlayback() }
        library.trash(item)
        if selectedID == item.id { selectedID = nil }
    }

    private func play(_ item: Recording) {
        if audio.activeRecordingID == item.id && audio.isPlaying { audio.pausePlayback() }
        else { audio.play(item, url: library.url(for: item)) }
    }

    private func importFiles(_ urls: [URL]) {
        guard !isImporting else { return }
        Task {
            isImporting = true
            defer { isImporting = false }
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let item = try await library.addRecording(url: url, title: url.deletingPathExtension().lastPathComponent, waveform: [])
                    filter = .all; selectedID = item.id
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}
