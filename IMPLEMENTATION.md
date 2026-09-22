# Study workspace implementation — 1.1

## Focus sound expansion — 1.3

Done: white and pink noise, deep ocean, forest rain, fireplace, quiet café, night train, library room, desk fan, distant thunder, and airplane cabin. Together with Silence, Rain, Brown noise, and Room tone, the picker now has fifteen categorized choices. All audio is generated locally from deterministic filters, oscillators, envelopes, and noise; no recording licenses or downloads are required. Generated WAV data is cached in memory after first use and looped with a crossfaded boundary.

## Follow-up release — 1.2

Done: optional scheduled reviews, task-to-note/deck links, 30-day flashcard recovery, fourteen daily local snapshots, paste/CSV import preview, full-backup comparison previews, accessibility labels/reduced motion, note-search and destination-lookup efficiency improvements, and manual update access. New optional metadata decodes from existing saves and is remapped when backups merge.

Verified: legacy migration, quoted/multiline CSV, invalid inputs, schedule intervals, review/link/recovery backup round-trips, merge remapping, deletion prevention on recovery failure, snapshot immutability/rotation, real StudyHub delete/restore flows, and all twenty primary/accent/button text palettes. Native UI checks found and corrected a restore-sheet presentation issue.

Blocked: actual Developer ID signing/notarization requires the owner's Apple developer certificate and Keychain profile (no valid signing identity is installed). The scripts and release guide are ready; no public release has been uploaded. Complete cross-device/VoiceOver certification is not claimed.

## Original roadmap

All sixteen roadmap features are implemented locally:

1. Today overview — recent work, scheduled tasks, and daily activity.
2. Continue studying — saved card position and per-deck progress.
3. Pins — five favorite decks, notes, tasks, or lists.
4. Quick capture — task, note, or flashcard in one sheet.
5. Command palette — keyboard search across destinations and actions.
6. Focus mode — distraction-free tool layout with Escape to exit.
7. Focus intentions — attach a study item to an interval.
8. Menu-bar timer — optional controls backed by the same app-owned clock.
9. Daily targets — optional focus minutes, cards, or intervals.
10. Study history — local activity and a seven-day chart.
11. Task scheduling — Today/Later and optional date-only deadlines.
12. Confidence review — optional Again/Unsure/Know without locking navigation.
13. Combined decks — temporary sessions with source labels.
14. Notes to cards — selected text pre-fills a reviewed capture form.
15. Full workspace backups — validated export, merge, replace, and recovery.
16. Ambient sounds — theme-style selection tiles, preview, volume, and timer behavior.

## Architecture and safety

StudyHub owns shared stores, routing, audio, and the Pomodoro clock. WorkspaceState keeps optional study metadata separate from the existing content files. Existing task files decode with no scheduling information. Invalid or future-version data is preserved, with saving disabled for the unreadable store.

Notes preserve their existing autosave and native editor behavior. Restore changes the editor generation so callbacks from an old editor cannot overwrite newly imported content. Full imports write a durable rollback journal before replacing files, retain a pre-import archive, and recover interrupted transactions at startup. Merge remaps content IDs and references. Ambient textures are generated locally and do not use third-party recordings.

## Verification

`bash test.sh` checks legacy decoding, confidence/back navigation, resume, event deduplication, pins, targets, scheduling, backup validation/remapping, injected-write rollback, interrupted-import recovery, recovery archive decoding, failed-save retention, and note-editor invalidation. A fixture of 10,000 cards, 500 notes, and 2,000 tasks exercises backup round-tripping.

The optimized app builds and is locally signed. Native UI checks cover Home, palette navigation, quick capture, Notes focus layout, settings, ambient selection/preview, and workspace export. This is not a claim of testing every supported Mac or audio device. Distribution signing/notarization and publishing updated GitHub assets are separate release work.
