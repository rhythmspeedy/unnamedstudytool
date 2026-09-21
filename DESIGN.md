# Implementation and design

## Scope

Native macOS study workspace with offline flashcards, notes, tasks, Pomodoro, and optional study aids. See IMPLEMENTATION.md for the completed 1.1 feature checklist. No service dependencies.

## Decisions

- SwiftUI provides native windows, menus, file pickers, keyboard actions, and accessibility semantics.
- Twenty palettes range from grayscale to muted natural colors. Serif headings and study text distinguish content from compact controls.
- A consistent animated navigation control switches between Home, Flashcards, Notes, To-do, and Pomodoro. Study sessions render inline. Optional focus mode hides navigation without destroying the active editor. Home and Pomodoro scroll when space is limited.
- One shared Pomodoro store owns both the deadline and ticker, independently of window visibility. The persistent status strip and optional menu-bar controls use this same clock. Content and study metadata use separate files; full workspace backups link them through validated references.
- Save each edit atomically before updating the visible library. Preserve unreadable files and report save failures.
- Deck progress persists; combined sessions are temporary. Space flips both ways, Right Arrow/X advances, and Left Arrow/Z restores the prior card and queue. Confidence ratings are optional, never a navigation gate.
- The optional timer reveals the answer instead of advancing or grading on the learner’s behalf. It pauses when the app is inactive.
- Before replacing the library file, the app keeps the previous version beside it as `library.previous.json` for basic recovery.

## Design references

Apple’s [typography guidance](https://developer.apple.com/design/human-interface-guidelines/typography) informs the restrained type hierarchy and readable control text. This [overview of repetitive AI design patterns](https://www.925studios.co/blog/ai-slop-design-tells) informed the deliberate grayscale and serif direction. The app uses native platform controls where familiarity improves usability.

## Verification

`bash test.sh` checks study repetition, completion, shuffle membership, persistence across reloads, protection of unreadable data, and failed-save behavior. `bash build-app.sh` compiles an optimized executable and packages it with an icon and local signature.
