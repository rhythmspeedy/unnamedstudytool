import Foundation
import CryptoKit

struct ExportedSettings: Codable {
    var strings: [String: String] = [:]
    var integers: [String: Int] = [:]
    var booleans: [String: Bool] = [:]
    var decimals: [String: Double] = [:]
    static let stringKeys = ["theme", "focusSize", "ambientSound"]
    static let integerKeys = ["pomodoroFocus", "pomodoroShort", "pomodoroLong", "timerSeconds"]
    static let booleanKeys = ["shuffle", "timerEnabled", "menuBarTimer", "ambientStopAtEnd", "automaticBackups"]
    static let decimalKeys = ["ambientVolume"]
    init(defaults: UserDefaults) {
        for key in Self.stringKeys { strings[key] = defaults.string(forKey: key) }
        for key in Self.integerKeys where defaults.object(forKey: key) != nil { integers[key] = defaults.integer(forKey: key) }
        for key in Self.booleanKeys where defaults.object(forKey: key) != nil { booleans[key] = defaults.bool(forKey: key) }
        for key in Self.decimalKeys where defaults.object(forKey: key) != nil { decimals[key] = defaults.double(forKey: key) }
    }
    func validate() throws {
        guard Set(strings.keys).isSubset(of: Set(Self.stringKeys)), Set(integers.keys).isSubset(of: Set(Self.integerKeys)),
              Set(booleans.keys).isSubset(of: Set(Self.booleanKeys)), Set(decimals.keys).isSubset(of: Set(Self.decimalKeys)),
              integers.allSatisfy({ $0.key == "timerSeconds" ? (5...300).contains($0.value) : (1...120).contains($0.value) }),
              decimals.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw WorkspaceFailure.invalid("The backup contains invalid settings.")
        }
    }
    func apply(to defaults: UserDefaults) {
        for key in Self.stringKeys + Self.integerKeys + Self.booleanKeys + Self.decimalKeys { defaults.removeObject(forKey: key) }
        strings.forEach { defaults.set($0.value, forKey: $0.key) }
        integers.forEach { defaults.set($0.value, forKey: $0.key) }
        booleans.forEach { defaults.set($0.value, forKey: $0.key) }
        decimals.forEach { defaults.set($0.value, forKey: $0.key) }
    }
}

struct WorkspaceBackup: Codable {
    var formatVersion = 1
    var exportedAt = Date()
    var appVersion = "1.2"
    var decks: [Deck]
    var todoLists: [TodoList]
    var notes: [StudyNote]
    var workspace: WorkspaceState
    var settings: ExportedSettings

    func validate() throws {
        guard formatVersion == 1 else { throw WorkspaceFailure.invalid("This backup format is not supported by this app version.") }
        let ids = decks.map(\.id) + decks.flatMap(\.cards).map(\.id) + todoLists.map(\.id) + todoLists.flatMap(\.items).map(\.id) + notes.map(\.id)
        guard Set(ids).count == ids.count, !todoLists.isEmpty,
              decks.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              todoLists.allSatisfy({ !$0.name.isEmpty && $0.items.allSatisfy { !$0.title.isEmpty } }) else {
            throw WorkspaceFailure.invalid("The backup contains duplicate identifiers or invalid content.")
        }
        for task in todoLists.flatMap(\.items) {
            guard (task.materials ?? []).allSatisfy({ $0.kind == .deck || $0.kind == .note }),
                  Set(task.materials ?? []).count == (task.materials ?? []).count else { throw WorkspaceFailure.invalid("A task has invalid material links.") }
            for day in [task.dueDay, task.scheduledDay].compactMap({ $0 }) {
                guard CalendarDay(day.date) == day else { throw WorkspaceFailure.invalid("A task has an invalid date.") }
            }
        }
        try WorkspaceStore.validate(workspace)
        guard Set((workspace.reviews ?? [:]).keys).isSubset(of: Set(decks.flatMap(\.cards).map(\.id))) else {
            throw WorkspaceFailure.invalid("A review points to a missing card.")
        }
        try settings.validate()
        let references = Set(decks.map { StudyItemReference(kind: .deck, id: $0.id) }
            + notes.map { StudyItemReference(kind: .note, id: $0.id) }
            + todoLists.map { StudyItemReference(kind: .todoList, id: $0.id) }
            + todoLists.flatMap { list in list.items.map { StudyItemReference(kind: .todoItem, id: $0.id, parentID: list.id) } })
        guard workspace.pins.allSatisfy({ references.contains($0.reference) }),
              workspace.recent.allSatisfy({ references.contains($0.reference) }) else {
            throw WorkspaceFailure.invalid("The backup contains a pin or recent item with a missing destination.")
        }
        for (id, progress) in workspace.progress {
            guard let deck = decks.first(where: { $0.id == id }), progress.reviewedCardIDs.isSubset(of: Set(deck.cards.map(\.id))),
                  progress.lastCardID == nil || deck.cards.contains(where: { $0.id == progress.lastCardID }) else {
                throw WorkspaceFailure.invalid("The backup contains invalid deck progress.")
            }
        }
    }

