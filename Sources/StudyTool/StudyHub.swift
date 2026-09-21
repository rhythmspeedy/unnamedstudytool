import SwiftUI
import Combine

enum CaptureKind: String, CaseIterable, Identifiable { case task = "Task", note = "Note", card = "Flashcard"; var id: String { rawValue } }
struct CaptureRequest: Identifiable { let id = UUID(); var kind: CaptureKind; var answer = "" }
enum StudyCommand {
    case open(StudyItemReference), page(StudyPage), capture(CaptureKind), focus(StudyItemReference?), toggleTimer, focusMode, newDeck, settings
}
struct StudyDestination: Identifiable {
    let reference: StudyItemReference
    let title: String
    let subtitle: String
    var id: String { reference.key }
    var icon: String {
        switch reference.kind { case .deck: "rectangle.stack"; case .note: "note.text"; case .todoList: "checklist"; case .todoItem: "circle" }
    }
}
@MainActor final class StudyRouter: ObservableObject {
    @Published var page: StudyPage = .home
    @Published var deckID: UUID?
    @Published var listID: UUID?
    @Published var taskID: UUID?
    @Published var focused = false
    @Published var palette = false
    @Published var capture: CaptureRequest?
    @Published var newDeckRequested = false
    @Published var settingsRequested = false
    @Published var generation = UUID()
    @Published var reviewRequested = false
}

