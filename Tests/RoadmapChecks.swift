import Foundation

enum RoadmapChecks {
    @MainActor static func run(in folder: URL) throws {
        func check(_ value: Bool, _ message: String) throws { try ModelChecks.check(value, message) }
        func rejected(_ message: String, _ action: () throws -> Void) throws {
            var didThrow = false
            do { try action() } catch { didThrow = true }
            try check(didThrow, message)
        }
        let suite = "RoadmapChecks-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("graphite", forKey: "theme")
        let legacy = "[{\"id\":\"\(UUID())\",\"title\":\"Existing task\",\"done\":false}]"
        let oldTasks = try JSONDecoder().decode([TodoItem].self, from: Data(legacy.utf8))
        try check(oldTasks[0].scheduledDay == nil && oldTasks[0].dueDay == nil, "Old tasks must decode without scheduling")
        let date = CalendarDay(Date())
        try check(try JSONDecoder().decode(CalendarDay.self, from: JSONEncoder().encode(date)) == date, "Date-only scheduling must round-trip")

        let deck = Deck(name: "Study", cards: (0..<8).map { Card(front: "Q\($0)", back: "A\($0)") })
        var session = StudySession(cards: deck.cards, shuffled: false, resumeAt: deck.cards[3].id)
        try check(session.current?.id == deck.cards[3].id && Set(session.queue.map(\.id)) == Set(deck.cards.map(\.id)), "Resume must retain every card")
        session.rate(.again)
        try check(session.queue[2].id == deck.cards[3].id && session.reviewed.count == 1, "Again should return soon")
        session.goBack()
        try check(session.current?.id == deck.cards[3].id && session.mastered == 0, "Back restores confidence queue")
        session.rate(.unsure)
        try check(session.queue[5].id == deck.cards[3].id && session.reviewed.count == 1, "Unsure returns later and repeats do not inflate reviews")
        var shuffled = StudySession(cards: deck.cards, shuffled: true, resumeAt: deck.cards[4].id)
        try check(shuffled.current?.id == deck.cards[4].id && shuffled.total == 8, "Shuffle resume keeps the saved card first")
        shuffled.answer(known: true)
        try check(shuffled.mastered == 1, "Free next must remain available without confidence")

        let workspaceURL = folder.appendingPathComponent("new-workspace.json")
        let store = WorkspaceStore(url: workspaceURL)
        let reference = StudyItemReference(kind: .deck, id: deck.id)
        store.pin(reference); store.pin(reference)
        try check(store.state.pins.isEmpty, "Pin toggles without duplicates")
        for _ in 0..<6 { store.pin(.init(kind: .note, id: UUID())) }
        try check(store.state.pins.count == 5 && store.error != nil, "Pin limit must be explicit")
        store.change { $0.pins = [PinnedItem(reference: reference)] }
        store.opened(reference); store.opened(reference)
        try check(store.state.recent.count == 1, "Recents must not duplicate")
        let event = StudyEvent(id: "focus-id", kind: .focusCompleted, occurredAt: Date(), value: 1500, reference: reference, labelSnapshot: "Study")
        store.record(event); store.record(event)
        try check(store.total(.focusMinutes) == 25 && store.total(.focusIntervals) == 1, "Focus events must be idempotent")
        store.change { $0.progress[deck.id] = DeckStudyProgress(lastCardID: deck.cards[2].id, reviewedCardIDs: [deck.cards[0].id]) }
        let note = StudyNote(title: "Unicode", body: "日本語 — 🪴\nA new line")
        let list = TodoList(name: "My list", items: [TodoItem(title: "Today", scheduledDay: date, dueDay: date)])
        let backup = WorkspaceBackup(decks: [deck], todoLists: [list], notes: [note], workspace: store.state, settings: ExportedSettings(defaults: defaults))
        let encoded = try backup.encoded()
        let decoded = try WorkspaceBackup.decode(encoded)
        try check(decoded.notes == [note] && decoded.workspace == store.state, "Full backup must round-trip every data category")
        try check(decoded.workspace.reviews == nil && oldTasks[0].materials == nil, "Existing workspaces need no new metadata")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let again = ReviewSchedule.next(.again, previous: nil, now: now)
        let know = ReviewSchedule.next(.know, previous: nil, now: now)
        try check(again.due == now.addingTimeInterval(600) && know.intervalDays == 3, "Review timing must distinguish Again and Know")
        try check(ReviewSchedule.next(.know, previous: know, now: now).intervalDays == 6, "Confident review intervals grow")
        try check(ReviewSchedule.next(.know, previous: ReviewSchedule(due: now, intervalDays: 30), now: now).intervalDays == 30, "Intervals stay bounded")
        let csv = try CardTextImport.parse("Prompt,Answer\r\n\"A, B\",\"Line 1\nLine 2\"\r\n\"Quote\",\"A \"\"word\"\"\"", separator: ",", skipHeader: true)
        try check(csv.count == 2 && csv[0].front == "A, B" && csv[0].back == "Line 1\nLine 2" && csv[1].back == "A \"word\"", "CSV preserves commas, multiline fields, and escaped quotes")
        try check(try CardTextImport.parse("日本語\t🌱\n", separator: "\t", skipHeader: false).first?.back == "🌱", "Pasted pairs preserve Unicode")
        try rejected("Reject extra CSV columns") { _ = try CardTextImport.parse("a,b,c", separator: ",", skipHeader: false) }
        try rejected("Reject unclosed CSV quotes") { _ = try CardTextImport.parse("\"a,b", separator: ",", skipHeader: false) }
        try rejected("Reject empty answers") { _ = try CardTextImport.parse("a,", separator: ",", skipHeader: false) }
        var linked = backup
        linked.todoLists[0].items[0].materials = [reference, .init(kind: .note, id: note.id)]
        linked.workspace.reviews = [deck.cards[0].id: know]
        linked.workspace.deletedFlashcards = [DeletedFlashcards(deck: Deck(name: "Recovered", cards: [Card(front: "Lost", back: "Found")]), wholeDeck: true)]
        let linkedRoundtrip = try WorkspaceBackup.decode(linked.encoded())
        try check(linkedRoundtrip.workspace == linked.workspace && linkedRoundtrip.todoLists == linked.todoLists, "Backups preserve review dates, recovery cards, and material links")
        let linkedMerge = try backup.merging(linked)
        try check(linkedMerge.todoLists[1].items[0].materials?.first?.id == linkedMerge.decks[1].id, "Merged task links point to imported decks")
        try check(linkedMerge.workspace.reviews?[linkedMerge.decks[1].cards[0].id] == know, "Merged reviews remap card IDs")
        try check(linkedMerge.workspace.deletedFlashcards?.first?.deck.id != linked.workspace.deletedFlashcards?.first?.deck.id, "Merged recovery cards have independent IDs")
        let guardedLibrary = Library(fileURL: folder.appendingPathComponent("guarded-library.json"))
        try check(guardedLibrary.save([deck]), "Set up deletion guard")
        guardedLibrary.beforeRemoving = { _, _ in false }
        try check(!guardedLibrary.save([]) && guardedLibrary.decks == [deck], "Failed recovery writes must prevent deletion")
        let dailyDir = folder.appendingPathComponent("daily-backups")
        let daily = try DailyBackups.save(backup, in: dailyDir, now: now)
        let firstSnapshot = try Data(contentsOf: daily)
        _ = try DailyBackups.save(linked, in: dailyDir, now: now)
        try check(try Data(contentsOf: daily) == firstSnapshot, "Later edits cannot overwrite today's safety snapshot")
        for offset in 1...15 { _ = try DailyBackups.save(backup, in: dailyDir, now: now.addingTimeInterval(Double(offset) * 86400)) }
        try check(try DailyBackups.files(in: dailyDir).count == 14, "Daily backups retain exactly 14 snapshots")
        var tampered = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        tampered["sha256"] = "bad-checksum"
        try rejected("Bad checksum must fail before import") { _ = try WorkspaceBackup.decode(JSONSerialization.data(withJSONObject: tampered)) }
        var future = backup; future.formatVersion = 100
        try rejected("Future versions must be rejected") { _ = try future.encoded() }
        var duplicate = backup; duplicate.notes.append(note)
        try rejected("Duplicate IDs must be rejected") { _ = try duplicate.encoded() }
        var badPin = backup; badPin.workspace.pins.append(PinnedItem(reference: .init(kind: .deck, id: UUID())))
        try rejected("Broken pin references must be rejected") { _ = try badPin.encoded() }
        let merged = try backup.merging(backup)
        try check(merged.decks.count == 2 && merged.notes.count == 2 && merged.todoLists.count == 2, "Merge adds independent copies")
        try check(merged.decks[0].id != merged.decks[1].id && merged.decks[0].cards[0].id != merged.decks[1].cards[0].id, "Merge remaps deck and card IDs")
        let newDeck = merged.decks[1]
        try check(merged.workspace.progress[newDeck.id]?.lastCardID == newDeck.cards[2].id, "Merge remaps progress references")
        try check(merged.workspace.pins.contains { $0.reference.id == newDeck.id }, "Merge remaps pins")

        let transactionDir = folder.appendingPathComponent("transaction")
        _ = try WorkspaceTransaction.install(backup, in: transactionDir, defaults: defaults)
        let oldFiles = try Dictionary(uniqueKeysWithValues: WorkspaceTransaction.fileNames.map { ($0, try Data(contentsOf: transactionDir.appendingPathComponent($0))) })
        try rejected("A partial install must fail and roll back") {
            _ = try WorkspaceTransaction.install(merged, in: transactionDir, defaults: defaults) { data, url in
                if url.lastPathComponent == "notes.json" { throw CocoaError(.fileWriteOutOfSpace) }
                try data.write(to: url, options: .atomic)
            }
        }
        for name in WorkspaceTransaction.fileNames {
            try check(try Data(contentsOf: transactionDir.appendingPathComponent(name)) == oldFiles[name], "Rollback must restore \(name)")
        }
        let journal = WorkspaceTransaction.Journal(originals: oldFiles, absent: [], settings: ExportedSettings(defaults: defaults))
        let recoveredBackup = try WorkspaceBackup.decodeRecoveryArchive(JSONEncoder().encode(journal))
        try check(recoveredBackup.decks == backup.decks && recoveredBackup.notes == backup.notes, "Pre-import archives restore original content")
        try JSONEncoder().encode(journal).write(to: transactionDir.appendingPathComponent("restore-journal.json"))
        try Data("interrupted import".utf8).write(to: transactionDir.appendingPathComponent("notes.json"))
        defaults.set("changed", forKey: "theme")
        try WorkspaceTransaction.recover(in: transactionDir, defaults: defaults)
        try check(try Data(contentsOf: transactionDir.appendingPathComponent("notes.json")) == oldFiles["notes.json"], "Startup recovery restores interrupted imports")
        try check(defaults.string(forKey: "theme") == "graphite", "Rollback restores curated settings")

        try FileManager.default.removeItem(at: workspaceURL)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: false)
        let another = StudyEvent(id: "unsaved", kind: .cardsReviewed, occurredAt: Date(), value: 3)
        store.record(another)
        try check(store.dirty && store.state.events.contains { $0.id == "unsaved" }, "Failed history writes must preserve in-memory events")
        try FileManager.default.removeItem(at: workspaceURL)
        try check(store.flush() && !store.dirty, "Retry must save retained history")
        try check(WorkspaceStore(url: workspaceURL).state.events.contains { $0.id == "unsaved" }, "Retried history survives reopening")

        let epoch = NotesStore(url: folder.appendingPathComponent("epoch-notes.json"), defaults: defaults)
        let oldEpoch = epoch.contentEpoch
        epoch.acceptRestored([note], data: try JSONEncoder().encode([note]))
        try check(epoch.contentEpoch != oldEpoch, "Restoring notes must invalidate old editor callbacks")
        var large = backup
        large.decks = (0..<100).map { Deck(name: "Deck \($0)", cards: (0..<100).map { Card(front: "Question \($0)", back: "Answer") }) }
        large.notes = (0..<500).map { StudyNote(title: "Note \($0)", body: String(repeating: "Long writing.\n", count: $0 < 5 ? 10000 : 20)) }
        large.todoLists = (0..<20).map { TodoList(name: "List \($0)", items: (0..<100).map { TodoItem(title: "Task \($0)") }) }
        large.workspace = WorkspaceState()
        let start = Date()
        let largeDecoded = try WorkspaceBackup.decode(large.encoded())
        try check(largeDecoded.decks.flatMap(\.cards).count == 10000 && largeDecoded.notes.count == 500, "Large workspace import preserves all content")
        print("Large-workspace backup round-trip: \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
    }
}
