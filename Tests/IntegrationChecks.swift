import SwiftUI
import AVFoundation

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
        try check(Set(AmbientSound.allCases.map(\.title)).count == AmbientSound.allCases.count, "Ambient titles are unique")
        try check(AmbientSound.Category.allCases.allSatisfy { category in AmbientSound.allCases.contains { $0.category == category } }, "Every ambient category has a sound")
        var generated = Set<Data>()
        for sound in AmbientSound.allCases {
            let data = AmbientAudioController.wave(sound)
            try check(data.count == 44 + 22_050 * 24 * 2, "\(sound.title) has the expected duration")
            try check(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF" && String(decoding: data[8..<12], as: UTF8.self) == "WAVE", "\(sound.title) is a WAV file")
            if sound != .silence { try check(data.dropFirst(44).contains { $0 != 0 }, "\(sound.title) contains audible samples") }
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            try check(player.prepareToPlay() && abs(player.duration - 24) < 0.01, "\(sound.title) decodes as 24-second audio")
            generated.insert(data)
        }
        try check(generated.count == AmbientSound.allCases.count, "Every ambient choice generates a distinct texture")
        print("PASS: app-level review/recovery/backups, 20 theme palettes, and \(AmbientSound.allCases.count) ambient textures")
    }
}
