import SwiftUI

enum StudyPage: String, CaseIterable {
    case home = "Home", flashcards = "Flashcards", todos = "To-do", notes = "Notes", pomodoro = "Pomodoro"
    var icon: String {
        switch self { case .home: "square.grid.2x2"; case .flashcards: "rectangle.stack"; case .todos: "checklist"; case .notes: "note.text"; case .pomodoro: "timer" }
    }
}

struct WorkspaceView: View {
    @EnvironmentObject private var pomodoro: PomodoroStore
    @EnvironmentObject private var todos: TodoStore
    @EnvironmentObject private var notes: NotesStore
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    @State private var page: StudyPage = .home
    private let ticks = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Text("unnamed").font(.system(size: 19, weight: .semibold, design: .rounded))
                Picker("Study tool", selection: Binding(get: { page }, set: { navigate($0) })) {
                    ForEach(StudyPage.allCases, id: \.self) { target in
                        Text(target.rawValue).tag(target)
                    }
                }.pickerStyle(.segmented).labelsHidden().controlSize(.large).frame(maxWidth: 480)
                Spacer()
                SettingsLink { Label("Settings", systemImage: "gearshape") }.help("Settings (⌘,)")
            }.padding(.horizontal, 24).padding(.vertical, 14).background(theme.surface).zIndex(1)
            Divider()
            Group {
                switch page {
                case .home: ScrollView { home.frame(maxWidth: .infinity) }
                case .flashcards: ContentView()
                case .todos: TodoView()
                case .notes: NotesView()
                case .pomodoro: PomodoroView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            if pomodoro.clock.running || pomodoro.clock.awaitingNext || pomodoro.clock.remaining < pomodoro.clock.duration {
                Divider()
                HStack {
                    Button { navigate(.pomodoro) } label: { Label("\(pomodoro.clock.phase.rawValue) · \(pomodoro.time)", systemImage: "timer").monospacedDigit() }.buttonStyle(.plain)
                    Spacer()
                    if pomodoro.clock.awaitingNext {
                        Text(pomodoro.notice ?? "Interval complete").font(.caption).foregroundStyle(.secondary)
                        Button("Start next interval") { pomodoro.next() }
                    } else { Button(pomodoro.clock.running ? "Pause" : "Resume") { pomodoro.toggle() } }
                }.padding(.horizontal, 24).padding(.vertical, 12).background(theme.surface)
            }
        }.background(theme.background)
            .onReceive(ticks) { _ in pomodoro.tick() }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("YOUR STUDY SPACE").font(.system(size: 11, design: .monospaced)).tracking(3).foregroundStyle(.secondary)
            Text("What would you like to work on?").font(.system(size: 34, weight: .medium, design: .serif))
            Text("Pick a tool. Your focus timer stays with you as you move.").foregroundStyle(.secondary)
            VStack(spacing: 12) {
                homeLink(.todos, detail: "Write tasks, check them off, and see what’s left.", trailing: "\(todos.lists.flatMap(\.items).filter { !$0.done }.count) open")
                homeLink(.pomodoro, detail: "Start a focus interval and make time for breaks.", trailing: pomodoro.clock.running ? pomodoro.time : "Open timer")
                homeLink(.flashcards, detail: "Work through your decks at your own pace.", trailing: "Open decks")
                homeLink(.notes, detail: "Write down ideas and keep what you’re learning.", trailing: "\(notes.notes.count) notes")
            }
            SettingsLink { Label("Personalize your study space", systemImage: "gearshape") }.controlSize(.large)
        }.padding(36).frame(maxWidth: 900, alignment: .topLeading)
    }
    private func homeLink(_ destination: StudyPage, detail: String, trailing: String) -> some View {
        Button { navigate(destination) } label: {
            HStack(spacing: 20) {
                Image(systemName: destination.icon).font(.system(size: 26, weight: .light)).frame(width: 38)
                VStack(alignment: .leading, spacing: 8) {
                    Text(destination.rawValue).font(.title2.weight(.medium))
                    Text(detail).font(.body).foregroundStyle(.secondary)
                }
                Spacer()
                Text(trailing).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
            }.padding(24).background(theme.surface, in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func navigate(_ destination: StudyPage) {
        guard page != .notes || notes.flush() || !notes.loaded else { return }
        page = destination
    }
}

struct PomodoroView: View {
    @EnvironmentObject private var timer: PomodoroStore
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    @State private var confirmReset = false
    var body: some View {
        ScrollView {
        VStack(spacing: 24) {
            Text("POMODORO").font(.system(size: 11, design: .monospaced)).tracking(3).foregroundStyle(.secondary)
            Text(timer.clock.phase.rawValue).font(.system(size: 34, design: .serif))
            Text(timer.time).font(.system(size: 88, weight: .light, design: .rounded)).monospacedDigit()
            ProgressView(value: timer.clock.duration - timer.clock.remaining, total: max(timer.clock.duration, 1)).tint(theme.accent).frame(maxWidth: 360)
            Text(timer.notice ?? "One thing at a time. Your timer follows you through the app.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 14) {
                if timer.clock.awaitingNext { Button("Start next interval") { timer.next() }.buttonStyle(PrimaryButtonStyle()) }
                else { Button(timer.clock.running ? "Pause" : timer.clock.remaining < timer.clock.duration ? "Resume" : "Start") { timer.toggle() }.buttonStyle(PrimaryButtonStyle()) }
                Button("Reset interval") { confirmReset = true }.controlSize(.large)
            }
            Text("\(timer.clock.completed) focus intervals completed this run").font(.caption).foregroundStyle(.secondary)
            Text("\(timer.minutes(.focus)) min focus · \(timer.minutes(.shortBreak)) min break · longer break after 4 focus intervals\nStart each interval when you’re ready. Customize durations in Settings.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            SettingsLink { Label("Timer settings", systemImage: "gearshape") }
        }.padding(40).frame(maxWidth: .infinity)
        }
            .alert("Reset this interval?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { timer.reset() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This restarts the current interval’s countdown. Completed focus intervals are kept.") }
    }
}
