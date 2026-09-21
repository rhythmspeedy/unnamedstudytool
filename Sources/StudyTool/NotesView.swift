import SwiftUI
import UniformTypeIdentifiers

struct NotesView: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var router: StudyRouter
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var editors: NoteEditorCache
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    @FocusState private var focus: Field?
    private enum Field { case search, title }
    @State private var exporting = false
    @State private var document = NoteTextDocument(text: "")
    @State private var exportName = "Note"
    @State private var exportError: String?
    @State private var confirmRecovery = false

    var body: some View {
        let matches = store.matchingNotes
        HSplitView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Notes").font(.system(size: 25, weight: .medium, design: .serif))
                    Spacer()
                    Text("\(store.notes.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search notes", text: $store.search).textFieldStyle(.plain).focused($focus, equals: .search)
                        .accessibilityLabel("Search notes")
                    if !store.search.isEmpty {
                        Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear note search")
                    }
                }.padding(10).background(theme.background, in: RoundedRectangle(cornerRadius: 8))
                Button { newNote() } label: { Label("New note", systemImage: "plus").frame(maxWidth: .infinity) }
                    .controlSize(.large).keyboardShortcut("n").disabled(!store.loaded)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(matches) { note in
                            Button { if store.select(note.id) { focus = nil } } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(note.displayTitle).font(.body.weight(.semibold)).lineLimit(2)
                                    Text(note.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    Text(note.modified, style: .date).font(.caption2).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
                                    .background(store.selectedID == note.id ? theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(store.selectedID == note.id ? theme.accent.opacity(0.3) : .clear))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityAddTraits(store.selectedID == note.id ? .isSelected : [])
                        }
                        if matches.isEmpty && !store.search.isEmpty {
                            Text("No matching notes.\nTry a different word.").font(.callout).foregroundStyle(.secondary).padding(.top, 20)
                        }
                    }.padding(1)
                }
                if store.deleted != nil {
                    HStack {
                        Text("Note deleted").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Undo delete") { store.undoDelete() }
                    }
                }
            }.padding(20).frame(minWidth: 230, idealWidth: 260, maxWidth: 300).background(theme.surface)
                .frame(width: router.focused ? 0 : nil).clipped().accessibilityHidden(router.focused)

            Group {
                if let note = store.selected {
                    VStack(spacing: 12) {
                        HStack {
                            Text(store.status).font(.caption).foregroundStyle(store.saveFailed ? theme.accent : theme.ink.opacity(0.6)).accessibilityLabel("Note status: \(store.status)")
                            if store.saveFailed { Button("Retry save") { store.flush() } }
                            Spacer()
                            Menu {
                                ItemActions(reference: .init(kind: .note, id: note.id))
                                Button("Create flashcard from selection…") {
                                    guard let text = editors.views[note.id]?.documentView as? NSTextView, text.selectedRange().length > 0 else {
                                        store.error = "Select some text in the note first."; return
                                    }
                                    hub.captureCard(from: (text.string as NSString).substring(with: text.selectedRange()))
                                }
                                Divider()
                                Button("Export as text…") { export(note) }
                                Divider()
                                Button("Delete note", role: .destructive) { store.deleteSelected() }
                            } label: { Image(systemName: "ellipsis").padding(6) }.menuStyle(.borderlessButton).frame(width: 30).help("Note options").accessibilityLabel("Note options")
                        }.padding(.horizontal, 22)
                        TextField("Untitled note", text: Binding(get: { store.selected?.title ?? "" }, set: { store.edit(id: note.id, title: $0) }))
                            .font(.system(size: 30, weight: .medium, design: .serif)).textFieldStyle(.plain)
                            .focused($focus, equals: .title).accessibilityLabel("Note title").padding(.horizontal, 22)
                        Divider().padding(.horizontal, 22)
                        NoteEditor(note: note, store: store, cache: editors, theme: theme, createCard: { hub.captureCard(from: $0) }).id(note.id)
                    }.padding(.top, 22).padding(.horizontal, 12).frame(maxWidth: 820, maxHeight: .infinity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !store.loaded {
                    ContentUnavailableView {
                        Label("Notes couldn’t be opened", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Your saved file has been preserved.")
                    } actions: {
                        if store.canRecover { Button("Restore previous save…") { confirmRecovery = true } }
                    }
                } else {
                    ContentUnavailableView("A place for your thoughts", systemImage: "note.text", description: Text("Create a note to start writing. Your work saves automatically."))
                }
            }.background(theme.background)
        }
        .background {
            Button("Search notes") { focus = .search }.keyboardShortcut("f").hidden().accessibilityHidden(true)
        }
        .onDisappear { store.flush() }
        .onChange(of: store.selectedID, initial: true) { _, id in if let id { workspace.opened(.init(kind: .note, id: id)) } }
        .fileExporter(isPresented: $exporting, document: document, contentType: .plainText, defaultFilename: exportName) { result in
            if case .failure(let error) = result { exportError = "Export failed: \(error.localizedDescription)" }
        }
        .alert("Notes needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            if store.loaded { Button("Retry saving") { store.flush() } }
            if let note = store.selected { Button("Export text copy…") { export(note); store.error = nil } }
            Button("Keep editing", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
        .alert("Restore the previous save?", isPresented: $confirmRecovery) {
            Button("Restore") { editors.views.removeAll(); store.restorePreviousSave() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Notes will return to their previous saved state. The current file will also be kept as a separate recovery archive.") }
    }

    private func newNote() { if store.create() != nil { focus = .title } }
    private func export(_ note: StudyNote) {
        document = NoteTextDocument(text: note.exportText)
        exportName = String(note.displayTitle.prefix(80)).components(separatedBy: CharacterSet(charactersIn: "/:\n\r")).joined(separator: "-")
        exporting = true
    }
}

struct NoteTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let value = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        text = value
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
