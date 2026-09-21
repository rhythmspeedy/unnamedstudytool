import SwiftUI

struct BackupCandidate: Identifiable {
    let id = UUID()
    let backup: WorkspaceBackup
    var allowMerge = true
}

struct BackupPreviewView: View {
    @EnvironmentObject private var hub: StudyHub
    @Environment(\.dismiss) private var dismiss
    let backup: WorkspaceBackup
    var allowMerge = true
    let install: (Bool) -> Void
    @State private var replacing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review this backup").font(.title2)
            Text("Saved \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened)) · app \(backup.appVersion)").foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                GridRow { Text("Content"); Text("This Mac"); Text("Backup") }.font(.headline)
                GridRow { Text("Decks"); Text("\(hub.library.decks.count)"); Text("\(backup.decks.count)") }
                GridRow { Text("Cards"); Text("\(hub.library.decks.flatMap(\.cards).count)"); Text("\(backup.decks.flatMap(\.cards).count)") }
                GridRow { Text("Notes"); Text("\(hub.notes.notes.count)"); Text("\(backup.notes.count)") }
                GridRow { Text("Tasks"); Text("\(hub.todos.lists.flatMap(\.items).count)"); Text("\(backup.todoLists.flatMap(\.items).count)") }
            }
            Text(backup.decks.prefix(4).map(\.name).joined(separator: " · ")).lineLimit(2).font(.caption)
            Text("Replace restores content, links, review dates, history, recovery items, and preferences. Current files are archived first. Active sessions close and the timer resets.").font(.callout)
            if allowMerge { Text("Merge adds independent copies and keeps your current preferences.").font(.callout) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if allowMerge { Button("Merge copies") { install(true) } }
                Button("Replace…", role: .destructive) { replacing = true }
            }
        }.padding(28).frame(width: 540).modifier(AppAppearance())
        .alert("Replace the current workspace?", isPresented: $replacing) {
            Button("Replace", role: .destructive) { install(false) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your current files will be archived locally before the backup is restored.") }
    }
}

struct DailyBackupSettingsView: View {
    @EnvironmentObject private var hub: StudyHub
    @AppStorage("automaticBackups") private var enabled = true
    @State private var files: [URL] = []
    @State private var pending: BackupCandidate?
    @State private var error: String?
    var body: some View {
        Section("Automatic backups") {
            Toggle("Keep daily local backups", isOn: $enabled).onChange(of: enabled) { _, on in if on { hub.automaticBackup(); refresh() } }
            Text("Keeps the first snapshot each active day, up to 14 days. These protect against accidental changes—not losing this Mac. Export a copy elsewhere for that.").font(.caption).foregroundStyle(.secondary)
            if let date = hub.automaticBackupDate { Text("Latest snapshot: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
            if let failure = hub.automaticBackupError { Text(failure).foregroundStyle(.red) }
            HStack {
                Button("Save today’s snapshot") { hub.automaticBackup(); refresh() }.disabled(!enabled)
                Menu("Restore a daily backup…") {
                    ForEach(files, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "daily-", with: "")) {
                            do { pending = BackupCandidate(backup: try WorkspaceBackup.decode(Data(contentsOf: url))) }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }.disabled(files.isEmpty)
            }
        }.onAppear { refresh() }
        .sheet(item: $pending) { candidate in
            BackupPreviewView(backup: candidate.backup) { merge in
                do { try hub.restore(candidate.backup, merge: merge); pending = nil }
                catch { self.error = error.localizedDescription; pending = nil }
            }
        }
        .alert("Backup needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func refresh() {
        do { files = try DailyBackups.files(in: hub.automaticBackupDirectory) }
        catch { self.error = error.localizedDescription }
    }
}

struct DeletedFlashcardsSettingsView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var showing = false
    var body: some View {
        Section("Recently deleted") {
            Text("Deleted decks and cards can be recovered for 30 days.").font(.caption).foregroundStyle(.secondary)
            Button("View recently deleted flashcards…") { showing = true }
        }.sheet(isPresented: $showing) { DeletedFlashcardsView() }
    }
}
struct DeletedFlashcardsView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var hub: StudyHub
    @Environment(\.dismiss) private var dismiss
    private var entries: [DeletedFlashcards] { (workspace.state.deletedFlashcards ?? []).filter { $0.expiresAt > Date() }.sorted { $0.deletedAt > $1.deletedAt } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Recently deleted").font(.title2); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Restoring keeps existing cards. Recovery copies expire after 30 days.").foregroundStyle(.secondary)
            if entries.isEmpty { ContentUnavailableView("Nothing to recover", systemImage: "trash", description: Text("Deleted flashcards appear here for 30 days.")) }
            else {
                List(entries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.deck.name).font(.headline)
                            Text("\(entry.wholeDeck ? "Deck" : "Cards") · \(entry.deck.cards.count) cards · until \(entry.expiresAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                            if !entry.wholeDeck { Text(entry.deck.cards.first?.front ?? "").lineLimit(1).font(.caption) }
                        }
                        Spacer(); Button("Restore") { hub.restoreDeleted(entry) }
                    }
                }
            }
        }.padding(26).frame(width: 580, height: 400).modifier(AppAppearance())
        .alert("Recovery needs attention", isPresented: Binding(get: { hub.error != nil || workspace.error != nil }, set: { if !$0 { hub.error = nil; workspace.error = nil } })) {
            Button("OK") { hub.error = nil; workspace.error = nil }
        } message: { Text(hub.error ?? workspace.error ?? "") }
    }
}
