import Foundation

enum StudyItemKind: String, Codable { case deck, note, todoList, todoItem }
struct StudyItemReference: Codable, Hashable, Identifiable {
    let kind: StudyItemKind
    let id: UUID
    var parentID: UUID? = nil
    var key: String { "\(kind.rawValue):\(id)" }
}
struct PinnedItem: Codable, Identifiable, Equatable {
    var id = UUID()
    let reference: StudyItemReference
    var pinnedAt = Date()
}
struct RecentItem: Codable, Equatable {
    let reference: StudyItemReference
    var openedAt = Date()
}
enum TargetMetric: String, Codable, CaseIterable, Identifiable {
    case focusMinutes = "Focus minutes", cardsReviewed = "Cards reviewed", focusIntervals = "Focus intervals"
    var id: String { rawValue }
}
struct DailyTarget: Codable, Equatable {
    var enabled = false
    var metric: TargetMetric = .focusMinutes
    var amount = 25
}
enum StudyEventKind: String, Codable { case focusCompleted, cardsReviewed, taskCompleted }
struct StudyEvent: Codable, Identifiable, Equatable {
    let id: String
    let kind: StudyEventKind
    var occurredAt: Date
    var value: Int
    var reference: StudyItemReference?
    var labelSnapshot: String?
}
struct FocusIntention: Codable, Equatable {
    let reference: StudyItemReference
    let labelSnapshot: String
}
struct DeckStudyProgress: Codable, Equatable {
    var lastCardID: UUID?
    var reviewedCardIDs: Set<UUID> = []
    var updatedAt = Date()
}
struct WorkspaceState: Codable, Equatable {
    var schemaVersion = 1
    var pins: [PinnedItem] = []
    var recent: [RecentItem] = []
    var target = DailyTarget()
    var events: [StudyEvent] = []
    var progress: [UUID: DeckStudyProgress] = [:]
    var intention: FocusIntention?
    var reviews: [UUID: ReviewSchedule]?
    var deletedFlashcards: [DeletedFlashcards]?
}
enum WorkspaceFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
struct CalendarDay: Codable, Equatable, Comparable {
    var year: Int
    var month: Int
    var day: Int
    init(_ date: Date = Date(), calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        year = c.year!; month = c.month!; day = c.day!
    }
    var date: Date { Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date.distantPast }
    var key: String { "\(year)-\(month)-\(day)" }
    static func < (lhs: Self, rhs: Self) -> Bool { (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day) }
}

@MainActor final class WorkspaceStore: ObservableObject {
    @Published private(set) var state = WorkspaceState()
    @Published private(set) var loaded = false
    @Published private(set) var lastSaved: Date?
    @Published private(set) var dirty = false
    @Published var error: String?
    let url: URL
    init(url: URL) {
        self.url = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)
                try Self.validate(decoded)
                state = decoded
            }
            loaded = true
        } catch { self.error = "Workspace could not be opened. The original file is preserved. \(error.localizedDescription)" }
    }
    nonisolated static func validate(_ value: WorkspaceState) throws {
        guard value.schemaVersion == 1 else { throw WorkspaceFailure.invalid("This workspace needs a different app version.") }
        guard (value.reviews ?? [:]).values.allSatisfy({ (0...30).contains($0.intervalDays) && $0.due.timeIntervalSince1970.isFinite }),
              Set((value.deletedFlashcards ?? []).map(\.id)).count == (value.deletedFlashcards ?? []).count else {
            throw WorkspaceFailure.invalid("Review or recovery data is invalid.")
        }
        for entry in value.deletedFlashcards ?? [] { try Library.validate([entry.deck]) }
        guard (1...10000).contains(value.target.amount), value.pins.count <= 5,
              Set(value.pins.map(\.reference)).count == value.pins.count,
              Set(value.events.map(\.id)).count == value.events.count,
              value.events.allSatisfy({ $0.value >= 0 && $0.value <= 10000000 }) else {
            throw WorkspaceFailure.invalid("Workspace data is invalid.")
        }
    }
    @discardableResult func change(_ edit: (inout WorkspaceState) -> Void) -> Bool {
        guard loaded else { error = "Restore a valid workspace from Settings → Data before saving."; return false }
        var next = state; edit(&next)
        let cutoff = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        next.events.removeAll { $0.occurredAt < cutoff }
        guard next != state else { return !dirty || flush() }
        do {
            try Self.validate(next)
            state = next; dirty = true
            return flush()
        } catch { self.error = "Workspace changes are invalid. \(error.localizedDescription)"; return false }
    }
    @discardableResult func flush() -> Bool {
        guard loaded else { return false }
        guard dirty else { return true }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                try Data(contentsOf: url).write(to: url.deletingPathExtension().appendingPathExtension("previous.json"), options: .atomic)
            }
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
            dirty = false; error = nil; lastSaved = Date(); return true
        } catch { self.error = "Workspace changes could not be saved. \(error.localizedDescription)"; return false }
    }
    func acceptRestored(_ value: WorkspaceState) { state = value; loaded = true; dirty = false; error = nil; lastSaved = Date() }
    func pin(_ reference: StudyItemReference) {
        if state.pins.contains(where: { $0.reference == reference }) {
            change { $0.pins.removeAll { $0.reference == reference } }
        } else if state.pins.count < 5 {
            change { $0.pins.append(PinnedItem(reference: reference)) }
        } else { error = "Home has five pins. Unpin an item to make room." }
    }
    func opened(_ reference: StudyItemReference) {
        change {
            $0.recent.removeAll { $0.reference == reference }
            $0.recent.insert(RecentItem(reference: reference), at: 0)
            $0.recent = Array($0.recent.prefix(12))
        }
    }
    func record(_ event: StudyEvent) {
        change {
            $0.events.removeAll { $0.id == event.id }
            $0.events.append(event)
            // Keep two years of local history; no unbounded log of interactions.
            let cutoff = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
            $0.events.removeAll { $0.occurredAt < cutoff }
        }
    }
    func total(_ metric: TargetMetric, on day: Date = Date(), calendar: Calendar = .current) -> Int {
        let events = state.events.filter { calendar.isDate($0.occurredAt, inSameDayAs: day) }
        switch metric {
        case .focusMinutes: return events.filter { $0.kind == .focusCompleted }.reduce(0) { $0 + $1.value } / 60
        case .focusIntervals: return events.filter { $0.kind == .focusCompleted }.count
        case .cardsReviewed: return events.filter { $0.kind == .cardsReviewed }.reduce(0) { $0 + $1.value }
        }
    }
}
