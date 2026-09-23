import SwiftUI

struct TodoView: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var router: StudyRouter
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var timer: PomodoroStore
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    private var selected: UUID? { get { router.listID } nonmutating set { router.listID = newValue } }
    @State private var draft = ""
    @State private var showCompleted = false
    @State private var naming = false
    @State private var rename = false
    @State private var name = ""
    @State private var editing: TodoItem?
    @State private var editTitle = ""
    @State private var scheduling: TodoItem?
    @State private var linking: TodoItem?
    @State private var dueEnabled = false
    @State private var dueDate = Date()
    @State private var deleteList = false
    @State private var deleted: (listID: UUID, item: TodoItem, index: Int)?
    @State private var inspectedTaskID: UUID?
    @FocusState private var inputFocused: Bool
    private var list: TodoList? { store.lists.first { $0.id == selected } ?? store.lists.first }
    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private struct TaskSection: Identifiable {
        let title: String
        let items: [TodoItem]
        var id: String { title }
    }

    var body: some View {
        GeometryReader { geometry in
        HStack(alignment: .top, spacing: 22) {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TO-DO").font(.system(size: 11, design: .monospaced)).tracking(3).foregroundStyle(.secondary)
                    Text(list?.name ?? "Your list").font(.system(size: 36, design: .serif))
                }
                Spacer()
                Menu {
                    if let list { ItemActions(reference: .init(kind: .todoList, id: list.id)) }
                    Divider()
                    if store.lists.count > 1 {
                        ForEach(store.lists) { list in Button(list.name) { selected = list.id } }
                        Divider()
                    }
                    Button("New list…") { rename = false; name = ""; naming = true }
                    Button("Rename list…") { rename = true; name = list?.name ?? ""; naming = true }
                    if store.lists.count > 1 { Button("Delete list…", role: .destructive) { deleteList = true } }
                } label: { Label("Lists", systemImage: "ellipsis.circle") }.fixedSize()
            }
            HStack {
                TextField("Add something to do, then press Return", text: $draft).textFieldStyle(.plain).focused($inputFocused).onSubmit(add)
                Button(action: add) { Image(systemName: "plus") }.disabled(trimmedDraft.isEmpty).help("Add task")
            }.padding(16).background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("\(list?.items.filter { !$0.done }.count ?? 0) remaining").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Show completed", isOn: $showCompleted).toggleStyle(.checkbox).font(.caption)
            }
            if let list {
                ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(taskSections(for: list)) { section in
                            Text(section.title.uppercased()).font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, section.id == taskSections(for: list).first?.id ? 0 : 10)
                            ForEach(section.items) { item in taskRow(item, in: list) }
                        }
                    }
                    if list.items.filter({ showCompleted || !$0.done }).isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: list.items.isEmpty ? "checklist" : "checkmark.circle").font(.system(size: 36, weight: .light))
                            Text(list.items.isEmpty ? "What’s on your mind?" : "All clear.").font(.title2)
                            Text(list.items.isEmpty ? "Add a task above. Keep it small enough to start." : "Your completed tasks are still here when you need them.").foregroundStyle(.secondary)
                        }.padding(40).frame(maxWidth: .infinity)
                    }
                }
                .onChange(of: router.taskID, initial: true) { _, id in
                    if let id { inspectedTaskID = id; showCompleted = true; scroll.scrollTo(id, anchor: .center) }
                }
                }
            }
            if deleted != nil {
                HStack {
                    Text("Task deleted").font(.caption).foregroundStyle(.secondary)
                    Button("Undo") { undoDelete() }
                    Spacer()
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if geometry.size.width >= 1040 {
                todoInspector.frame(width: 286)
            }
        }
        .padding(geometry.size.width >= 1040 ? 32 : 28)
        .frame(maxWidth: 1320, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        }
            .onAppear { if selected == nil { selected = store.lists.first?.id }; inputFocused = router.taskID == nil }
            .onChange(of: selected) { _, id in if let id { workspace.opened(.init(kind: .todoList, id: id)) } }
            .sheet(item: $scheduling) { item in
                VStack(alignment: .leading, spacing: 18) {
                    Text("Due date").font(.title2)
                    Toggle("Set a due date", isOn: $dueEnabled)
                    DatePicker("Date", selection: $dueDate, displayedComponents: .date).disabled(!dueEnabled)
                    HStack {
                        Button("Cancel") { scheduling = nil }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Save") {
                            guard var list, let index = list.items.firstIndex(where: { $0.id == item.id }) else { store.error = "This task is no longer available."; return }
                            list.items[index].dueDay = dueEnabled ? CalendarDay(dueDate) : nil
                            if store.update(list) { scheduling = nil }
                        }.keyboardShortcut(.defaultAction)
                    }
                }.padding(26).frame(width: 360)
            }
            .sheet(item: $linking) { item in
                if let list { MaterialLinksView(taskID: item.id, listID: list.id) }
            }
            .sheet(isPresented: $naming) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(rename ? "Rename list" : "New list").font(.title2)
                    TextField("List name", text: $name).textFieldStyle(.roundedBorder).onSubmit(saveName)
                    HStack { Button("Cancel") { naming = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Save", action: saveName).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.padding(28).frame(width: 380)
            }
            .sheet(item: $editing) { _ in
                VStack(alignment: .leading, spacing: 18) {
                    Text("Edit task").font(.title2)
                    TextField("Task", text: $editTitle, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                    HStack { Button("Cancel") { editing = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("Save", action: saveEdit).keyboardShortcut(.defaultAction).disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.padding(28).frame(width: 440)
            }
            .alert("Delete this list and its tasks?", isPresented: $deleteList) {
                Button("Delete", role: .destructive) {
                    if let list, store.save(store.lists.filter { $0.id != list.id }) { selected = store.lists.first?.id; deleted = nil }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("To-do needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
    }

    private func taskSections(for list: TodoList) -> [TaskSection] {
        let today = CalendarDay()
        let active = list.items.filter { !$0.done }
        let todayItems = active.filter { ($0.scheduledDay.map { $0 <= today } ?? false) || ($0.dueDay.map { $0 <= today } ?? false) }
        let todayIDs = Set(todayItems.map(\.id))
        let upcoming = active.filter { !todayIDs.contains($0.id) && ($0.scheduledDay != nil || $0.dueDay != nil) }
        let upcomingIDs = Set(upcoming.map(\.id))
        let later = active.filter { !todayIDs.contains($0.id) && !upcomingIDs.contains($0.id) }
        var sections = [TaskSection]()
        if !todayItems.isEmpty { sections.append(TaskSection(title: "Today", items: todayItems)) }
        if !upcoming.isEmpty { sections.append(TaskSection(title: "Upcoming", items: upcoming)) }
        if !later.isEmpty { sections.append(TaskSection(title: "Later", items: later)) }
        let completed = list.items.filter(\.done)
        if showCompleted && !completed.isEmpty { sections.append(TaskSection(title: "Completed", items: completed)) }
        return sections
    }

    private func taskRow(_ item: TodoItem, in list: TodoList) -> some View {
        HStack(spacing: 14) {
            Button { toggle(item) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(item.done ? theme.accent : theme.ink.opacity(0.5))
            }.buttonStyle(.plain).accessibilityLabel(item.done ? "Mark \(item.title) incomplete" : "Complete \(item.title)")
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).strikethrough(item.done).foregroundStyle(item.done ? theme.ink.opacity(0.5) : theme.ink).textSelection(.enabled)
                if let due = item.dueDay { Text("Due \(due.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                else if let day = item.scheduledDay { Text(day <= CalendarDay() ? "Today" : day.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                TaskMaterialButtons(references: item.materials ?? [])
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                ItemActions(reference: .init(kind: .todoItem, id: item.id, parentID: list.id))
                Divider()
                Button("Study materials…") { linking = item }
                Button("Today") { schedule(item, day: CalendarDay()) }
                Button("Later") { schedule(item, day: nil) }
                Button("Due date…") { openSchedule(for: item) }
                Button("Edit…") { openEdit(for: item) }
                Button("Move to top") { moveToTop(item) }
                Button("Delete", role: .destructive) { remove(item) }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 28).accessibilityLabel("Options for \(item.title)")
        }
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(inspectedTaskID == item.id || router.taskID == item.id ? theme.accent.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { inspectedTaskID = item.id }
        .id(item.id)
    }

    @ViewBuilder private var todoInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let list, let item = list.items.first(where: { $0.id == inspectedTaskID }) {
                Text("SELECTED TASK").font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                Text(item.title).font(.system(size: 22, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true)
                if let due = item.dueDay {
                    Label("Due \(due.date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                } else if let scheduled = item.scheduledDay {
                    Label(scheduled <= CalendarDay() ? "Scheduled today" : "Scheduled \(scheduled.date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                }
                if !(item.materials ?? []).isEmpty {
                    Divider()
                    Text("STUDY MATERIALS").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                    TaskMaterialButtons(references: item.materials ?? [])
                }
                Button { hub.run(.focus(.init(kind: .todoItem, id: item.id, parentID: list.id))) } label: {
                    Label("Focus on this", systemImage: "timer").frame(maxWidth: .infinity)
                }.buttonStyle(PrimaryButtonStyle()).disabled(item.done)
                HStack {
                    Button("Edit") { openEdit(for: item) }
                    Button("Schedule") { openSchedule(for: item) }
                }
                Button("Study materials…") { linking = item }.font(.caption)
                Spacer(minLength: 0)
            } else if let list {
                let today = CalendarDay()
                let active = list.items.filter { !$0.done }
                let todayCount = active.filter { ($0.scheduledDay.map { $0 <= today } ?? false) || ($0.dueDay.map { $0 <= today } ?? false) }.count
                Text("AT A GLANCE").font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                metric("Remaining", value: active.count)
                metric("Today", value: todayCount)
                metric("Completed", value: list.items.filter(\.done).count)
                Divider()
                Text(timer.clock.running ? "\(timer.clock.phase.rawValue) · \(timer.time)" : "No focus session running").font(.callout.weight(.medium))
                Text(timer.clock.running ? "The timer will continue while you work here." : "Choose a task, then focus on it when you’re ready.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Open Pomodoro") { hub.navigate(.pomodoro) }.font(.caption)
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.ink.opacity(0.07)))
    }

    private func metric(_ label: String, value: Int) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text("\(value)").monospacedDigit() }.font(.callout)
    }

    private func openEdit(for item: TodoItem) { editing = item; editTitle = item.title }
    private func openSchedule(for item: TodoItem) {
        scheduling = item; dueEnabled = item.dueDay != nil; dueDate = item.dueDay?.date ?? Date()
    }

    private func add() {
        guard !trimmedDraft.isEmpty, var list else { return }
        list.items.append(TodoItem(title: trimmedDraft))
        if store.update(list) { draft = ""; inputFocused = true }
    }
    private func schedule(_ item: TodoItem, day: CalendarDay?) {
        guard var list, let index = list.items.firstIndex(where: { $0.id == item.id }) else { store.error = "This task is no longer available."; return }
        list.items[index].scheduledDay = day; store.update(list)
    }
    private func toggle(_ item: TodoItem) {
        guard var list, let index = list.items.firstIndex(where: { $0.id == item.id }) else { return }
        list.items[index].done.toggle(); store.update(list)
    }
    private func moveToTop(_ item: TodoItem) {
        guard var list else { return }
        list.items.removeAll { $0.id == item.id }; list.items.insert(item, at: 0); store.update(list)
    }
    private func remove(_ item: TodoItem) {
        guard var list, let index = list.items.firstIndex(where: { $0.id == item.id }) else { return }
        list.items.remove(at: index)
        if store.update(list) { deleted = (list.id, item, index) }
    }
    private func undoDelete() {
        guard let deleted, var list = store.lists.first(where: { $0.id == deleted.listID }) else { return }
        list.items.insert(deleted.item, at: min(deleted.index, list.items.count))
        if store.update(list) { self.deleted = nil }
    }
    private func saveName() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if rename, var list { list.name = title; if store.update(list) { naming = false } }
        else { let list = TodoList(name: title); if store.save(store.lists + [list]) { selected = list.id; naming = false } }
    }
    private func saveEdit() {
        guard let editing, var list, let index = list.items.firstIndex(where: { $0.id == editing.id }) else { return }
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        list.items[index].title = title
        if store.update(list) { self.editing = nil }
    }
}
