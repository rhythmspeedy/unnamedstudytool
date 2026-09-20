import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var done = false
}

struct TodoList: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var items: [TodoItem] = []
}

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var lists: [TodoList] = []
    @Published var error: String?
    private let url: URL
    private var loaded = false

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("unnamedstudytool/todos.json")
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                lists = try JSONDecoder().decode([TodoList].self, from: Data(contentsOf: self.url))
            }
            if lists.isEmpty { lists = [TodoList(name: "My list")] }
            loaded = true
        } catch { self.error = "Could not open to-do lists. The saved file is preserved. \(error.localizedDescription)" }
    }

    @discardableResult func save(_ updated: [TodoList]) -> Bool {
        guard loaded else { error = "Saving is disabled until your to-do file can be read. Reopen the app after restoring todos.json."; return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: url, options: .atomic)
            lists = updated
            return true
        } catch { self.error = "Could not save to-do changes. \(error.localizedDescription)"; return false }
    }

    @discardableResult func update(_ list: TodoList) -> Bool {
        save(lists.map { $0.id == list.id ? list : $0 })
    }
}

struct PomodoroClock {
    enum Phase: String { case focus = "Focus", shortBreak = "Short break", longBreak = "Long break" }
    private(set) var phase: Phase = .focus
    private(set) var completed = 0
    private(set) var remaining: TimeInterval = 25 * 60
    private(set) var duration: TimeInterval = 25 * 60
    private(set) var deadline: Date?
    private(set) var awaitingNext = false
    var running: Bool { deadline != nil }

    mutating func start(now: Date) {
        guard !running, !awaitingNext else { return }
        deadline = now.addingTimeInterval(remaining)
    }
    mutating func pause(now: Date) {
        tick(now: now)
        deadline = nil
    }
    @discardableResult mutating func tick(now: Date) -> Bool {
        guard let deadline else { return false }
        remaining = max(0, deadline.timeIntervalSince(now))
        guard remaining == 0 else { return false }
        self.deadline = nil
        awaitingNext = true
        if phase == .focus { completed += 1 }
        return true
    }
    mutating func reset(minutes: Int) {
        deadline = nil
        awaitingNext = false
        remaining = TimeInterval(minutes * 60)
        duration = remaining
    }
    mutating func nextPhase(focus: Int, short: Int, long: Int) {
        guard awaitingNext else { return }
        if phase == .focus { phase = completed % 4 == 0 ? .longBreak : .shortBreak }
        else { phase = .focus }
        reset(minutes: phase == .focus ? focus : phase == .shortBreak ? short : long)
    }
}

@MainActor
final class PomodoroStore: ObservableObject {
    @Published private(set) var clock = PomodoroClock()
    @Published var notice: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        clock.reset(minutes: minutes(.focus))
    }
    func minutes(_ phase: PomodoroClock.Phase) -> Int {
        let key = phase == .focus ? "pomodoroFocus" : phase == .shortBreak ? "pomodoroShort" : "pomodoroLong"
        let fallback = phase == .focus ? 25 : phase == .shortBreak ? 5 : 15
        return min(max(defaults.object(forKey: key) as? Int ?? fallback, 1), 120)
    }
    var time: String {
        let seconds = Int(ceil(clock.remaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    func toggle() {
        if clock.running { clock.pause(now: Date()) }
        else { clock.start(now: Date()) }
    }
    func tick() {
        // A deadline stays accurate across navigation, backgrounding, and sleep.
        guard clock.running else { return }
        if clock.tick(now: Date()) { notice = "\(clock.phase.rawValue) complete. Ready for \(clock.phase == .focus ? "a break" : "another focus session")?" }
    }
    func reset() { clock.reset(minutes: minutes(clock.phase)); notice = nil }
    func next() {
        clock.nextPhase(focus: minutes(.focus), short: minutes(.shortBreak), long: minutes(.longBreak))
        notice = nil
        clock.start(now: Date())
    }
}
