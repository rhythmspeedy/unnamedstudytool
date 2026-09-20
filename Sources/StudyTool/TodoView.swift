import SwiftUI

struct TodoView: View {
    @EnvironmentObject private var store: TodoStore
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    @State private var selected: UUID?
    @State private var draft = ""
    @State private var showCompleted = false
    @State private var naming = false
    @State private var rename = false
    @State private var name = ""
    @State private var editing: TodoItem?
    @State private var editTitle = ""
    @State private var deleteList = false
    @State private var deleted: (listID: UUID, item: TodoItem, index: Int)?
    @FocusState private var inputFocused: Bool
    private var list: TodoList? { store.lists.first { $0.id == selected } ?? store.lists.first }
    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TO-DO").font(.system(size: 11, design: .monospaced)).tracking(3).foregroundStyle(.secondary)
                    Text(list?.name ?? "Your list").font(.system(size: 36, design: .serif))
                }
                Spacer()
                Menu {
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
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(list.items.filter { showCompleted || !$0.done }) { item in
                            HStack(spacing: 14) {
                                Button { toggle(item) } label: {
                                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(item.done ? theme.accent : theme.ink.opacity(0.5))
                                }.buttonStyle(.plain).accessibilityLabel(item.done ? "Mark \(item.title) incomplete" : "Complete \(item.title)")
                                Text(item.title).strikethrough(item.done).foregroundStyle(item.done ? theme.ink.opacity(0.5) : theme.ink).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                Menu {
                                    Button("Edit…") { editing = item; editTitle = item.title }
                                    Button("Move to top") { moveToTop(item) }
                                    Button("Delete", role: .destructive) { remove(item) }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 28)
                            }.padding(16).background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
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
            }
            if deleted != nil {
                HStack {
                    Text("Task deleted").font(.caption).foregroundStyle(.secondary)
                    Button("Undo") { undoDelete() }
                    Spacer()
                }
            }
        }.padding(36).frame(maxWidth: 950, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { inputFocused = true }
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

    private func add() {
        guard !trimmedDraft.isEmpty, var list else { return }
        list.items.append(TodoItem(title: trimmedDraft))
        if store.update(list) { draft = ""; inputFocused = true }
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
