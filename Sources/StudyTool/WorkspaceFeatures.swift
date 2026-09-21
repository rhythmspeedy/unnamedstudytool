import SwiftUI
import Charts
import UniformTypeIdentifiers

struct ItemActions: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var workspace: WorkspaceStore
    let reference: StudyItemReference
    var body: some View {
        Button(workspace.state.pins.contains(where: { $0.reference == reference }) ? "Unpin from Home" : "Pin to Home") { workspace.pin(reference) }
        Button("Focus on this") { hub.run(.focus(reference)) }
    }
}

struct TodayView: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var todos: TodoStore
    @EnvironmentObject private var notes: NotesStore
    @EnvironmentObject private var library: Library
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    @State private var history = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.date.formatted(.dateTime.weekday(.wide).month().day()).uppercased()).font(.system(size: 11, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                        Text("A little progress, today.").font(.system(size: 34, design: .serif))
                    }
                    Spacer()
                    Button { hub.run(.capture(.task)) } label: { Label("Capture", systemImage: "plus") }.help("Quick capture (⌘⇧Space)")
                    Button("History") { history = true }
                }
                if let recent = workspace.state.recent.first, let item = hub.resolve(recent.reference) {
                    Button { hub.run(.open(item.reference)) } label: {
                        HStack { Image(systemName: item.icon); Text("Continue \(item.title)").lineLimit(1); Spacer(); Image(systemName: "arrow.up.right") }.padding(16)
                    }.buttonStyle(.plain).background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                if workspace.state.target.enabled {
                    let target = workspace.state.target
                    let value = workspace.total(target.metric, on: context.date)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(target.metric.rawValue); Spacer(); Text("\(value) / \(target.amount)").monospacedDigit() }.font(.caption)
                        ProgressView(value: Double(min(value, target.amount)), total: Double(target.amount)).tint(theme.accent)
                    }
                }
                if !hub.dueCards.isEmpty {
                    Button("\(hub.dueCards.count) cards ready to review") { hub.startReview() }
                    Text("An optional refresher. You can still study any deck at any time.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = hub.automaticBackupError {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Retry automatic backup") { hub.automaticBackup() }
                }
                if !workspace.state.pins.isEmpty {
                    Text("PINNED").font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 10) {
                        ForEach(workspace.state.pins) { pin in
                            if let item = hub.resolve(pin.reference) {
                                Button { hub.run(.open(item.reference)) } label: {
                                    Label(item.title, systemImage: item.icon).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                }.buttonStyle(.plain).background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .contextMenu { ItemActions(reference: item.reference) }
                            }
                        }
                    }
                }
                let today = CalendarDay(context.date)
                let tasks = todos.lists.flatMap { list in list.items.filter { !$0.done && (($0.scheduledDay.map { $0 <= today } ?? false) || ($0.dueDay.map { $0 <= today } ?? false)) }.map { (list.id, $0) } }
                if !tasks.isEmpty {
                    Text("TODAY").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(tasks.enumerated()), id: \.element.1.id) { _, entry in
                        HStack {
                            let reference = StudyItemReference(kind: .todoItem, id: entry.1.id, parentID: entry.0)
                            Button { hub.toggleTask(reference) } label: { Image(systemName: "circle").font(.title3) }.buttonStyle(.plain).accessibilityLabel("Complete \(entry.1.title)")
                            Button { hub.run(.open(reference)) } label: { Text(entry.1.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                        }.padding(12).background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                HStack {
                    Text("\(workspace.total(.focusMinutes, on: context.date)) min focused")
                    Text("· \(workspace.total(.cardsReviewed, on: context.date)) cards reviewed")
                    Spacer()
                }.font(.caption).foregroundStyle(.secondary)
                Divider()
            }
        }
        .sheet(isPresented: $history) { StudyHistoryView() }
    }
}

