import SwiftUI
import AppKit

/// Retains each native editor's scroll position, selection, and undo history across tool changes.
@MainActor
final class NoteEditorCache: ObservableObject {
    var views: [UUID: NSScrollView] = [:]
}

struct NoteEditor: NSViewRepresentable {
    let note: StudyNote
    let store: NotesStore
    let cache: NoteEditorCache
    let theme: StudyTheme

    func makeCoordinator() -> Coordinator { Coordinator(store: store, id: note.id) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll: NSScrollView
        if let existing = cache.views[note.id] {
            scroll = existing
        } else {
            scroll = NSTextView.scrollableTextView()
            guard let text = scroll.documentView as? NSTextView else { preconditionFailure("Expected a native text editor") }
            text.isRichText = false
            text.importsGraphics = false
            text.allowsUndo = true
            text.isAutomaticLinkDetectionEnabled = false
            text.isAutomaticTextReplacementEnabled = false
            text.font = .systemFont(ofSize: 16)
            text.textContainerInset = NSSize(width: 20, height: 22)
            text.defaultParagraphStyle = {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 5
                return style
            }()
            text.string = note.body
            text.setAccessibilityLabel("Note body")
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            cache.views[note.id] = scroll
        }
        (scroll.documentView as? NSTextView)?.delegate = context.coordinator
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        if text.string != note.body { text.string = note.body }
        text.backgroundColor = NSColor(theme.background)
        text.textColor = NSColor(theme.ink)
        text.insertionPointColor = NSColor(theme.accent)
        scroll.backgroundColor = NSColor(theme.background)
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        // Flush marked-text edits too, before detaching the native view.
        if let text = view.documentView as? NSTextView {
            if coordinator.store.notes.contains(where: { $0.id == coordinator.id }) {
                coordinator.store.edit(id: coordinator.id, body: text.string)
                coordinator.store.flush()
            }
            text.delegate = nil
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let store: NotesStore
        let id: UUID
        init(store: NotesStore, id: UUID) { self.store = store; self.id = id }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            store.edit(id: id, body: text.string)
        }
    }
}

@MainActor
final class StudyAppDelegate: NSObject, NSApplicationDelegate {
    var notes: NotesStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let notes, notes.dirty, !notes.flush() else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Your latest notes have not been saved"
        alert.informativeText = "Keep the app open to retry saving or export a text copy. \(notes.error ?? "")"
        alert.addButton(withTitle: "Keep editing")
        alert.runModal()
        return .terminateCancel
    }
}
