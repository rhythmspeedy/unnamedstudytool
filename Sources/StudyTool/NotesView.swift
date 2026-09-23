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
    private enum Field: Hashable { case search, noteTitle, pageTitle(UUID) }
    @State private var exporting = false
    @State private var document = NoteTextDocument(text: "")
    @State private var exportName = "Note"
    @State private var exportError: String?
    @State private var confirmRecovery = false
    @State private var pendingPageID: UUID?
    @State private var pageToDelete: StudyNotePage?

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
                    VStack(spacing: 14) {
                        HStack {
                            Text(store.status).font(.caption).foregroundStyle(store.saveFailed ? theme.accent : theme.ink.opacity(0.6)).accessibilityLabel("Note status: \(store.status)")
                            if store.saveFailed { Button("Retry save") { store.flush() } }
                            Spacer()
                            Button { addPage(to: note.id) } label: { Label("New page", systemImage: "plus") }
                                .buttonStyle(.bordered).keyboardShortcut("n", modifiers: [.command, .shift])
                                .help("Add a page to this note (Shift-Command-N)")
                            Menu {
                                ItemActions(reference: .init(kind: .note, id: note.id))
                                Button("Create flashcard from selection…") {
                                    guard let text = selectedText(in: note) else {
                                        store.error = "Select some text in the note first."; return
                                    }
                                    hub.captureCard(from: text)
                                }
                                Divider()
                                Button("Export as text…") { export(note) }
                                Divider()
                                Button("Delete note", role: .destructive) { store.deleteSelected() }
                            } label: { Image(systemName: "ellipsis").padding(6) }.menuStyle(.borderlessButton).frame(width: 30).help("Note options").accessibilityLabel("Note options")
                        }.padding(.horizontal, 22)
                        GeometryReader { geometry in
                            ScrollViewReader { reader in
                                ScrollView {
                                    VStack(spacing: 16) {
                                        notePage(
                                            number: 1,
                                            noteID: note.id,
                                            pageID: nil,
                                            title: note.title,
                                            body: note.body,
                                            editorHeight: max(380, geometry.size.height - 112)
                                        )
                                        ForEach(Array(note.pages.enumerated()), id: \.element.id) { index, page in
                                            notePage(
                                                number: index + 2,
                                                noteID: note.id,
                                                pageID: page.id,
                                                title: page.title,
                                                body: page.body,
                                                editorHeight: max(380, geometry.size.height - 112),
                                                canDelete: true
                                            )
                                            .id(page.id)
                                        }
                                    }
                                    .padding(.horizontal, 4).padding(.bottom, 12)
                                }
                                .onChange(of: pendingPageID) { _, pageID in
                                    guard let pageID else { return }
                                    withAnimation(.easeOut(duration: 0.22)) { reader.scrollTo(pageID, anchor: .top) }
                                    DispatchQueue.main.async {
                                        focus = .pageTitle(pageID)
                                        pendingPageID = nil
                                    }
                                }
                            }
                        }
                    }.padding(.top, 16).padding(.horizontal, 8).frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .alert("Delete this page?", isPresented: Binding(get: { pageToDelete != nil }, set: { if !$0 { pageToDelete = nil } })) {
            Button("Delete page", role: .destructive) {
                guard let noteID = store.selectedID, let page = pageToDelete else { return }
                if store.deletePage(noteID: noteID, pageID: page.id) { editors.views.removeValue(forKey: page.id) }
                pageToDelete = nil
            }
            Button("Cancel", role: .cancel) { pageToDelete = nil }
        } message: { Text("The page and its writing will be removed from this note.") }
    }

    @ViewBuilder
    private func notePage(number: Int, noteID: UUID, pageID: UUID?, title: String, body: String, editorHeight: CGFloat, canDelete: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("PAGE \(number)").font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(theme.ink.opacity(0.48))
                Spacer()
                if canDelete, let pageID, let page = store.selected?.pages.first(where: { $0.id == pageID }) {
                    Menu {
                        Button("Delete page…", role: .destructive) { pageToDelete = page }
                    } label: { Image(systemName: "ellipsis").frame(width: 24, height: 20) }
                    .menuStyle(.borderlessButton).frame(width: 26).help("Page options").accessibilityLabel("Page \(number) options")
                }
            }
            TextField(number == 1 ? "Untitled note" : "Untitled page", text: Binding(
                get: {
                    if let pageID { return store.selected?.pages.first(where: { $0.id == pageID })?.title ?? "" }
                    return store.selected?.title ?? ""
                },
                set: { value in
                    if let pageID { store.editPage(noteID: noteID, pageID: pageID, title: value) }
                    else { store.edit(id: noteID, title: value) }
                }
            ))
            .font(.system(size: number == 1 ? 30 : 25, weight: .medium, design: .serif)).textFieldStyle(.plain)
            .focused($focus, equals: pageID.map(Field.pageTitle) ?? .noteTitle)
            .accessibilityLabel(number == 1 ? "Note title" : "Page \(number) title")
            Divider()
            NoteEditor(noteID: noteID, pageID: pageID, body: body, store: store, cache: editors, theme: theme, createCard: { hub.captureCard(from: $0) })
                .id(pageID ?? noteID).frame(maxWidth: .infinity).frame(height: editorHeight)
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.ink.opacity(0.07), lineWidth: 0.75))
    }

    private func newNote() { if store.create() != nil { focus = .noteTitle } }
    private func addPage(to noteID: UUID) {
        if let pageID = store.addPage(to: noteID) { pendingPageID = pageID }
    }
    private func selectedText(in note: StudyNote) -> String? {
        for id in note.editorIDs {
            guard let text = editors.views[id]?.documentView as? NSTextView else { continue }
            let range = text.selectedRange()
            guard range.length > 0, NSMaxRange(range) <= (text.string as NSString).length else { continue }
            return (text.string as NSString).substring(with: range)
        }
        return nil
    }
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
