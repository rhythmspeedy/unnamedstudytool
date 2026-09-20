# unnamedstudytool

A native, offline Mac study workspace with flashcards, notes, to-do lists, and a Pomodoro timer. Requires macOS 14 or later.

[Download the Mac app](https://github.com/rhythmspeedy/unnamedstudytool/releases/latest) — Apple Silicon (M-series), macOS 14+. Download the app ZIP under **Assets**, unzip it, and drag the app into Applications. The current release is not Apple-notarized; see the signing notice below.

## Your workspace

The Home page opens Flashcards, To-do, or Pomodoro in any order. Navigation remains available at the top of each tool. Switching tools closes that tool’s temporary view; your decks and tasks remain saved. Pomodoro state belongs to the app and continues across navigation, including flashcard focus sessions.

To-do opens one default list. Type a task and press Return, check it off, or use its menu to edit, move it to the top, or delete it. A deleted task can be undone while you remain on that page. Completed tasks can be shown again. The Lists menu contains optional additional lists and list management.

Pomodoro uses 25-minute focus intervals, 5-minute short breaks, and a 15-minute long break after four completed focus intervals. Start each next interval when ready. Pause and resume from the page or the persistent status strip. A deadline keeps the timer accurate when backgrounded or asleep; the app shows completion when it resumes. Quitting ends the timer run. No system notification permission is needed; completion appears inside the app.

Settings is available from Home, the top-bar gear, and the standard macOS Settings menu. General contains themes, Flashcards contains focus size/card timers, and Pomodoro contains interval durations. Duration changes apply to the next interval or a reset.

To-do data is saved separately in `~/Library/Application Support/unnamedstudytool/todos.json`. The existing Library backup feature exports flashcards only.

Research: [Pomodoro timing overview](https://www.nextutils.com/blog/pomodoro-technique-guide).

## Open

Double-click **unnamedstudytool.app** in this folder. You can also drag it into Applications and keep it in your Dock. No server, account, or internet connection is needed.

For a downloaded release, unzip the app and drag it into Applications. Download the app ZIP from the repository's **Releases** area, not GitHub's automatic source-code ZIP. Files labeled `arm64` require Apple Silicon (M-series); files labeled `x86_64` require Intel. macOS 14 or later is required.

Current local packages are ad-hoc signed, **not Apple-notarized**. macOS may block a downloaded copy. See [Apple's guidance on opening apps safely](https://support.apple.com/102445); only approve an app if you trust its source. Do not disable Gatekeeper globally. A normal public distribution build should use Developer ID signing and Apple notarization.

## Study

1. Create a deck in the sidebar.
2. Add cards with a prompt and answer. Use **Save & add another** for quick entry.
3. Start studying. Press **Space** to flip between prompt and answer, **→** to advance at any time, and **←** to return to the previous card. **Z / X** are quiet alternatives for previous and next. Browsing never requires revealing a card first.

Search finds text on either side of a card. Deck options include rename and delete. End a session anytime; cards remain saved, while session progress resets next time.

Open **unnamedstudytool → Settings…** or use the Settings button in the sidebar to choose a Graphite, Parchment, Forest, Ocean, or Clay theme; select the focus-session size; and configure an optional per-card timer.

Shortcuts: **⌘N** new deck, **⇧⌘N** add card, **⌘R** study, **Space** flip, **→ / X** next, **← / Z** previous, **Escape** close a dialog or study session.

## Notes

Open Notes from Home or the top navigation. Create a note with **⌘N**, type a title and plain-text body, and use **⌘F** to search titles and contents. Notes appear most recently edited first. Standard Mac editing shortcuts work in the editor. The selected note, editor scroll position, and undo history remain available when switching tools; Pomodoro continues running.

Edits save after a short pause and before switching notes or tools. The small status label shows saving progress. Failed saves preserve the draft in memory and offer retry or text export. The options menu exports a `.txt` file or deletes the note; **Undo delete** restores the most recently deleted note during the app session.

Notes are stored in `~/Library/Application Support/unnamedstudytool/notes.json`, with the previous successful save in `notes.previous.json`. If the main file cannot be read, Notes offers recovery and preserves the damaged file as an archive. Flashcard library backups do not include notes.

## Your data

Changes save automatically to `~/Library/Application Support/unnamedstudytool/library.json`. Use **Library backup → Export library** to make a JSON backup. Import adds independent copies of the decks in a backup, preserving your existing decks. Deleted cards and decks cannot be undone; export before major changes.

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
