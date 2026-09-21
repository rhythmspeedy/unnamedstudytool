import SwiftUI

struct MaterialLinksView: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var todos: TodoStore
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var notes: NotesStore
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID
    let listID: UUID
    @State private var query = ""
    @State private var selected: Set<StudyItemReference> = []
    @State private var error: String?
    private var items: [StudyDestination] {
        hub.destinations.filter { ($0.reference.kind == .deck || $0.reference.kind == .note) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Study materials").font(.title2)
            Text("Link notes or decks to this task. Their contents stay where they are.").foregroundStyle(.secondary)
            TextField("Find notes or decks", text: $query).textFieldStyle(.roundedBorder)
            List(items) { item in
                Toggle(isOn: Binding(get: { selected.contains(item.reference) }, set: { on in
                    if on { selected.insert(item.reference) } else { selected.remove(item.reference) }
                })) { Label(item.title, systemImage: item.icon) }
            }.frame(height: 270)
            if items.isEmpty { Text(query.isEmpty ? "Create a note or deck first." : "No matching materials.").foregroundStyle(.secondary) }
            if selected.contains(where: { hub.resolve($0) == nil }) {
                Button("Remove unavailable links") { selected = Set(selected.filter { hub.resolve($0) != nil }) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save links") {
                    guard var list = todos.lists.first(where: { $0.id == listID }), let index = list.items.firstIndex(where: { $0.id == taskID }) else { error = "This task no longer exists."; return }
                    list.items[index].materials = selected.sorted { $0.key < $1.key }
                    if todos.update(list) { dismiss() } else { error = todos.error }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 500).modifier(AppAppearance())
        .onAppear { selected = Set(todos.lists.first { $0.id == listID }?.items.first { $0.id == taskID }?.materials ?? []) }
    }
}

struct TaskMaterialButtons: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var notes: NotesStore
    let references: [StudyItemReference]
    var body: some View {
        ForEach(references) { reference in
            if let destination = hub.resolve(reference) {
                Button { hub.run(.open(reference)) } label: { Label(destination.title, systemImage: destination.icon).lineLimit(1) }
                    .buttonStyle(.link).font(.caption).accessibilityLabel("Open linked \(destination.subtitle): \(destination.title)")
            } else { Text("Linked material is unavailable — edit links to remove it").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
