import SwiftUI
import AppKit

/// Retains each native editor's scroll position, selection, and undo history across tool changes.
@MainActor
final class NoteEditorCache: ObservableObject {
    var views: [UUID: NSScrollView] = [:]
}

struct NoteEditor: NSViewRepresentable {
    let noteID: UUID
    let pageID: UUID?
    let body: String
    let store: NotesStore
    let cache: NoteEditorCache
    let theme: StudyTheme
    var createCard: (String) -> Void = { _ in }

    private var cacheID: UUID { pageID ?? noteID }

    func makeCoordinator() -> Coordinator { Coordinator(store: store, noteID: noteID, pageID: pageID) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll: NSScrollView
        if let existing = cache.views[cacheID] {
            scroll = existing
        } else {
            scroll = CardCreatingTextView.scrollableTextView()
            guard let text = scroll.documentView as? NSTextView else { preconditionFailure("Expected a native text editor") }
            text.isRichText = false
            text.importsGraphics = false
            text.allowsUndo = true
            text.isAutomaticLinkDetectionEnabled = false
            text.isAutomaticTextReplacementEnabled = false
            text.font = .systemFont(ofSize: 16)
            text.textContainerInset = NSSize(width: 14, height: 16)
            text.defaultParagraphStyle = {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 5
                return style
            }()
            text.string = body
            text.setAccessibilityLabel(pageID == nil ? "First page body" : "Page body")
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            cache.views[cacheID] = scroll
        }
        (scroll.documentView as? NSTextView)?.delegate = context.coordinator
        (scroll.documentView as? CardCreatingTextView)?.createCard = createCard
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        if text.string != body { text.string = body }
        text.backgroundColor = NSColor(theme.background)
        text.textColor = NSColor(theme.ink)
        text.insertionPointColor = NSColor(theme.accent)
        scroll.backgroundColor = NSColor(theme.background)
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        // Flush marked-text edits too, before detaching the native view.
        if let text = view.documentView as? NSTextView {
            if coordinator.isCurrent {
                coordinator.save(text.string)
                coordinator.store.flush()
            }
            text.delegate = nil
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let store: NotesStore
        let noteID: UUID
        let pageID: UUID?
        let epoch: UUID
        init(store: NotesStore, noteID: UUID, pageID: UUID?) {
            self.store = store; self.noteID = noteID; self.pageID = pageID; epoch = store.contentEpoch
        }
        var isCurrent: Bool {
            guard epoch == store.contentEpoch, let note = store.notes.first(where: { $0.id == noteID }) else { return false }
            return pageID.map { id in note.pages.contains(where: { $0.id == id }) } ?? true
        }
        func save(_ body: String) {
            if let pageID { store.editPage(noteID: noteID, pageID: pageID, body: body) }
            else { store.edit(id: noteID, body: body) }
        }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            guard isCurrent else { return } // A replaced workspace or deleted page invalidates old editor callbacks.
            save(text.string)
        }
    }
}

final class CardCreatingTextView: NSTextView {
    var createCard: ((String) -> Void)?
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        if selectedRange().length > 0 {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Create flashcard from selection…", action: #selector(makeCard), keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        return menu
    }
    @objc private func makeCard() {
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else { NSSound.beep(); return }
        createCard?((string as NSString).substring(with: range))
    }
}

@MainActor
final class StudyAppDelegate: NSObject, NSApplicationDelegate {
    var notes: NotesStore?
    var workspace: WorkspaceStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let notesSaved = notes?.dirty != true || notes?.flush() == true
        let workspaceSaved = workspace?.dirty != true || workspace?.flush() == true
        guard !notesSaved || !workspaceSaved else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Your latest changes have not been saved"
        alert.informativeText = "Keep the app open to retry saving. \(notes?.error ?? workspace?.error ?? "")"
        alert.addButton(withTitle: "Keep editing")
        alert.runModal()
        return .terminateCancel
    }
}
