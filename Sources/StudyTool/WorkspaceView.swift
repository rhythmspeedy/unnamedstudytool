import SwiftUI

enum StudyPage: String, CaseIterable {
    case home = "Home", flashcards = "Flashcards", todos = "To-do", notes = "Notes", pomodoro = "Pomodoro"
    var icon: String {
        switch self { case .home: "square.grid.2x2"; case .flashcards: "rectangle.stack"; case .todos: "checklist"; case .notes: "note.text"; case .pomodoro: "timer" }
    }
}

struct WorkspaceView: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var router: StudyRouter
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var pomodoro: PomodoroStore
    @EnvironmentObject private var todos: TodoStore
    @EnvironmentObject private var notes: NotesStore
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    private var page: StudyPage { router.page }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Text("unnamed").font(.system(size: 19, weight: .semibold, design: .rounded))
                BubbleNavigation(page: page, select: { navigate($0) }).frame(maxWidth: 480)
                Spacer()
                if page != .home {
                    Button { hub.run(.focusMode) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Focus mode (⌘⇧F)").accessibilityLabel("Enter focus mode")
                }
                SettingsLink { Label("Settings", systemImage: "gearshape") }.help("Settings (⌘,)")
            }.padding(.horizontal, 24).padding(.vertical, 14).background(theme.surface).zIndex(1)
                .frame(height: router.focused ? 0 : nil).clipped().accessibilityHidden(router.focused).disabled(router.focused)
            Divider()
            if router.focused {
                HStack { Text("FOCUS").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Exit focus · Esc") { router.focused = false }.keyboardShortcut(.cancelAction) }.padding(.horizontal, 24).padding(.vertical, 8)
            }
            Group {
                switch page {
                case .home: ScrollView { home.frame(maxWidth: .infinity) }
                case .flashcards: ContentView()
                case .todos: TodoView()
                case .notes: NotesView()
                case .pomodoro: PomodoroView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(StudyReveal(duration: 0.1, distance: 0))
            .id("\(page.rawValue)-\(router.generation)")
            .clipped()
            if pomodoro.clock.running || pomodoro.clock.awaitingNext || pomodoro.clock.remaining < pomodoro.clock.duration {
                Divider()
                HStack {
                    Button { navigate(.pomodoro) } label: { Label("\(pomodoro.clock.phase.rawValue) · \(pomodoro.time)", systemImage: "timer").monospacedDigit() }.buttonStyle(.plain)
                    if let intention = workspace.state.intention {
                        Text(intention.labelSnapshot).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if pomodoro.clock.awaitingNext {
                        Text(pomodoro.notice ?? "Interval complete").font(.caption).foregroundStyle(.secondary)
                        Button("Start next interval") { pomodoro.next() }
                    } else { Button(pomodoro.clock.running ? "Pause" : "Resume") { pomodoro.toggle() } }
                }.padding(.horizontal, 24).padding(.vertical, 12).background(theme.surface)
            }
        }.background(theme.background)
            .disabled(hub.startupBlocked)
            .onExitCommand { if router.focused { router.focused = false } }
            .sheet(item: $router.capture) { request in QuickCaptureView(kind: request.kind, bodyText: request.answer) }
            .sheet(isPresented: $router.palette) { CommandPaletteView() }
            .onChange(of: router.settingsRequested) { _, requested in if requested { router.settingsRequested = false; openSettings() } }
            .overlay(alignment: .bottom) {
                if let notice = hub.notice {
                    Text(notice).font(.caption).padding(12).background(theme.surface, in: Capsule()).padding(16)
                        .task(id: notice) { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { hub.notice = nil } }
                }
            }
            .alert("Workspace needs attention", isPresented: Binding(get: { hub.error != nil || workspace.error != nil }, set: { if !$0 { hub.error = nil; workspace.error = nil } })) {
                if workspace.dirty { Button("Retry saving") { workspace.flush() } }
                Button("OK") { hub.error = nil; workspace.error = nil }
            } message: { Text(hub.error ?? workspace.error ?? "") }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 28) {
            TodayView()
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
        }.buttonStyle(HomeToolButtonStyle())
    }

    private func navigate(_ destination: StudyPage) {
        guard destination != page else { return }
        hub.navigate(destination)
    }
}

