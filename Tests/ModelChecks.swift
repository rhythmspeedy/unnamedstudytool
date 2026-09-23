import Foundation

enum CheckFailure: Error { case failed(String) }

@main struct ModelChecks {
    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure.failed(message) }
    }

    @MainActor static func main() async throws {
        let a = Card(front: "A", back: "1")
        let b = Card(front: "B", back: "2")
        var session = StudySession(cards: [a, b], shuffled: false)
        session.answer(known: false)
        try check(session.current == b && session.mastered == 0, "Practice should move the card to the end")
        session.answer(known: true)
        try check(session.current == a, "The practice card should return")
        session.goBack()
        try check(session.current == b && session.mastered == 0, "Back should restore the previous card and progress")
        session.answer(known: true)
        try check(session.current == a, "The restored card should advance normally")
        session.answer(known: true)
        try check(session.complete && session.mastered == 2, "Learning every card should complete the session")
        session.answer(known: true)
        try check(session.mastered == 2, "Completed sessions must not overcount")
        let cards = (0..<20).map { Card(front: "\($0)", back: "answer") }
        let shuffled = StudySession(cards: cards, shuffled: true)
        try check(Set(shuffled.queue.map(\.id)) == Set(cards.map(\.id)) && shuffled.total == 20, "Shuffle must preserve all cards")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("library.json")
        let deck = Deck(name: "Test", cards: [a, b])
        let library = Library(fileURL: url)
        try check(library.save([deck]), "First save should succeed")
        try check(Library(fileURL: url).decks == [deck], "Data should survive reopening")
        let invalid = Data("invalid json".utf8)
        try invalid.write(to: url)
        let broken = Library(fileURL: url)
        try check(broken.error != nil && !broken.save([]), "Unreadable data must block overwriting")
        try check(try Data(contentsOf: url) == invalid, "Unreadable data must remain intact")
        let blocked = Library(fileURL: folder.appendingPathComponent("missing/library.json"))
        try Data().write(to: folder.appendingPathComponent("missing"))
        try check(!blocked.save([deck]) && blocked.error != nil && blocked.decks.isEmpty, "Failed saves must surface errors and preserve in-memory state")
        let todoURL = folder.appendingPathComponent("todos.json")
        let todos = TodoStore(url: todoURL)
        try check(todos.lists.count == 1, "To-do must begin with one default list")
        var todoList = todos.lists[0]
        todoList.items = [TodoItem(title: "Read chapter")]
        try check(todos.update(todoList), "Task creation must save")
        todoList.items[0].done = true
        try check(todos.update(todoList), "Task completion must save")
        try check(TodoStore(url: todoURL).lists == [todoList], "Tasks and completion must survive reopening")
        let extra = TodoList(name: "Exam")
        try check(todos.save([todoList, extra]), "Additional lists must save")
        try check(TodoStore(url: todoURL).lists.count == 2, "Multiple lists must survive reopening")
        try invalid.write(to: todoURL)
        let brokenTodos = TodoStore(url: todoURL)
        try check(!brokenTodos.save([]) && brokenTodos.error != nil, "Unreadable to-do data must not be overwritten")

        let notesURL = folder.appendingPathComponent("notes.json")
        let defaults = UserDefaults(suiteName: "NotesChecks-\(UUID().uuidString)")!
        let notes = NotesStore(url: notesURL, defaults: defaults)
        let first = notes.create()!
        notes.edit(id: first, title: "Biology", body: "Cellular respiration\n日本語 🪴")
        try check(notes.dirty, "Typing must mark notes unsaved")
        try await Task.sleep(for: .milliseconds(850))
        try check(!notes.dirty && notes.status == "Saved", "Typing pause must autosave")
        try check(NotesStore(url: notesURL, defaults: defaults).selected?.body == "Cellular respiration\n日本語 🪴", "Unicode and selection must survive reopening")
        notes.search = "RESPIRATION"
        try check(notes.matchingNotes.count == 1, "Search must include note contents")
        let page = notes.addPage(to: first)!
        notes.editPage(noteID: first, pageID: page, title: "Cell division", body: "Mitosis and meiosis")
        try check(notes.flush(), "Additional note pages must save")
        let pagedNote = NotesStore(url: notesURL, defaults: defaults).selected!
        try check(pagedNote.pages.first?.title == "Cell division" && pagedNote.pages.first?.body == "Mitosis and meiosis", "Additional note pages must survive reopening")
        notes.search = "MEIOSIS"
        try check(notes.matchingNotes.map(\.id) == [first], "Search must include additional page titles and contents")
        try check(pagedNote.exportText.contains("Cell division") && pagedNote.exportText.contains("Mitosis and meiosis"), "Text export must include every page")
        let second = notes.create()!
        notes.edit(id: second, title: "Long note", body: String(repeating: "A long line of notes.\n", count: 10000))
        try check(notes.select(first), "Switching notes must flush pending edits")
        try check(NotesStore(url: notesURL, defaults: defaults).notes.first(where: { $0.id == second })?.body == String(repeating: "A long line of notes.\n", count: 10000), "Long notes must save completely")
        notes.deleteSelected()
        try check(notes.notes.count == 1, "Delete must remove selected note")
        notes.undoDelete()
        try check(notes.selectedID == first && notes.notes.count == 2, "Undo delete must restore content and selection")
        let previous = try Data(contentsOf: notes.recoveryURL)
        try invalid.write(to: notesURL)
        let corruptNotes = NotesStore(url: notesURL, defaults: defaults)
        try check(!corruptNotes.loaded && corruptNotes.create() == nil, "Corrupt notes must not be overwritten")
        corruptNotes.restorePreviousSave()
        try check(corruptNotes.loaded && (try Data(contentsOf: notesURL)) == previous, "Recovery must restore previous save")
        let blockedNotesURL = folder.appendingPathComponent("blocked-notes/notes.json")
        let blockedNotes = NotesStore(url: blockedNotesURL, defaults: defaults)
        let draft = blockedNotes.create()!
        try FileManager.default.removeItem(at: blockedNotesURL)
        try FileManager.default.createDirectory(at: blockedNotesURL, withIntermediateDirectories: false)
        blockedNotes.edit(id: draft, body: "Do not lose this draft")
        try check(!blockedNotes.flush() && blockedNotes.dirty && blockedNotes.error != nil, "Save failures must be visible")
        try check(blockedNotes.selected?.body == "Do not lose this draft" && !blockedNotes.select(first), "Save failures must preserve text and block switching")

        let start = Date(timeIntervalSince1970: 1000)
        var clock = PomodoroClock()
        clock.start(now: start)
        clock.tick(now: start.addingTimeInterval(120))
        try check(clock.remaining == 1380, "Timer must use elapsed time, not tick counts")
        clock.pause(now: start.addingTimeInterval(180))
        clock.tick(now: start.addingTimeInterval(900))
        try check(clock.remaining == 1320 && !clock.running, "Paused timer must not advance")
        clock.start(now: start.addingTimeInterval(1000))
        try check(clock.tick(now: start.addingTimeInterval(3000)), "Timer must complete after a long background gap")
        try check(clock.completed == 1 && clock.awaitingNext, "Completion must count exactly one focus interval")
        clock.tick(now: start.addingTimeInterval(4000))
        try check(clock.completed == 1, "Repeated ticks must not count twice")
        for round in 1...4 {
            if round > 1 {
                clock.start(now: start)
                clock.tick(now: start.addingTimeInterval(8000))
            }
            clock.nextPhase(focus: 25, short: 5, long: 15)
            try check(clock.phase == (round == 4 ? .longBreak : .shortBreak), "Fourth focus interval must lead to a long break")
            try check(!clock.running, "Break must wait for explicit start")
            clock.start(now: start)
            clock.tick(now: start.addingTimeInterval(8000))
            clock.nextPhase(focus: 25, short: 5, long: 15)
        }
        try RoadmapChecks.run(in: folder)
        print("PASS: notes, flashcards, tasks, Pomodoro, workspace backup/merge/rollback, history, targets, pins, scheduling, confidence and resume")
    }
}
