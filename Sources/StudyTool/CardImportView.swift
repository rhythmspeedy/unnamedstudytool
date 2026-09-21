import SwiftUI
import UniformTypeIdentifiers

struct CardImportView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var hub: StudyHub
    @Environment(\.dismiss) private var dismiss
    var initialDeckID: UUID?
    @State private var destination: UUID?
    @State private var name = ""
    @State private var text = ""
    @State private var delimiter = "Tab"
    @State private var skipHeader = false
    @State private var importing = false
    @State private var preview: [Card] = []
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import flashcards").font(.title2)
            Text("Two columns: prompt and answer. Paste tab-separated pairs, or open a CSV. Nothing is saved until you confirm.").foregroundStyle(.secondary)
            HStack {
                Picker("Separated by", selection: $delimiter) { Text("Tab").tag("Tab"); Text("Comma").tag("Comma") }
                Toggle("First row is a header", isOn: $skipHeader)
                Button("Open file…") { importing = true }
            }
            TextEditor(text: $text).font(.body.monospaced()).frame(height: 140).accessibilityLabel("Question and answer pairs")
            Picker("Add to", selection: $destination) {
                Text("New deck").tag(Optional<UUID>.none)
                ForEach(library.decks) { Text($0.name).tag(Optional($0.id)) }
            }
            if destination == nil { TextField("New deck name", text: $name).textFieldStyle(.roundedBorder) }
            Button("Preview import") {
                do { preview = try CardTextImport.parse(text, separator: delimiter == "Tab" ? "\t" : ",", skipHeader: skipHeader); error = nil }
                catch { preview = []; self.error = error.localizedDescription }
            }.disabled(text.isEmpty)
            if !preview.isEmpty {
                Text("\(preview.count) cards · existing cards will be kept").font(.headline)
                List(preview.prefix(100)) { card in
                    VStack(alignment: .leading) { Text(card.front).lineLimit(2); Text(card.back).foregroundStyle(.secondary).lineLimit(2) }
                }.frame(height: 140)
                if preview.count > 100 { Text("Showing the first 100 cards.").font(.caption) }
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer()
                Button("Import \(preview.count) cards") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(preview.isEmpty || (destination == nil && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }.padding(26).frame(width: 600).modifier(AppAppearance())
        .onAppear { destination = initialDeckID }
        .onChange(of: text) { _, _ in preview = [] }
        .onChange(of: delimiter) { _, _ in preview = [] }
        .onChange(of: skipHeader) { _, _ in preview = [] }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 10_000_000 else { throw WorkspaceFailure.invalid("Import up to 10 MB at a time.") }
                text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
                delimiter = url.pathExtension.lowercased() == "csv" ? "Comma" : "Tab"
                preview = []; error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
    private func save() {
        var decks = library.decks
        let id: UUID
        if let destination {
            guard let index = decks.firstIndex(where: { $0.id == destination }) else { error = "Choose an available deck."; return }
            decks[index].cards += preview; id = destination
        } else {
            let deck = Deck(name: name.trimmingCharacters(in: .whitespacesAndNewlines), cards: preview)
            decks.append(deck); id = deck.id
        }
        guard library.save(decks) else { error = library.error; return }
        hub.router.deckID = id; hub.notice = "Imported \(preview.count) cards"; dismiss()
    }
}
