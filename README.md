# unnamedstudytool

A native, offline Mac study workspace with flashcards, notes, to-do lists, and a Pomodoro timer. Requires macOS 14 or later.

[Download the Mac app](https://github.com/rhythmspeedy/unnamedstudytool/releases/latest) — Apple Silicon (M-series), macOS 14+. Download the app ZIP under **Assets**, unzip it, and drag the app into Applications. The current release is not Apple-notarized; see the signing notice below.

## Your workspace

Home opens Flashcards, Notes, To-do, or Pomodoro in any order. Today brings together recent work, up to five pinned items, scheduled tasks, an optional daily target, and study totals. Navigation remains available at the top of each tool. Pomodoro belongs to the app and continues across navigation and when the main window is closed. Enable its optional menu-bar control in Settings → General.

Use **⌘K** to find items or actions, **⇧⌘Space** to capture a task, note, or flashcard, and **⇧⌘F** for a distraction-free view of the current tool. Escape exits focus mode. Item menus offer pinning and a focus intention; the intention stays visible alongside the timer. History shows recent activity without streak penalties.

To-do opens one default list. Type a task and press Return, check it off, or use its menu to edit, move it to the top, or delete it. A deleted task can be undone while you remain on that page. Completed tasks can be shown again. The Lists menu contains optional additional lists and list management.

Pomodoro uses 25-minute focus intervals, 5-minute short breaks, and a 15-minute long break after four completed focus intervals. Start each next interval when ready. Pause and resume from the page or the persistent status strip. A deadline keeps the timer accurate when backgrounded or asleep; the app shows completion when it resumes. Quitting ends the timer run. No system notification permission is needed; completion appears inside the app.

Settings is available from Home, the top-bar gear, and the standard macOS Settings menu. General contains themes, daily targets, and the menu-bar timer; Flashcards contains focus size/card timers; Pomodoro contains interval durations and ambient sound tiles. Choose Silence, Rain, Brown noise, or Room tone, preview it, and adjust volume. Sounds are synthesized locally, require no downloads, and default to silence. Duration changes apply to the next interval or a reset.

Task menus can schedule work for Today or Later and add a due date. Today includes overdue tasks without hiding them. Dates are stored as calendar dates, not midnight timestamps.

Research: [Pomodoro timing overview](https://www.nextutils.com/blog/pomodoro-technique-guide).

## Open

Double-click **unnamedstudytool.app** in this folder. You can also drag it into Applications and keep it in your Dock. No server, account, or internet connection is needed.

For a downloaded release, unzip the app and drag it into Applications. Download the app ZIP from the repository's **Releases** area, not GitHub's automatic source-code ZIP. Files labeled `arm64` require Apple Silicon (M-series); files labeled `x86_64` require Intel. macOS 14 or later is required.

Current local packages are ad-hoc signed, **not Apple-notarized**. macOS may block a downloaded copy. See [Apple's guidance on opening apps safely](https://support.apple.com/102445); only approve an app if you trust its source. Do not disable Gatekeeper globally. A normal public distribution build should use Developer ID signing and Apple notarization.

## Study

1. Create a deck in the sidebar.
2. Add cards with a prompt and answer. Use **Save & add another** for quick entry.
3. Start studying. Press **Space** to flip between prompt and answer, **→** to advance at any time, and **←** to return to the previous card. **Z / X** are quiet alternatives for previous and next. Browsing never requires revealing a card first.

Search finds text on either side of a card. Deck options include rename, delete, and resetting saved study progress. Resume starts at the saved card; Start from beginning is also available. Combine decks for a temporary mixed session without changing their contents. After revealing an answer, optional **1 / 2 / 3** confidence controls mean Again / Unsure / Know. Arrow keys still move freely without grading.

Open **unnamedstudytool → Settings…** to choose among twenty themes, select the focus-session size, and configure an optional per-card timer.

Shortcuts: **⌘N** new deck, **⇧⌘N** add card, **⌘R** study, **Space** flip, **→ / X** next, **← / Z** previous, **Escape** close a dialog or study session.

## Notes

Open Notes from Home or the top navigation. Create a note with **⌘N**, type a title and plain-text body, and use **⌘F** to search titles and contents. Use **New page** or **⇧⌘N** to append another titled writing section to the same note; search and text export include every page. Notes appear most recently edited first. Standard Mac editing shortcuts work in the editor. The selected note, editor scroll position, and undo history remain available when switching tools; Pomodoro continues running.

Edits save after a short pause and before switching notes or tools. The small status label shows saving progress. Failed saves preserve the draft in memory and offer retry or text export. The options menu exports a `.txt` file or deletes the note; **Undo delete** restores the most recently deleted note during the app session.

Select note text and use its context menu to create a flashcard with that text as the answer. Review the prompt and destination before saving.

Notes are stored in `~/Library/Application Support/unnamedstudytool/notes.json`, with the previous successful save in `notes.previous.json`. If the main file cannot be read, Notes offers recovery and preserves the damaged file as an archive.

## Your data

Changes save automatically to `~/Library/Application Support/unnamedstudytool/library.json`. Use **Library backup → Export library** to make a JSON backup. Import adds independent copies of the decks in a backup, preserving your existing decks. Deleted cards and decks remain recoverable for 30 days in **Settings → Data → Recently deleted**.

**Settings → Data** exports the entire workspace: decks, notes, tasks, pins, study progress/history, targets, and preferences. Import offers Merge (independent copies, keeping current preferences) or confirmed Replace. Imports validate versions, IDs, references, and a checksum before writing. A pre-import recovery archive and rollback journal protect against interrupted imports; use **Restore pre-import recovery archive** to restore an archived workspace. Backups contain readable personal study data, not encrypted data—keep them somewhere private.

## New in 1.2

- **Optional review queue:** rating a revealed card schedules its next review: Again in 10 minutes, Unsure tomorrow, Know in 3 days (doubling up to 30 days on later Know ratings). Home offers ready cards. Ordinary arrow-key browsing never changes the schedule or locks navigation.
- **Linked study materials:** a task’s options menu → Study materials links notes and decks. Open them from the task, or use the existing Focus on this action to start a timer with an intention. Links do not duplicate content.
- **Flashcard recovery:** deletions save a recovery copy before changing the library. Settings → Data restores decks or cards for 30 days, keeping existing cards. A failed recovery save prevents deletion.
- **Automatic local backups:** enabled by default, keeping the first snapshot each active day for up to 14 snapshots. They run on launch and check for a new day every ten minutes while the app is open. Settings → Data can disable them or preview and restore a snapshot. Disabled backups stop new snapshots, not existing retention files. These are not encrypted and do not protect against loss of the Mac; export off-device for that.
- **Paste/CSV imports:** Flashcards → Library backup → Import pasted text or CSV. Choose tab or comma separation, optionally skip a header, preview, then add to an existing or new deck. Quoted commas, Unicode, and multiline CSV fields are supported. Imports are limited to 10 MB / 10,000 cards per batch.
- **Restore previews:** inspect counts and deck names before merging or replacing any full backup. Replacement requires confirmation and keeps a pre-import archive.
- **Accessibility and efficiency:** explicit action labels, reduced-motion sidebar behavior, fewer repeated note searches, and direct destination lookup. Automated checks cover primary, accent, and button text contrast across all twenty themes; they do not constitute a complete VoiceOver certification.
- **Manual updates:** Settings → General or the app menu opens official GitHub releases. Quit the app and replace the application bundle; study data stays in Application Support. Published assets are not updated automatically by a local build.

Old app versions do not understand new review, link, and recovery metadata and may discard it when saving. Keep a full backup before downgrading.

## New in 1.3

Focus sounds now offer fifteen choices organized into four compact groups:

- **Quiet:** Silence.
- **Noise colors:** White noise, Pink noise, and Brown noise.
- **Weather & nature:** Rain, Forest rain, Deep ocean, Distant thunder, and Fireplace.
- **Places & motion:** Room tone, Desk fan, Quiet café, Library room, Night train, and Airplane cabin.

Every texture is synthesized locally on demand, cached for fast replay during the current run, and crossfaded into a continuous loop. No recorded audio, third-party license, attribution, download, or network request is involved. Atmospheric events are deliberately subdued so voices, page turns, rail sounds, crackles, and thunder do not compete with studying. Silence remains the default.

## Build and test

With Apple's Swift tools installed:

```sh
bash test.sh
bash build-app.sh
```

The build script creates a locally signed application in this folder for the current Mac architecture. This is a local app, not a notarized distribution release.

To package a release for the current Mac architecture:

```sh
bash package-release.sh
```

This rebuilds the app, verifies its signature, and creates a ZIP and SHA-256 checksum in `dist/`. Upload these as release assets. It does not upload anything or notarize the app. Personal study data lives outside the repository and is not included in the app bundle or ZIP.
