import Foundation

struct StudyNotePage: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var body = ""

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled page" : trimmed
    }
}

struct StudyNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var body = ""
    var pages: [StudyNotePage] = []
    var modified = Date()
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled note" : trimmed
    }
    var preview: String {
        let source = ([body] + pages.map(\.body)).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        let text = source.prefix(180).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? "No text yet" : text
    }
    var exportText: String {
        ([StudyNotePage(id: id, title: title, body: body)] + pages).map { page in
            page.title.isEmpty ? page.body : "\(page.title)\n\n\(page.body)"
        }.joined(separator: "\n\n\u{2500}\u{2500}\u{2500}\n\n")
    }
    var searchableText: String {
        ([title, body] + pages.flatMap { [$0.title, $0.body] }).joined(separator: "\n")
    }
    var editorIDs: [UUID] { [id] + pages.map(\.id) }

    private enum CodingKeys: String, CodingKey { case id, title, body, pages, modified }

    init(id: UUID = UUID(), title: String = "", body: String = "", pages: [StudyNotePage] = [], modified: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.pages = pages
        self.modified = modified
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        body = try values.decode(String.self, forKey: .body)
        pages = try values.decodeIfPresent([StudyNotePage].self, forKey: .pages) ?? []
        modified = try values.decode(Date.self, forKey: .modified)
    }
}

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [StudyNote] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var dirty = false
    @Published private(set) var loaded = false
    @Published private(set) var deleted: StudyNote?
    @Published var error: String?
    @Published var search = ""
    let url: URL
    private let defaults: UserDefaults
    private var pendingSave: Task<Void, Never>?
    private var savedData: Data?
    private(set) var saveFailed = false
    private(set) var contentEpoch = UUID()

    func acceptRestored(_ values: [StudyNote], data: Data) {
        contentEpoch = UUID()
        pendingSave?.cancel(); pendingSave = nil
        notes = values; savedData = data; loaded = true; dirty = false; saveFailed = false
        error = nil; deleted = nil; search = ""; selectedID = sortedNotes.first?.id
        defaults.set(selectedID?.uuidString, forKey: "selectedNote")
    }

    init(url: URL? = nil, defaults: UserDefaults = .standard) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("unnamedstudytool/notes.json")
        self.defaults = defaults
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                let data = try Data(contentsOf: self.url)
                notes = try Self.decode(data)
                savedData = data
            }
            loaded = true
            let savedSelection = defaults.string(forKey: "selectedNote").flatMap(UUID.init(uuidString:))
            selectedID = notes.first(where: { $0.id == savedSelection })?.id ?? sortedNotes.first?.id
        } catch {
            self.error = "Notes could not be opened. Your saved file is preserved. Restore the previous save or export any text before repairing notes.json. \(error.localizedDescription)"
        }
    }

    private static func decode(_ data: Data) throws -> [StudyNote] {
        let notes = try JSONDecoder().decode([StudyNote].self, from: data)
        let noteIDs = notes.map(\.id)
        let pageIDs = notes.flatMap { $0.pages.map(\.id) }
        guard Set(noteIDs).count == noteIDs.count,
              Set(noteIDs + pageIDs).count == noteIDs.count + pageIDs.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return notes
    }
    var selected: StudyNote? { notes.first { $0.id == selectedID } }
    var sortedNotes: [StudyNote] {
        notes.sorted { $0.modified == $1.modified ? $0.id.uuidString < $1.id.uuidString : $0.modified > $1.modified }
    }
    var matchingNotes: [StudyNote] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter { query.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(query) }
            .sorted { $0.modified == $1.modified ? $0.id.uuidString < $1.id.uuidString : $0.modified > $1.modified }
    }
    var status: String { !loaded ? "Unavailable" : saveFailed ? "Not saved" : dirty ? "Saving…" : "Saved" }
    var recoveryURL: URL { url.deletingPathExtension().appendingPathExtension("previous.json") }
    var canRecover: Bool { FileManager.default.fileExists(atPath: recoveryURL.path) }

    @discardableResult func select(_ id: UUID) -> Bool {
        guard flush() else { return false }
        selectedID = id
        defaults.set(id.uuidString, forKey: "selectedNote")
        return true
    }
    @discardableResult func create() -> UUID? {
        guard flush(), loaded else { return nil }
        let note = StudyNote()
        notes.insert(note, at: 0)
        selectedID = note.id
        defaults.set(note.id.uuidString, forKey: "selectedNote")
        search = ""
        dirty = true
        flush()
        return note.id
    }
    func edit(id: UUID, title: String? = nil, body: String? = nil) {
        guard loaded, let index = notes.firstIndex(where: { $0.id == id }) else {
            error = "This note is unavailable. Your text has not been saved."
            return
        }
        guard title.map({ $0 != notes[index].title }) == true || body.map({ $0 != notes[index].body }) == true else { return }
        if let title { notes[index].title = title }
        if let body { notes[index].body = body }
        notes[index].modified = Date()
        dirty = true
        scheduleSave()
    }

    @discardableResult func addPage(to noteID: UUID) -> UUID? {
        guard flush(), loaded, let index = notes.firstIndex(where: { $0.id == noteID }) else {
            error = "This note is unavailable, so a new page could not be added."
            return nil
        }
        let page = StudyNotePage()
        notes[index].pages.append(page)
        notes[index].modified = Date()
        dirty = true
        guard flush() else { return nil }
        return page.id
    }

    func editPage(noteID: UUID, pageID: UUID, title: String? = nil, body: String? = nil) {
        guard loaded,
              let noteIndex = notes.firstIndex(where: { $0.id == noteID }),
              let pageIndex = notes[noteIndex].pages.firstIndex(where: { $0.id == pageID }) else {
            error = "This page is unavailable. Your text has not been saved."
            return
        }
        let page = notes[noteIndex].pages[pageIndex]
        guard title.map({ $0 != page.title }) == true || body.map({ $0 != page.body }) == true else { return }
        if let title { notes[noteIndex].pages[pageIndex].title = title }
        if let body { notes[noteIndex].pages[pageIndex].body = body }
        notes[noteIndex].modified = Date()
        dirty = true
        scheduleSave()
    }

    @discardableResult func deletePage(noteID: UUID, pageID: UUID) -> Bool {
        guard flush(), loaded, let noteIndex = notes.firstIndex(where: { $0.id == noteID }) else {
            error = "This note is unavailable, so the page could not be deleted."
            return false
        }
        guard notes[noteIndex].pages.contains(where: { $0.id == pageID }) else {
            error = "This page is no longer available."
            return false
        }
        notes[noteIndex].pages.removeAll { $0.id == pageID }
        notes[noteIndex].modified = Date()
        dirty = true
        return flush()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) }
            catch { return } // Cancellation is the only error from this sleep.
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    @discardableResult func flush() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard loaded else { return false }
        guard dirty else { return true }
        do {
            let data = try JSONEncoder().encode(notes)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let savedData { try savedData.write(to: recoveryURL, options: .atomic) }
            try data.write(to: url, options: .atomic)
            savedData = data
            saveFailed = false
            dirty = false
            error = nil
            return true
        } catch {
            saveFailed = true
            self.error = "Your latest text is still in memory, but could not be saved. Retry saving or export a text copy before quitting. \(error.localizedDescription)"
            return false
        }
    }
    func deleteSelected() {
        guard flush(), let selected else { return }
        deleted = selected
        notes.removeAll { $0.id == selected.id }
        selectedID = sortedNotes.first?.id
        defaults.set(selectedID?.uuidString, forKey: "selectedNote")
        dirty = true
        flush()
    }
    func undoDelete() {
        guard loaded, let deleted else { return }
        notes.append(deleted)
        selectedID = deleted.id
        defaults.set(deleted.id.uuidString, forKey: "selectedNote")
        self.deleted = nil
        search = ""
        dirty = true
        flush()
    }
    func restorePreviousSave() {
        do {
            let data = try Data(contentsOf: recoveryURL)
            let restored = try Self.decode(data)
            // Preserve the current on-disk file before an explicit recovery.
            if FileManager.default.fileExists(atPath: url.path) {
                let original = try Data(contentsOf: url)
                let archive = url.deletingLastPathComponent().appendingPathComponent("notes-before-recovery-\(UUID().uuidString).json")
                try original.write(to: archive, options: .atomic)
            }
            try data.write(to: url, options: .atomic)
            contentEpoch = UUID()
            notes = restored
            savedData = data
            loaded = true
            dirty = false
            saveFailed = false
            error = nil
            selectedID = sortedNotes.first?.id
        } catch { self.error = "Recovery failed. Existing files were preserved. \(error.localizedDescription)" }
    }
}
