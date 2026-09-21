import SwiftUI

@main struct IntegrationChecks {
    @MainActor static func main() throws {
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw WorkspaceFailure.invalid(message) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StudyIntegration-\(UUID())")
        let suite = "StudyIntegration-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "automaticBackups")
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let hub = StudyHub(directory: root, defaults: defaults)
        let card = Card(front: "Question", back: "Answer")
        var deck = Deck(name: "Recovery check", cards: [card])
        try check(hub.library.save([deck]), "Create deck")
        hub.rate(card, confidence: .know)
        try check(hub.dueCards.isEmpty, "Newly confident cards are scheduled later")
        hub.workspace.change { $0.reviews?[card.id]?.due = .distantPast }
        try check(hub.dueCards.map(\.id) == [card.id], "Due queue contains scheduled cards")
        deck.cards = []
        try check(hub.library.save([deck]), "Delete card with recovery")
        try check(hub.workspace.state.deletedFlashcards?.first?.deck.cards == [card], "Deletion retains original card")
        hub.restoreDeleted(hub.workspace.state.deletedFlashcards!.first!)
        try check(hub.library.decks.first?.cards == [card] && hub.workspace.state.deletedFlashcards?.isEmpty == true, "Restoring a card preserves its ID")
        try check(hub.library.save([]), "Delete deck with recovery")
        let archived = hub.workspace.state.deletedFlashcards!.first!
        hub.restoreDeleted(archived); hub.restoreDeleted(archived)
        try check(hub.library.decks.count == 1 && hub.library.decks[0].cards.count == 1, "Restore retry is idempotent")
        defaults.set(true, forKey: "automaticBackups")
        hub.automaticBackup()
        try check(hub.automaticBackupError == nil && hub.automaticBackupDate != nil, "App-owned daily backup succeeds")
        let backupFiles = try DailyBackups.files(in: hub.automaticBackupDirectory)
        try check(backupFiles.count == 1, "One daily snapshot")

        func luminance(_ color: Color) -> Double {
            let rgb = NSColor(color).usingColorSpace(.sRGB)!
            func channel(_ value: CGFloat) -> Double { let v = Double(value); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent) + 0.0722 * channel(rgb.blueComponent)
        }
        func contrast(_ a: Color, _ b: Color) -> Double {
            let a = luminance(a), b = luminance(b)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        for theme in StudyTheme.allCases {
            try check(contrast(theme.ink, theme.background) >= 4.5 && contrast(theme.ink, theme.surface) >= 4.5, "\(theme.title) body contrast")
            try check(contrast(theme.buttonInk, theme.accent) >= 4.5, "\(theme.title) button contrast")
            try check(contrast(theme.accent, theme.surface) >= 4.5, "\(theme.title) accent text contrast")
        }
        print("PASS: app-level review/recovery/backups and all 20 theme text/button palettes")
    }
}
