import Foundation

struct ReviewSchedule: Codable, Equatable {
    var due: Date
    var intervalDays: Int
    static func next(_ confidence: StudySession.Confidence, previous: Self?, now: Date = Date()) -> Self {
        switch confidence {
        case .again: return Self(due: now.addingTimeInterval(600), intervalDays: 0)
        case .unsure: return Self(due: now.addingTimeInterval(86400), intervalDays: 1)
        case .know:
            let days = min(30, max(3, (previous?.intervalDays ?? 0) * 2))
            return Self(due: now.addingTimeInterval(Double(days) * 86400), intervalDays: days)
        }
    }
}

struct DeletedFlashcards: Codable, Equatable, Identifiable {
    var id = UUID()
    var deletedAt = Date()
    var deck: Deck
    var wholeDeck: Bool
    var expiresAt: Date { deletedAt.addingTimeInterval(30 * 86400) }
}

enum CardTextImport {
    /// RFC-style quoted CSV (including multiline fields), or tab-separated pairs.
    static func parse(_ text: String, separator: Character, skipHeader: Bool) throws -> [Card] {
        guard text.utf8.count <= 10_000_000 else { throw WorkspaceFailure.invalid("Import up to 10 MB at a time.") }
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closedQuote = false, index = 0
        while index < characters.count {
            let c = characters[index]
            if quoted {
                if c == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" { field.append(c); index += 1 }
                    else { quoted = false; closedQuote = true }
                } else { field.append(c) }
            } else if c == separator || c == "\n" {
                row.append(field); field = ""; closedQuote = false
                if c == "\n" { rows.append(row); row = [] }
            } else if c == "\"", field.isEmpty, !closedQuote { quoted = true }
            else {
                guard !closedQuote && c != "\"" else { throw WorkspaceFailure.invalid("Unexpected text after a quote near row \(rows.count + 1).") }
                field.append(c)
            }
            index += 1
        }
        guard !quoted else { throw WorkspaceFailure.invalid("A quoted field is missing its closing quote.") }
        if !field.isEmpty || !row.isEmpty || closedQuote { row.append(field); rows.append(row) }
        rows.removeAll { $0.count == 1 && $0[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if skipHeader, !rows.isEmpty { rows.removeFirst() }
        guard !rows.isEmpty, rows.count <= 10000 else { throw WorkspaceFailure.invalid("Include between 1 and 10,000 question-and-answer pairs.") }
        return try rows.enumerated().map { index, row in
            guard row.count == 2 else { throw WorkspaceFailure.invalid("Row \(index + 1) needs exactly two columns: prompt and answer.") }
            let values = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard values.allSatisfy({ !$0.isEmpty }) else { throw WorkspaceFailure.invalid("Row \(index + 1) has an empty prompt or answer.") }
            return Card(front: values[0], back: values[1])
        }
    }
}

enum DailyBackups {
    static func files(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]).filter {
            let attributes = try $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return attributes.isRegularFile == true && attributes.isSymbolicLink != true && $0.lastPathComponent.range(of: "^daily-[0-9]{4}-[0-9]{2}-[0-9]{2}\\.json$", options: .regularExpression) != nil
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    static func save(_ backup: WorkspaceBackup, in directory: URL, now: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let url = directory.appendingPathComponent("daily-\(formatter.string(from: now)).json")
        // Keep the first snapshot each day: later mistakes cannot overwrite it.
        if !FileManager.default.fileExists(atPath: url.path) {
            try backup.encoded().write(to: url, options: .atomic)
        } else { _ = try WorkspaceBackup.decode(Data(contentsOf: url)) }
        for old in try files(in: directory).dropFirst(14) { try FileManager.default.removeItem(at: old) }
        return url
    }
}
