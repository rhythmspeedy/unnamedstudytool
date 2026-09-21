# unnamedstudytool 1.2

Version 1.2 turns unnamedstudytool into a more connected study workspace while keeping it offline and straightforward.

## Highlights

- Optional review queue based on Again, Unsure, and Know ratings.
- Link a task directly to relevant notes and flashcard decks.
- Recover deleted decks and cards for 30 days.
- Automatic daily local backups with a restore preview.
- Paste tab-separated flashcards or import CSV files after reviewing a preview.
- Full-workspace backup previews before Merge or Replace.
- Today view, pins, quick capture, command search, focus mode, study history, daily targets, combined-deck sessions, note-to-card capture, and selectable ambient focus sounds.
- Improved keyboard navigation, reduced-motion behavior, accessibility labels, and theme contrast.

## Download

Download **`unnamedstudytool-1.2-macOS-arm64.zip`** from Assets. This build is for Apple Silicon Macs (M1 or newer) running macOS 14 or later.

The companion `.sha256` file can be used to verify the ZIP after downloading:

```sh
shasum -a 256 -c unnamedstudytool-1.2-macOS-arm64.zip.sha256
```

## Install on macOS

1. Download and unzip `unnamedstudytool-1.2-macOS-arm64.zip`.
2. Drag `unnamedstudytool.app` into Applications.
3. Because this free build is not Apple-notarized, macOS may block the first launch. In Finder, Control-click the app, choose **Open**, then choose **Open** again.
4. If macOS still blocks it, open **System Settings → Privacy & Security**, find the message about unnamedstudytool, and choose **Open Anyway**. Only do this if you downloaded the app from this official repository.

Do not disable Gatekeeper globally. See [Apple’s instructions for safely opening Mac apps](https://support.apple.com/102445) for the current system wording.

## Updating from 1.0

Quit the old app, replace it in Applications with version 1.2, and reopen it. Your decks, notes, tasks, preferences, and progress live separately in Application Support and remain in place. For extra safety, export a full workspace backup from **Settings → Data** before updating.

## Distribution notice

This release is ad-hoc signed but is **not Developer ID signed or Apple-notarized**. It has no updater service, account requirement, analytics, or network dependency. Study data stays on your Mac unless you explicitly export it.
