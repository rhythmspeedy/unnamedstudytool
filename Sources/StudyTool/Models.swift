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
    private struct Snapshot {
        let queue: [Card]
        let mastered: Int
    }

    private(set) var queue: [Card]
    private(set) var mastered = 0
    private var history: [Snapshot] = []
    let total: Int
    var current: Card? { queue.first }
    var complete: Bool { queue.isEmpty }
    var canGoBack: Bool { !history.isEmpty }

    init(cards: [Card], shuffled: Bool) {
        queue = shuffled ? cards.shuffled() : cards
        total = cards.count
    }

    mutating func answer(known: Bool) {
        guard !queue.isEmpty else { return }
        history.append(Snapshot(queue: queue, mastered: mastered))
        let card = queue.removeFirst()
        if known { mastered += 1 } else { queue.append(card) }
    }

    mutating func goBack() {
        guard let snapshot = history.popLast() else { return }
        queue = snapshot.queue
        mastered = snapshot.mastered
    }
}

@MainActor
final class Library: ObservableObject {
    @Published private(set) var decks: [Deck] = []
    @Published var error: String?
    private var loaded = false
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("unnamedstudytool", isDirectory: true)
            .appendingPathComponent("library.json")
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                decks = try JSONDecoder().decode([Deck].self, from: Data(contentsOf: self.fileURL))
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
}