    func encoded() throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        return try JSONEncoder().encode(BackupEnvelope(formatVersion: 1, payload: data, sha256: Self.digest(data)))
    }
    static func decode(_ data: Data) throws -> Self {
        let envelope = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        guard envelope.formatVersion == 1, digest(envelope.payload) == envelope.sha256 else {
            throw WorkspaceFailure.invalid("The backup version or checksum is invalid. Nothing was changed.")
        }
        let value = try JSONDecoder().decode(Self.self, from: envelope.payload)
        try value.validate(); return value
    }
    static func decodeRecoveryArchive(_ data: Data) throws -> Self {
        let journal = try JSONDecoder().decode(WorkspaceTransaction.Journal.self, from: data)
        guard Set(journal.originals.keys).union(journal.absent) == Set(WorkspaceTransaction.fileNames) else {
            throw WorkspaceFailure.invalid("This is not a valid recovery archive.")
        }
        func decode<T: Decodable>(_ name: String, fallback: T) throws -> T {
            if let data = journal.originals[name] { return try JSONDecoder().decode(T.self, from: data) }
            return fallback
        }
        let backup = WorkspaceBackup(decks: try decode("library.json", fallback: [Deck]()), todoLists: try decode("todos.json", fallback: [TodoList(name: "My list")]), notes: try decode("notes.json", fallback: [StudyNote]()), workspace: try decode("workspace.json", fallback: WorkspaceState()), settings: journal.settings)
        try backup.validate(); return backup
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Import independent copies and remap every cross-feature reference.
    func merging(_ imported: Self) throws -> Self {
        try imported.validate()
        var result = self
        let allIDs = imported.decks.map(\.id) + imported.decks.flatMap(\.cards).map(\.id)
            + imported.todoLists.map(\.id) + imported.todoLists.flatMap(\.items).map(\.id) + imported.notes.map(\.id)
        let archivedIDs = (imported.workspace.deletedFlashcards ?? []).flatMap { [$0.deck.id] + $0.deck.cards.map(\.id) }
        let mapping = Dictionary(uniqueKeysWithValues: Set(allIDs + archivedIDs).map { ($0, UUID()) })
        func ref(_ old: StudyItemReference) -> StudyItemReference? {
            guard let id = mapping[old.id] else { return nil }
            return StudyItemReference(kind: old.kind, id: id, parentID: old.parentID.flatMap { mapping[$0] })
        }
        result.decks += imported.decks.map { old in
            var deck = old; deck.id = mapping[old.id]!
            deck.cards = old.cards.map { var c = $0; c.id = mapping[c.id]!; return c }; return deck
        }
        result.todoLists += imported.todoLists.map { old in
            var list = old; list.id = mapping[old.id]!
            list.items = old.items.map { var item = $0; item.id = mapping[item.id]!; item.materials = item.materials?.compactMap(ref); return item }; return list
        }
        result.notes += imported.notes.map { var note = $0; note.id = mapping[note.id]!; return note }
        for pin in imported.workspace.pins where result.workspace.pins.count < 5 {
            if let reference = ref(pin.reference) { result.workspace.pins.append(PinnedItem(reference: reference, pinnedAt: pin.pinnedAt)) }
        }
        for (id, progress) in imported.workspace.progress {
            if let id = mapping[id] {
                result.workspace.progress[id] = DeckStudyProgress(lastCardID: progress.lastCardID.flatMap { mapping[$0] }, reviewedCardIDs: Set(progress.reviewedCardIDs.compactMap { mapping[$0] }), updatedAt: progress.updatedAt)
            }
        }
        result.workspace.events += imported.workspace.events.map {
            StudyEvent(id: UUID().uuidString, kind: $0.kind, occurredAt: $0.occurredAt, value: $0.value, reference: $0.reference.flatMap(ref), labelSnapshot: $0.labelSnapshot)
        }
        for (id, review) in imported.workspace.reviews ?? [:] {
            if let id = mapping[id] {
                if result.workspace.reviews == nil { result.workspace.reviews = [:] }
                result.workspace.reviews?[id] = review
            }
        }
        let recovered = (imported.workspace.deletedFlashcards ?? []).map { entry in
            var entry = entry; entry.id = UUID(); entry.deck.id = mapping[entry.deck.id]!
            entry.deck.cards = entry.deck.cards.map { var card = $0; card.id = mapping[card.id]!; return card }
            return entry
        }
        if !recovered.isEmpty { result.workspace.deletedFlashcards = (result.workspace.deletedFlashcards ?? []) + recovered }
        // Keep current settings, targets, recent items, and active intention during a merge.
        try result.validate(); return result
    }
}
private struct BackupEnvelope: Codable { let formatVersion: Int; let payload: Data; let sha256: String }

