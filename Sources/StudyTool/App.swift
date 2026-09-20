import SwiftUI
import UniformTypeIdentifiers

@main
struct StudyToolApp: App {
    @NSApplicationDelegateAdaptor(StudyAppDelegate.self) private var appDelegate
    @StateObject private var library = Library()
    @StateObject private var todos = TodoStore()
    @StateObject private var pomodoro = PomodoroStore()
    @StateObject private var notes = NotesStore()
    @StateObject private var noteEditors = NoteEditorCache()
    var body: some Scene {
        Window("unnamedstudytool", id: "main") {
            WorkspaceView().environmentObject(library).environmentObject(todos).environmentObject(pomodoro)
                .environmentObject(notes).environmentObject(noteEditors)
                .modifier(AppAppearance())
                .frame(minWidth: 820, minHeight: 580)
                .onAppear { appDelegate.notes = notes }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in notes.flush() }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in notes.flush() }
        }
        .defaultSize(width: 1100, height: 760)
        .commands { CommandGroup(replacing: .newItem) {} }

        Settings {
            StudySettingsView()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var library: Library
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    @State private var selection: UUID?
    @State private var search = ""
    @State private var deckEditor = false
    @State private var deckName = ""
    @State private var renaming = false
    @State private var cardEditor = false
    @State private var editingCard: UUID?
    @State private var front = ""
    @State private var back = ""
    @State private var deleteDeck = false
    @State private var deletingCard: Card?
    @State private var session: StudySession?
    @AppStorage("shuffle") private var shuffled = true
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument = LibraryDocument()
    @State private var sidebarVisible = true
    @FocusState private var focusedField: EditorField?
    private enum EditorField: Hashable { case deckName, front, back }

    private var deck: Deck? { library.decks.first { $0.id == selection } }
    private var visibleCards: [Card] {
        (deck?.cards ?? []).filter { search.isEmpty || $0.front.localizedCaseInsensitiveContains(search) || $0.back.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Group {
            if let session {
                StudyView(initial: session) { self.session = nil }
            } else {
                libraryView
            }
        }
    }

    private var libraryView: some View {
        HSplitView {
            if sidebarVisible {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("unnamed").font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("STUDY TOOL").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    sidebarButton(help: "Hide deck sidebar")
                }.padding(.horizontal, 20).padding(.top, 24)
                HStack {
                    Text("YOUR DECKS").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(library.decks.count)").foregroundStyle(.secondary).font(.caption.monospacedDigit())
                }.padding(.horizontal, 20)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(library.decks) { item in
                            Button { selection = item.id } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "rectangle.stack")
                                        .foregroundStyle(selection == item.id ? theme.accent : theme.ink.opacity(0.55))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.name).font(.body.weight(selection == item.id ? .semibold : .regular)).lineLimit(2)
                                        Text("\(item.cards.count) cards").font(.caption).foregroundStyle(theme.ink.opacity(0.6))
                                    }
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(theme.ink)
                                .padding(.horizontal, 14).padding(.vertical, 13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selection == item.id ? theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selection == item.id ? theme.accent.opacity(0.3) : .clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 2)
                }.frame(maxHeight: .infinity)
                VStack(spacing: 14) {
                    Button { newDeck() } label: { Label("New deck", systemImage: "plus").frame(maxWidth: .infinity) }
                        .controlSize(.large).keyboardShortcut("n")
                    Menu {
                        Button("Import library…") { importing = true }
                        Button("Export library…") { exportDocument = LibraryDocument(decks: library.decks); exporting = true }
                    } label: { Label("Library backup", systemImage: "externaldrive") }
                    Text("Saved on this Mac · Offline").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }.padding(20)
            }
            .background(theme.surface)
            .frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
            }
            ZStack {
                LinearGradient(colors: [theme.background, theme.surface.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                if let deck {
                    deckView(deck)
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        if !sidebarVisible { sidebarButton(help: "Show deck sidebar") }
                        Image(systemName: "rectangle.on.rectangle").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.secondary)
                        Text("A little practice.\nA lot remembered.").font(.system(size: 44, weight: .medium, design: .serif))
                        Text("Make a deck, add what you’re learning, and find your rhythm.")
                            .foregroundStyle(.secondary).frame(maxWidth: 380, alignment: .leading)
                        Button("Create your first deck", action: newDeck).buttonStyle(PrimaryButtonStyle()).controlSize(.large)
                    }.padding(50).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .tint(theme.accent)
        .onChange(of: selection) { _, _ in search = "" }
        .onAppear { if selection == nil { selection = library.decks.first?.id } }
        .sheet(isPresented: $deckEditor) {
            VStack(alignment: .leading, spacing: 20) {
                Text(renaming ? "Rename deck" : "A new place to learn.").font(.title2.weight(.semibold))
                TextField("Deck name", text: $deckName).textFieldStyle(.roundedBorder).focused($focusedField, equals: .deckName).onSubmit(saveDeck)
                HStack { Button("Cancel") { deckEditor = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Save", action: saveDeck).keyboardShortcut(.defaultAction).disabled(deckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(28).frame(width: 400).onAppear { focusedField = .deckName }
        }
        .sheet(isPresented: $cardEditor) {
            VStack(alignment: .leading, spacing: 16) {
                Text(editingCard == nil ? "Add a card" : "Edit card").font(.title2.weight(.semibold))
                Text("PROMPT").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $front).font(.body).focused($focusedField, equals: .front).accessibilityLabel("Prompt").frame(height: 100).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                Text("ANSWER").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $back).font(.body).focused($focusedField, equals: .back).accessibilityLabel("Answer").frame(height: 130).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("Cancel") { cardEditor = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if editingCard == nil { Button("Save & add another") { saveCard(another: true) }.disabled(!validCard) }
                    Button("Save card") { saveCard(another: false) }.keyboardShortcut(.defaultAction).disabled(!validCard)
                }
            }.padding(28).frame(width: 520).onAppear { focusedField = .front }
        }
        .alert("Delete this deck?", isPresented: $deleteDeck) {
            Button("Delete deck", role: .destructive) {
                if library.save(library.decks.filter { $0.id != selection }) { selection = library.decks.first?.id }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All cards in this deck will be deleted. This cannot be undone.") }
        .alert("Delete this card?", isPresented: Binding(get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } })) {
            Button("Delete card", role: .destructive) {
                if var deck, let card = deletingCard { deck.cards.removeAll { $0.id == card.id }; update(deck) }
                deletingCard = nil
            }
            Button("Cancel", role: .cancel) { deletingCard = nil }
        }
        .alert("Something needs attention", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "unnamedstudytool-backup") { result in
            if case .failure(let error) = result { library.error = "Export failed: \(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let imported = try JSONDecoder().decode([Deck].self, from: Data(contentsOf: url))
                let copies = imported.map { item in Deck(name: item.name, cards: item.cards.map { Card(front: $0.front, back: $0.back) }) }
                if copies.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.cards.contains { $0.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }) {
                    library.error = "Import failed: every deck needs a name and every card needs a prompt and answer."
                } else if library.save(library.decks + copies) { selection = copies.first?.id ?? selection }
            } catch { library.error = "Import failed: \(error.localizedDescription)" }
        }
    }

    private func deckView(_ deck: Deck) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top) {
                if !sidebarVisible { sidebarButton(help: "Show deck sidebar").padding(.trailing, 4) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("MAKE IT STICK").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(.secondary)
                    Text(deck.name).font(.system(size: 36, weight: .medium, design: .serif)).lineLimit(2)
                    Text("\(deck.cards.count) cards · Your next small step starts here.").foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Rename deck") { renaming = true; deckName = deck.name; deckEditor = true }
                    Button("Delete deck", role: .destructive) { deleteDeck = true }
                } label: { Image(systemName: "ellipsis").padding(8) }.menuStyle(.borderlessButton).frame(width: 34)
            }
            HStack {
                Button { session = StudySession(cards: deck.cards, shuffled: shuffled) } label: { Label("Start studying", systemImage: "play.fill").padding(.horizontal, 12).padding(.vertical, 4) }
                    .buttonStyle(PrimaryButtonStyle()).controlSize(.large).disabled(deck.cards.isEmpty).keyboardShortcut("r")
                Toggle("Shuffle", isOn: $shuffled).toggleStyle(.checkbox).padding(.leading, 10)
                Spacer()
                Button { editingCard = nil; front = ""; back = ""; cardEditor = true } label: { Label("Add card", systemImage: "plus") }.controlSize(.large).keyboardShortcut("n", modifiers: [.command, .shift])
            }
            Divider()
            HStack {
                Text("CARDS").font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                Spacer()
                TextField("Search cards", text: $search).textFieldStyle(.roundedBorder).frame(width: 230)
            }
            if deck.cards.isEmpty {
                ContentUnavailableView("Start with one card", systemImage: "plus.rectangle.on.rectangle", description: Text("Add a question, a definition, or anything you want to remember."))
            } else if visibleCards.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleCards) { card in
                            HStack(alignment: .top, spacing: 18) {
                                VStack(alignment: .leading, spacing: 9) {
                                    Text(card.front).font(.body.weight(.medium)).textSelection(.enabled)
                                    Text(card.back).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Button { editingCard = card.id; front = card.front; back = card.back; cardEditor = true } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).help("Edit card")
                                Button { deletingCard = card } label: { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("Delete card")
                            }
                            .padding(20)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.ink.opacity(0.10)))
                        }
                    }.padding(1)
                }
            }
            Spacer(minLength: 0)
        }.padding(36)
    }

    private func sidebarButton(help: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() } } label: {
            Image(systemName: "sidebar.left").padding(6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }

    private var validCard: Bool { !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func newDeck() { renaming = false; deckName = ""; deckEditor = true }
    private func saveDeck() {
        let name = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if renaming, var deck { deck.name = name; if update(deck) { deckEditor = false } }
        else { let item = Deck(name: name); if library.save(library.decks + [item]) { selection = item.id; deckEditor = false } }
    }
    @discardableResult private func update(_ deck: Deck) -> Bool { library.save(library.decks.map { $0.id == deck.id ? deck : $0 }) }
    private func saveCard(another: Bool) {
        guard validCard, var deck else { return }
        let card = Card(id: editingCard ?? UUID(), front: front.trimmingCharacters(in: .whitespacesAndNewlines), back: back.trimmingCharacters(in: .whitespacesAndNewlines))
        if let index = deck.cards.firstIndex(where: { $0.id == card.id }) { deck.cards[index] = card } else { deck.cards.append(card) }
        if update(deck) { if another { front = ""; back = ""; focusedField = .front } else { cardEditor = false } }
    }
}

struct LibraryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var decks: [Deck] = []
    init(decks: [Deck] = []) { self.decks = decks }
    init(configuration: ReadConfiguration) throws { decks = try JSONDecoder().decode([Deck].self, from: configuration.file.regularFileContents ?? Data()) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: try JSONEncoder().encode(decks)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .foregroundStyle(enabled ? theme.buttonInk : theme.ink.opacity(0.45))
            .background(enabled ? theme.accent.opacity(configuration.isPressed ? 0.80 : 1) : theme.ink.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}