@MainActor final class StudyHub: ObservableObject {
    let library: Library
    let todos: TodoStore
    let notes: NotesStore
    let workspace: WorkspaceStore
    let router = StudyRouter()
    let pomodoro: PomodoroStore
    let editors = NoteEditorCache()
    let audio: AmbientAudioController
    let directory: URL
    let defaults: UserDefaults
    @Published var error: String?
    @Published var notice: String?
    @Published var recoveryArchive: URL?
    @Published private(set) var startupBlocked = false
    @Published var automaticBackupDate: Date?
    @Published var automaticBackupError: String?
    private var backupTimer: Timer?
    private var observers = Set<AnyCancellable>()

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("unnamedstudytool")
        self.defaults = defaults
        var recoveryError: String?
        do { try WorkspaceTransaction.recover(in: self.directory, defaults: defaults) }
        catch { recoveryError = "Startup recovery needs attention. \(error.localizedDescription)" }
        library = Library(fileURL: self.directory.appendingPathComponent("library.json"))
        todos = TodoStore(url: self.directory.appendingPathComponent("todos.json"))
        notes = NotesStore(url: self.directory.appendingPathComponent("notes.json"), defaults: defaults)
        workspace = WorkspaceStore(url: self.directory.appendingPathComponent("workspace.json"))
        pomodoro = PomodoroStore(defaults: defaults)
        audio = AmbientAudioController(defaults: defaults)
        error = recoveryError
        startupBlocked = recoveryError != nil
        library.beforeRemoving = { [weak self] old, new in self?.archiveRemoved(old: old, new: new) ?? false }
        todos.didSave = { [weak self] old, new in self?.tasksSaved(old: old, new: new) }
        pomodoro.onCompletion = { [weak self] id, seconds in
            guard let self else { return }
            let intention = self.workspace.state.intention
            self.workspace.record(StudyEvent(id: id.uuidString, kind: .focusCompleted, occurredAt: Date(), value: Int(seconds), reference: intention?.reference, labelSnapshot: intention?.labelSnapshot))
        }
        pomodoro.onStateChange = { [weak self] in
            guard let self else { return }
            self.audio.timerChanged(running: self.pomodoro.clock.running, focus: self.pomodoro.clock.phase == .focus, completed: self.pomodoro.clock.awaitingNext)
        }
        // Reconcile references after content deletion/import, after the new value is published.
        library.$decks.dropFirst().sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in: &observers)
        todos.$lists.dropFirst().sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in: &observers)
        notes.$notes.dropFirst().map { $0.map(\.id) }.removeDuplicates().sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in: &observers)
        backupTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.automaticBackup() }
        }
        Task { @MainActor [weak self] in self?.automaticBackup() }
    }
    var destinations: [StudyDestination] {
        library.decks.map { StudyDestination(reference: .init(kind: .deck, id: $0.id), title: $0.name, subtitle: "Flashcards") }
        + notes.notes.map { StudyDestination(reference: .init(kind: .note, id: $0.id), title: $0.displayTitle, subtitle: "Notes") }
        + todos.lists.map { StudyDestination(reference: .init(kind: .todoList, id: $0.id), title: $0.name, subtitle: "To-do list") }
        + todos.lists.flatMap { list in list.items.map { StudyDestination(reference: .init(kind: .todoItem, id: $0.id, parentID: list.id), title: $0.title, subtitle: list.name) } }
    }
    func resolve(_ reference: StudyItemReference) -> StudyDestination? {
        switch reference.kind {
        case .deck:
            return library.decks.first { $0.id == reference.id }.map { StudyDestination(reference: reference, title: $0.name, subtitle: "Flashcards") }
        case .note:
            return notes.notes.first { $0.id == reference.id }.map { StudyDestination(reference: reference, title: $0.displayTitle, subtitle: "Notes") }
        case .todoList:
            return todos.lists.first { $0.id == reference.id }.map { StudyDestination(reference: reference, title: $0.name, subtitle: "To-do list") }
        case .todoItem:
            guard let list = todos.lists.first(where: { $0.id == reference.parentID }) else { return nil }
            return list.items.first { $0.id == reference.id }.map { StudyDestination(reference: reference, title: $0.title, subtitle: list.name) }
        }
    }
    var currentReference: StudyItemReference? {
        switch router.page {
        case .notes: return notes.selectedID.map { .init(kind: .note, id: $0) }
        case .flashcards: return router.deckID.map { .init(kind: .deck, id: $0) }
        case .todos: return (router.listID ?? todos.lists.first?.id).map { .init(kind: .todoList, id: $0) }
        default: return nil
        }
    }
    @discardableResult func navigate(_ page: StudyPage) -> Bool {
        guard !startupBlocked else { return false }
        guard !notes.loaded || notes.flush() else { error = notes.error; return false }
        router.page = page
        if page == .home { router.focused = false }
        return true
    }
    func run(_ command: StudyCommand) {
        guard !startupBlocked else { error = "Resolve startup recovery before making changes."; return }
        switch command {
        case .page(let page): navigate(page)
        case .open(let reference):
            guard resolve(reference) != nil else { error = "This item is no longer available."; reconcile(); return }
            guard !notes.loaded || notes.flush() else { error = notes.error; return }
            switch reference.kind {
            case .deck: router.deckID = reference.id; router.page = .flashcards
            case .note: guard notes.select(reference.id) else { error = notes.error; return }; router.page = .notes
            case .todoList: router.listID = reference.id; router.taskID = nil; router.page = .todos
            case .todoItem: router.listID = reference.parentID; router.taskID = reference.id; router.page = .todos
            }
            workspace.opened(reference)
        case .capture(let kind): router.capture = CaptureRequest(kind: kind)
        case .focus(let reference):
            if let reference {
                guard let item = resolve(reference) else { error = "This item is no longer available."; return }
                guard !pomodoro.clock.running, pomodoro.clock.remaining == pomodoro.clock.duration, !pomodoro.clock.awaitingNext else {
                    error = "Finish or reset the current interval before changing its intention."; return
                }
                guard workspace.change({ $0.intention = FocusIntention(reference: reference, labelSnapshot: item.title) }) else { return }
            }
            if !pomodoro.clock.running {
                if pomodoro.clock.awaitingNext { pomodoro.next() } else { pomodoro.toggle() }
            }
        case .toggleTimer:
            if pomodoro.clock.awaitingNext { pomodoro.next() } else { pomodoro.toggle() }
        case .focusMode: if router.page != .home { router.focused.toggle() }
        case .newDeck: if navigate(.flashcards) { router.generation = UUID(); router.newDeckRequested = true }
        case .settings: router.settingsRequested = true
        }
    }
    func captureCard(from text: String) { router.capture = CaptureRequest(kind: .card, answer: text) }
    func studied(_ session: StudySession) {
        workspace.change { value in
            for deckID in Set(session.sources.values) {
                var progress = value.progress[deckID] ?? DeckStudyProgress()
                progress.reviewedCardIDs.formUnion(session.reviewed.filter { session.sources[$0] == deckID })
                progress.lastCardID = session.queue.first(where: { session.sources[$0.id] == deckID })?.id
                progress.updatedAt = Date(); value.progress[deckID] = progress
            }
            let key = CalendarDay().key
            if let reviewed = session.reviewedByDay[key], !reviewed.isEmpty {
                let id = "cards:\(session.id):\(key)"
                let oldDate = value.events.first { $0.id == id }?.occurredAt ?? Date()
                value.events.removeAll { $0.id == id }
                value.events.append(StudyEvent(id: id, kind: .cardsReviewed, occurredAt: oldDate, value: reviewed.count, reference: nil, labelSnapshot: "Flashcard session"))
            }
        }
    }
    func reconcile() {
        guard workspace.loaded, library.loaded, todos.loaded, notes.loaded, !startupBlocked else { return }
        let valid = Set(destinations.map(\.reference))
        workspace.change {
            $0.pins.removeAll { !valid.contains($0.reference) }
            $0.recent.removeAll { !valid.contains($0.reference) }
            $0.progress = $0.progress.filter { key, _ in library.decks.contains { $0.id == key } }
            for deck in library.decks {
                if var p = $0.progress[deck.id] {
                    let ids = Set(deck.cards.map(\.id)); p.reviewedCardIDs.formIntersection(ids)
                    if let id = p.lastCardID, !ids.contains(id) { p.lastCardID = deck.cards.first?.id }
                    $0.progress[deck.id] = p
                }
            }
            let cardIDs = Set(library.decks.flatMap(\.cards).map(\.id))
            $0.reviews = $0.reviews?.filter { cardIDs.contains($0.key) }
        }
    }
    var dueCards: [Card] {
        let reviews = workspace.state.reviews ?? [:], now = Date()
        return library.decks.flatMap(\.cards).filter { reviews[$0.id].map { $0.due <= now } ?? false }
            .sorted { (reviews[$0.id]?.due ?? .distantFuture) < (reviews[$1.id]?.due ?? .distantFuture) }
    }
    func startReview() {
        guard navigate(.flashcards) else { return }
        if let first = dueCards.first { router.deckID = library.decks.first(where: { $0.cards.contains { $0.id == first.id } })?.id }
        router.generation = UUID(); router.reviewRequested = true
    }
    func rate(_ card: Card, confidence: StudySession.Confidence) {
        workspace.change {
            var reviews = $0.reviews ?? [:]
            reviews[card.id] = ReviewSchedule.next(confidence, previous: reviews[card.id])
            $0.reviews = reviews
        }
    }
    private func archiveRemoved(old: [Deck], new: [Deck]) -> Bool {
        let remaining = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        var entries: [DeletedFlashcards] = []
        for deck in old {
            if let replacement = remaining[deck.id] {
                let ids = Set(replacement.cards.map(\.id))
                let removed = deck.cards.filter { !ids.contains($0.id) }
                if !removed.isEmpty { entries.append(DeletedFlashcards(deck: Deck(id: deck.id, name: deck.name, cards: removed), wholeDeck: false)) }
            } else { entries.append(DeletedFlashcards(deck: deck, wholeDeck: true)) }
        }
        guard !entries.isEmpty else { return true }
        return workspace.change {
            var archived = ($0.deletedFlashcards ?? []).filter { $0.expiresAt > Date() }
            for entry in entries where !archived.contains(where: { $0.deck == entry.deck && $0.wholeDeck == entry.wholeDeck }) { archived.append(entry) }
            $0.deletedFlashcards = archived
        }
    }
    func restoreDeleted(_ entry: DeletedFlashcards) {
        guard entry.expiresAt > Date() else { error = "This recovery copy has expired."; return }
        var decks = library.decks
        let activeIDs = Set(decks.flatMap(\.cards).map(\.id))
        let cards = entry.deck.cards.filter { !activeIDs.contains($0.id) }
        if let index = decks.firstIndex(where: { $0.id == entry.deck.id }) { decks[index].cards += cards }
        else { decks.append(Deck(id: entry.deck.id, name: entry.deck.name, cards: cards)) }
        guard library.save(decks) else { error = library.error; return }
        if workspace.change({ $0.deletedFlashcards?.removeAll { $0.id == entry.id } }) { notice = "Flashcards restored" }
    }
    var automaticBackupDirectory: URL { directory.appendingPathComponent("Daily Backups", isDirectory: true) }
    func automaticBackup() {
        guard defaults.object(forKey: "automaticBackups") == nil || defaults.bool(forKey: "automaticBackups"), !startupBlocked else { return }
        guard automaticBackupDate.map({ Calendar.current.isDateInToday($0) }) != true else { return }
        do {
            if (workspace.state.deletedFlashcards ?? []).contains(where: { $0.expiresAt <= Date() }) {
                guard workspace.change({ $0.deletedFlashcards?.removeAll { $0.expiresAt <= Date() } }) else {
                    throw WorkspaceFailure.invalid(workspace.error ?? "Recovery cleanup could not be saved.")
                }
            }
            let snapshot = try backup()
            let url = try DailyBackups.save(snapshot, in: automaticBackupDirectory)
            automaticBackupDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            automaticBackupError = nil
        } catch { automaticBackupError = "Automatic backup could not be saved. \(error.localizedDescription)" }
    }
    func toggleTask(_ reference: StudyItemReference) {
        guard let index = todos.lists.firstIndex(where: { $0.id == reference.parentID }),
              let taskIndex = todos.lists[index].items.firstIndex(where: { $0.id == reference.id }) else { error = "This task is no longer available."; return }
        var list = todos.lists[index]; list.items[taskIndex].done.toggle(); todos.update(list)
    }
    private func tasksSaved(old: [TodoList], new: [TodoList]) {
        let before = Dictionary(uniqueKeysWithValues: old.flatMap(\.items).map { ($0.id, $0.done) })
        for list in new {
            for item in list.items where before[item.id] != item.done {
                workspace.change { state in
                    state.events.removeAll { $0.kind == .taskCompleted && $0.reference?.id == item.id }
                    if item.done {
                        state.events.append(StudyEvent(id: "task:\(item.id)", kind: .taskCompleted, occurredAt: Date(), value: 1, reference: .init(kind: .todoItem, id: item.id, parentID: list.id), labelSnapshot: item.title))
                    }
                }
            }
        }
    }
    func backup() throws -> WorkspaceBackup {
        guard library.loaded, todos.loaded, notes.loaded, workspace.loaded, notes.flush(), workspace.flush(), !startupBlocked else {
            throw WorkspaceFailure.invalid("Some data could not be read or saved. Repair it before exporting or merging a backup.")
        }
        reconcile()
        return WorkspaceBackup(decks: library.decks, todoLists: todos.lists, notes: notes.notes, workspace: workspace.state, settings: ExportedSettings(defaults: defaults))
    }
    func restore(_ imported: WorkspaceBackup, merge: Bool) throws {
        guard !startupBlocked else { throw WorkspaceFailure.invalid("Reopen the app to complete startup recovery first.") }
        guard !notes.dirty || notes.flush() else { throw WorkspaceFailure.invalid("Save or export your unsaved note before importing.") }
        let result = try merge ? backup().merging(imported) : imported
        recoveryArchive = try WorkspaceTransaction.install(result, in: directory, defaults: defaults)
        audio.stop(); pomodoro.reset()
        library.acceptRestored(result.decks); todos.acceptRestored(result.todoLists)
        notes.acceptRestored(result.notes, data: try JSONEncoder().encode(result.notes))
        workspace.acceptRestored(result.workspace); editors.views.removeAll()
        router.generation = UUID(); router.page = .home; router.deckID = nil; router.listID = nil; router.taskID = nil; router.focused = false
        notice = "Workspace imported. A recovery archive was saved on this Mac."
    }
}
