import Foundation

struct Card: Identifiable, Codable, Equatable {
    var id = UUID()
    var front: String
    var back: String
}

struct Deck: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var cards: [Card] = []
}

struct StudySession {
    enum Confidence { case again, unsure, know }
    private struct Snapshot {
        let card: Card
        let mastered: Int
        let reinsertionIndex: Int?
    }

    private(set) var queue: [Card]
    private(set) var mastered = 0
    private var history: [Snapshot] = []
    let id = UUID()
    let sources: [UUID: UUID]
    let sourceNames: [UUID: String]
    private(set) var reviewed: Set<UUID> = []
    private(set) var reviewedByDay: [String: Set<UUID>] = [:]
    let total: Int
    var current: Card? { queue.first }
    var complete: Bool { queue.isEmpty }
    var canGoBack: Bool { !history.isEmpty }

    init(cards: [Card], shuffled: Bool, sources: [UUID: UUID] = [:], sourceNames: [UUID: String] = [:], resumeAt: UUID? = nil) {
        queue = shuffled ? cards.shuffled() : cards
        self.sources = sources; self.sourceNames = sourceNames
        if let resumeAt, let index = queue.firstIndex(where: { $0.id == resumeAt }) {
            queue = Array(queue[index...]) + Array(queue[..<index])
        }
        total = cards.count
    }

    mutating func rate(_ confidence: Confidence) {
        guard let card = current else { return }
        queue.removeFirst()
        let reinsertion: Int?
        switch confidence { case .again: reinsertion = min(2, queue.count); case .unsure: reinsertion = min(5, queue.count); case .know: reinsertion = nil }
        history.append(Snapshot(card: card, mastered: mastered, reinsertionIndex: reinsertion))
        reviewed.insert(card.id)
        reviewedByDay[CalendarDay().key, default: []].insert(card.id)
        switch confidence {
        case .again: queue.insert(card, at: min(2, queue.count))
        case .unsure: queue.insert(card, at: min(5, queue.count))
        case .know: mastered += 1
        }
    }

    mutating func answer(known: Bool) {
        guard !queue.isEmpty else { return }
        let card = queue.removeFirst()
        history.append(Snapshot(card: card, mastered: mastered, reinsertionIndex: known ? nil : queue.count))
        reviewed.insert(card.id)
        reviewedByDay[CalendarDay().key, default: []].insert(card.id)
        if known { mastered += 1 } else { queue.append(card) }
    }

    mutating func goBack() {
        guard let snapshot = history.popLast() else { return }
        if let index = snapshot.reinsertionIndex { queue.remove(at: index) }
        queue.insert(snapshot.card, at: 0)
        mastered = snapshot.mastered
    }
}

@MainActor
final class Library: ObservableObject {
    @Published private(set) var decks: [Deck] = []
    @Published var error: String?
    private(set) var loaded = false
    let fileURL: URL
    var beforeRemoving: (([Deck], [Deck]) -> Bool)?
    func acceptRestored(_ values: [Deck]) { decks = values; loaded = true; error = nil }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("unnamedstudytool", isDirectory: true)
            .appendingPathComponent("library.json")
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                let decoded = try JSONDecoder().decode([Deck].self, from: Data(contentsOf: self.fileURL))
                try Self.validate(decoded)
                decks = decoded
            }
            loaded = true
        } catch {
            self.error = "Your library could not be opened. Your saved file has been preserved. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func save(_ updated: [Deck]) -> Bool {
        guard loaded else {
            error = "Saving is disabled because the existing library could not be read. Restore a valid library.json in Application Support/unnamedstudytool and reopen the app."
            return false
        }
        do {
            try Self.validate(updated)
            guard beforeRemoving?(decks, updated) ?? true else {
                error = "The recovery copy could not be saved. Nothing was deleted."
                return false
            }
            let data = try JSONEncoder().encode(updated)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let previous = try Data(contentsOf: fileURL)
                try previous.write(to: fileURL.deletingPathExtension().appendingPathExtension("previous.json"), options: .atomic)
            }
            try data.write(to: fileURL, options: .atomic)
            decks = updated
            return true
        } catch {
            self.error = "Changes could not be saved. \(error.localizedDescription)"
            return false
        }
    }
    nonisolated static func validate(_ decks: [Deck]) throws {
        let ids = decks.map(\.id) + decks.flatMap(\.cards).map(\.id)
        guard Set(ids).count == ids.count else { throw WorkspaceFailure.invalid("The library contains duplicate identifiers.") }
    }
}