struct PomodoroView: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var timer: PomodoroStore
    @EnvironmentObject private var audio: AmbientAudioController
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    @AppStorage("ambientSound") private var ambientSound: AmbientSound = .silence
    @State private var confirmReset = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                HStack(alignment: .top, spacing: 32) {
                    timerPanel.frame(maxWidth: 610)
                    if geometry.size.width >= 900 {
                        focusContext.frame(width: 286)
                    }
                }
                .padding(geometry.size.width >= 900 ? 38 : 30)
                .frame(maxWidth: 1040)
                .frame(maxWidth: .infinity)
            }
        }
        .alert("Reset this interval?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { timer.reset() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This restarts the current interval’s countdown. Completed focus intervals are kept.") }
    }

    private var timerPanel: some View {
        VStack(spacing: 24) {
            Text("POMODORO").font(.system(size: 11, design: .monospaced)).tracking(3).foregroundStyle(.secondary)
            IntentionPicker()
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
            DisclosureGroup("Focus sounds") { AmbientPicker().padding(.top, 12) }.frame(maxWidth: 500)
        }
        .frame(maxWidth: .infinity)
    }

    private var focusContext: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SESSION").font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
            HStack(spacing: 9) {
                ForEach(0..<4, id: \.self) { index in
                    Circle().fill(index < cycleProgress ? theme.accent : theme.ink.opacity(0.12)).frame(width: 9, height: 9)
                }
                Spacer()
                Text("\(cycleProgress) of 4").font(.caption).foregroundStyle(.secondary)
            }
            if let intention = workspace.state.intention {
                Divider()
                Text("CURRENT INTENTION").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                Text(intention.labelSnapshot).font(.callout.weight(.medium)).lineLimit(3)
                if hub.resolve(intention.reference) != nil {
                    Button("Open material") { hub.run(.open(intention.reference)) }.font(.caption)
                }
            }
            Divider()
            if timer.clock.phase == .focus {
                Text("UP NEXT").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                if upcomingTasks.isEmpty {
                    Text("No open tasks. A clear desk is a good place to focus.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(upcomingTasks.prefix(3).enumerated()), id: \.element.1.id) { _, entry in
                        Button { hub.run(.open(.init(kind: .todoItem, id: entry.1.id, parentID: entry.0.id))) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "circle").font(.caption2)
                                Text(entry.1.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain).font(.caption)
                    }
                }
            } else {
                Text("TAKE A REAL BREAK").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                Label("Look away from the screen", systemImage: "eye").font(.caption)
                Label("Stand, stretch, or get water", systemImage: "figure.cooldown").font(.caption)
                Text("Nothing to complete here—just reset.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("SOUND").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
            HStack {
                Label(ambientSound.title, systemImage: ambientSound.icon).font(.caption).lineLimit(1)
                Spacer()
                if ambientSound != .silence {
                    Button(audio.playing || audio.preparing ? "Stop" : "Play") {
                        if audio.playing || audio.preparing { audio.stop() } else { audio.play() }
                    }.font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.ink.opacity(0.07)))
    }

    private var cycleProgress: Int {
        let progress = timer.clock.completed % 4
        return progress == 0 && timer.clock.completed > 0 && (timer.clock.awaitingNext || timer.clock.phase == .longBreak) ? 4 : progress
    }

    private var upcomingTasks: [(TodoList, TodoItem)] {
        hub.todos.lists.flatMap { list in list.items.filter { !$0.done }.map { (list, $0) } }
            .sorted { left, right in
                let leftDay = left.1.dueDay ?? left.1.scheduledDay
                let rightDay = right.1.dueDay ?? right.1.scheduledDay
                switch (leftDay, rightDay) {
                case let (a?, b?): return a == b ? left.1.title < right.1.title : a < b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return false
                }
            }
    }
}

struct IntentionPicker: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var timer: PomodoroStore
    @State private var search = ""
    @State private var choosing = false
    var body: some View {
        Button { choosing = true } label: { Label(workspace.state.intention?.labelSnapshot ?? "Choose an intention (optional)", systemImage: "scope").lineLimit(1) }
            .disabled(timer.clock.running || timer.clock.awaitingNext || timer.clock.remaining != timer.clock.duration)
            .popover(isPresented: $choosing) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Find a task, deck, or note", text: $search).textFieldStyle(.roundedBorder)
                    Button("No intention") { workspace.change { $0.intention = nil }; choosing = false }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(hub.destinations.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { item in
                                Button { workspace.change { $0.intention = FocusIntention(reference: item.reference, labelSnapshot: item.title) }; choosing = false } label: { Label(item.title, systemImage: item.icon).lineLimit(1) }.buttonStyle(.plain)
                            }
                        }
                    }.frame(height: 230)
                }.padding(18).frame(width: 340).modifier(AppAppearance())
            }
    }
}