struct StudyHistoryView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var clear = false
    private var days: [Date] { (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: Date())) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("Your week").font(.largeTitle); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            HStack(spacing: 24) {
                ForEach(TargetMetric.allCases) { metric in
                    VStack(alignment: .leading) {
                        Text("\(days.reduce(0) { $0 + workspace.total(metric, on: $1) })").font(.title.monospacedDigit())
                        Text(metric.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading) {
                    Text("\(workspace.state.events.filter { $0.kind == .taskCompleted && $0.occurredAt >= (days.first ?? .now) }.count)").font(.title.monospacedDigit())
                    Text("Tasks completed").font(.caption).foregroundStyle(.secondary)
                }
            }
            Chart(days, id: \.self) { day in
                BarMark(x: .value("Day", day, unit: .day), y: .value("Focus minutes", workspace.total(.focusMinutes, on: day)))
            }.frame(height: 170).accessibilityLabel("Focus minutes during the last seven days")
            Text("Focus minutes by day. History stays on this Mac for two years and is included in workspace backups.").font(.caption).foregroundStyle(.secondary)
            if workspace.state.events.isEmpty { Text("Your next study session starts your history.").foregroundStyle(.secondary) }
            Button("Clear study history…", role: .destructive) { clear = true }
        }.padding(30).frame(width: 620).modifier(AppAppearance())
        .alert("Clear study history?", isPresented: $clear) {
            Button("Clear", role: .destructive) { workspace.change { $0.events = [] } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes local history and daily target progress. Decks, notes, tasks, and deck progress remain saved.") }
    }
}

struct QuickCaptureView: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var todos: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State var kind: CaptureKind
    @State private var title = ""
    @State var bodyText = ""
    @State private var destination: UUID?
    @State private var today = false
    @State private var newDeck = ""
    @State private var error: String?
    @State private var capturedNoteID: UUID?
    @FocusState private var titleFocused: Bool
    private var valid: Bool { kind == .note ? !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !bodyText.isEmpty : !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (kind != .card || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Capture a thought").font(.title2)
            Picker("Type", selection: $kind) { ForEach(CaptureKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            TextField(kind == .card ? "Prompt" : kind == .task ? "What needs doing?" : "Title (optional)", text: $title).textFieldStyle(.roundedBorder).focused($titleFocused)
            if kind != .task {
                Text(kind == .card ? "Answer" : "Note").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $bodyText).font(.body).frame(height: 180).accessibilityLabel(kind == .card ? "Answer" : "Note body")
            }
            if kind == .task {
                Picker("List", selection: $destination) { ForEach(todos.lists) { Text($0.name).tag(Optional($0.id)) } }
                Toggle("Add to Today", isOn: $today)
            }
            if kind == .card {
                Picker("Deck", selection: $destination) {
                    Text("Create a new deck…").tag(Optional<UUID>.none)
                    ForEach(library.decks) { Text($0.name).tag(Optional($0.id)) }
                }
                if destination == nil { TextField("New deck name", text: $newDeck).textFieldStyle(.roundedBorder) }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Text("⌘Return to save").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.return, modifiers: .command).disabled(!valid || (kind == .card && destination == nil && newDeck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }.padding(28).frame(width: 490).modifier(AppAppearance())
        .onAppear { chooseDefault(); titleFocused = true }
        .onChange(of: kind) { _, _ in chooseDefault(); hub.defaults.set(kind.rawValue, forKey: "lastCaptureKind") }
    }
    private func chooseDefault() {
        destination = kind == .card ? (hub.router.deckID ?? library.decks.first?.id) : (hub.router.listID ?? todos.lists.first?.id)
    }
    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .task:
            guard var list = todos.lists.first(where: { $0.id == destination }) else { error = "Choose an available list."; return }
            list.items.append(TodoItem(title: trimmed, scheduledDay: today ? CalendarDay() : nil))
            guard todos.update(list) else { error = todos.error; return }
        case .note:
            let noteID = capturedNoteID ?? hub.notes.create()
            guard let id = noteID else { error = hub.notes.error; return }
            capturedNoteID = id
            hub.notes.edit(id: id, title: trimmed.isEmpty ? String(bodyText.split(separator: "\n").first?.prefix(70) ?? "Untitled note") : trimmed, body: bodyText)
            guard hub.notes.flush() else { error = hub.notes.error; return }
        case .card:
            var deck = library.decks.first { $0.id == destination }
            if deck == nil && destination != nil { error = "That deck was deleted. Choose another destination."; return }
            if deck == nil { deck = Deck(name: newDeck.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard var deck else { error = "Choose or create a deck."; return }
            deck.cards.append(Card(front: trimmed, back: bodyText.trimmingCharacters(in: .whitespacesAndNewlines)))
            var updated = library.decks
            if let index = updated.firstIndex(where: { $0.id == deck.id }) { updated[index] = deck } else { updated.append(deck) }
            guard library.save(updated) else { error = library.error; return }
        }
        hub.defaults.set(kind.rawValue, forKey: "lastCaptureKind")
        hub.notice = "\(kind.rawValue) saved"; dismiss()
    }
}

struct CommandPaletteView: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var notes: NotesStore
    @EnvironmentObject private var todos: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: String?
    @FocusState private var searching: Bool
    struct Entry: Identifiable { let id: String; let title: String; let subtitle: String; let icon: String; let command: StudyCommand }
    private var entries: [Entry] {
        var values = StudyPage.allCases.map { Entry(id: $0.rawValue, title: "Open \($0.rawValue)", subtitle: "Tool", icon: $0.icon, command: .page($0)) }
        values += CaptureKind.allCases.map { Entry(id: "new\($0.rawValue)", title: "New \($0.rawValue.lowercased())", subtitle: "Capture", icon: "plus", command: .capture($0)) }
        values += [Entry(id: "deck", title: "New deck", subtitle: "Flashcards", icon: "plus.rectangle", command: .newDeck), Entry(id: "timer", title: "Start / pause timer", subtitle: "Pomodoro", icon: "timer", command: .toggleTimer), Entry(id: "settings", title: "Settings and backups", subtitle: "Preferences", icon: "gearshape", command: .settings)]
        values += hub.destinations.map { Entry(id: $0.id, title: $0.title, subtitle: $0.subtitle, icon: $0.icon, command: .open($0.reference)) }
        let tokens = query.lowercased().split(separator: " ")
        return Array(values.filter { entry in tokens.allSatisfy { (entry.title + " " + entry.subtitle).localizedCaseInsensitiveContains($0) } }.sorted {
            let a = $0.title.lowercased() == query.lowercased(), b = $1.title.lowercased() == query.lowercased()
            return a == b ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : a
        }.prefix(50))
    }
    var body: some View {
        VStack(spacing: 12) {
            TextField("Find a tool, note, deck, or task…", text: $query).textFieldStyle(.roundedBorder).focused($searching)
                .onSubmit { activate() }
                .onMoveCommand { direction in
                    let values = entries; guard !values.isEmpty else { return }
                    let index = values.firstIndex { $0.id == selection } ?? 0
                    if direction == .down { selection = values[min(index + 1, values.count - 1)].id }
                    if direction == .up { selection = values[max(index - 1, 0)].id }
                }
            List(entries, selection: $selection) { entry in
                HStack {
                    Image(systemName: entry.icon).frame(width: 22)
                    Text(entry.title).lineLimit(1); Spacer(); Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                }.tag(entry.id).contentShape(Rectangle()).onTapGesture { selection = entry.id; activate() }
            }.frame(height: 320)
            if entries.isEmpty { Text("No matches. Try a shorter search.").foregroundStyle(.secondary) }
            HStack { Text("↑ ↓ to choose · Return to open").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(22).frame(width: 560).modifier(AppAppearance())
        .onAppear { searching = true; selection = entries.first?.id }
        .onChange(of: query) { _, _ in selection = entries.first?.id }
    }
    private func activate() {
        guard let entry = entries.first(where: { $0.id == selection }) ?? entries.first else { return }
        dismiss()
        // Allow the palette sheet to dismiss before presenting a capture sheet.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            hub.run(entry.command)
        }
    }
}

struct TargetSettingsView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    var body: some View {
        Toggle("Daily study target", isOn: Binding(get: { workspace.state.target.enabled }, set: { value in workspace.change { $0.target.enabled = value } }))
        if workspace.state.target.enabled {
            Picker("Measure", selection: Binding(get: { workspace.state.target.metric }, set: { value in workspace.change { $0.target.metric = value } })) {
                ForEach(TargetMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            Stepper("Target: \(workspace.state.target.amount)", value: Binding(get: { workspace.state.target.amount }, set: { value in workspace.change { $0.target.amount = value } }), in: 1...10000)
        }
    }
}

struct DataSettingsView: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var exporting = false
    @State private var importing = false
    @State private var importingArchive = false
    @State private var document = WorkspaceBackupDocument()
    @State private var pending: BackupCandidate?
    @State private var error: String?
    @State private var message: String?
    var body: some View {
        Section("Workspace backup") {
            Text("Export decks, notes, tasks, progress, pins, history, and preferences in one file. Everything stays local until you choose where to save it.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Export workspace…") {
                    do { document = WorkspaceBackupDocument(data: try hub.backup().encoded()); exporting = true }
                    catch { self.error = error.localizedDescription }
                }
                Button("Import workspace…") { importingArchive = false; importing = true }
            }
            Button("Restore a pre-import recovery archive…") { importingArchive = true; importing = true }
            if let date = workspace.lastSaved { Text("Workspace saved \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
            Text("Imports keep a recovery archive. Previous-save copies are also stored beside the app’s data.").font(.caption).foregroundStyle(.secondary)
            Button("Show local data and recovery files") { NSWorkspace.shared.open(hub.directory) }
            if let message { Text(message).font(.callout) }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "unnamedstudytool-workspace") { result in
            if case .failure(let error) = result { self.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                if importingArchive { pending = BackupCandidate(backup: try WorkspaceBackup.decodeRecoveryArchive(data), allowMerge: false) }
                else { pending = BackupCandidate(backup: try WorkspaceBackup.decode(data)) }
            } catch { self.error = "Import failed. \(error.localizedDescription)" }
        }
        .sheet(item: $pending) { candidate in
            BackupPreviewView(backup: candidate.backup, allowMerge: candidate.allowMerge) { install(merge: $0) }
        }
        .alert("Backup needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func install(merge: Bool) {
        guard let pending else { error = "Select a backup file first."; return }
        do { try hub.restore(pending.backup, merge: merge); self.pending = nil; message = "Imported successfully. Your previous data was archived." }
        catch { self.pending = nil; self.error = error.localizedDescription }
    }
}
struct WorkspaceBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