/// Durable rollback journal protects multi-file imports, including process termination.
enum WorkspaceTransaction {
    static let fileNames = ["library.json", "todos.json", "notes.json", "workspace.json"]
    struct Journal: Codable {
        let originals: [String: Data]
        let absent: [String]
        let settings: ExportedSettings
    }
    static func recover(in directory: URL, defaults: UserDefaults) throws {
        let journalURL = directory.appendingPathComponent("restore-journal.json")
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        guard Set(journal.originals.keys).union(journal.absent) == Set(fileNames) else { throw WorkspaceFailure.invalid("Recovery journal is invalid. Your files have been preserved.") }
        try journal.settings.validate()
        for name in fileNames {
            let url = directory.appendingPathComponent(name)
            if let data = journal.originals[name] { try data.write(to: url, options: .atomic) }
            else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        journal.settings.apply(to: defaults)
        try FileManager.default.removeItem(at: journalURL)
    }
    static func install(_ backup: WorkspaceBackup, in directory: URL, defaults: UserDefaults,
                        write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws -> URL {
        try backup.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let journalURL = directory.appendingPathComponent("restore-journal.json")
        guard !FileManager.default.fileExists(atPath: journalURL.path) else { throw WorkspaceFailure.invalid("An earlier import needs recovery. Reopen the app before importing again.") }
        var originals: [String: Data] = [:]
        var absent: [String] = []
        for name in fileNames {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { originals[name] = try Data(contentsOf: url) } else { absent.append(name) }
        }
        let journal = Journal(originals: originals, absent: absent, settings: ExportedSettings(defaults: defaults))
        let journalData = try JSONEncoder().encode(journal)
        let archive = directory.appendingPathComponent("before-import-\(UUID().uuidString).json")
        try journalData.write(to: archive, options: .atomic)
        let payloads = [try JSONEncoder().encode(backup.decks), try JSONEncoder().encode(backup.todoLists), try JSONEncoder().encode(backup.notes), try JSONEncoder().encode(backup.workspace)]
        try journalData.write(to: journalURL, options: .atomic)
        do {
            for (name, data) in zip(fileNames, payloads) { try write(data, directory.appendingPathComponent(name)) }
            backup.settings.apply(to: defaults)
            try FileManager.default.removeItem(at: journalURL)
            return archive
        } catch {
            let originalError = error
            do { try recover(in: directory, defaults: defaults) }
            catch { throw WorkspaceFailure.invalid("Import failed and rollback needs attention. Keep the app closed and preserve \(archive.lastPathComponent). \(error.localizedDescription)") }
            throw WorkspaceFailure.invalid("Import failed; your original data was restored. \(originalError.localizedDescription)")
        }
    }
}
