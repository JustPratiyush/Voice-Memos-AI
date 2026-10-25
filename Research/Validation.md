# Validation record

Work performed October 20–21, 2026, using the installed Swift 6.3.3 toolchain and macOS SDK. The project uses Swift 5 language mode and deployment targets macOS 14 / iOS 17.

## Executed

- `swift build --product VoiceMemosReplica`: Mac executable compiled and linked.
- `Scripts/build-macos.sh --debug`: sandboxed `.app` assembled, Info.plist validated, ad-hoc signature created and verified.
- Native launch of `build/Voice Memos Replica.app`: library, sidebar, toolbar, recording affordance, and empty state rendered.
- Launch with `--demo`: four locally generated audio examples loaded in a separate temporary library.
- Running-app playback: Play became Pause; time advanced; pause retained the current position.
- Playback options: Options displayed speed, Skip Silence, and Enhance Recording. Skip Silence was changed for a demo recording.
- Full-window editor: selected the 28.4-second demo, changed both trim boundaries, and trimmed it to approximately 23 seconds.
- Undo restored the displayed 28-second duration; redo restored the 23-second result.
- Save as New Recording returned to the library with a new 23-second copy; the original 28-second recording remained.
- A space entered into the title field inserted text instead of triggering global playback.
- `Scripts/test-core.sh`: eleven core checks passed; full output is in `core-test-results.txt`.
- Final release build via `Scripts/build-macos.sh` passed with `-strict-concurrency=complete` and no warnings; the ad-hoc signature verified successfully. Build output is in `release-build.txt`.
- Final release launched successfully with `--demo`; the saved edited copy and original loaded, and selecting the original displayed its detailed waveform, overview, and transport.
- Xcode project generation and `plutil -lint` completed. All three target definitions, source references, shared-scheme/workspace XML, and icon asset references passed structural checks. iOS icon PNGs were verified as RGB without alpha.

## Core checks

The standalone runner executes the XCTest test bodies compiled with `CORE_STANDALONE_TESTS`. It does not claim that the XCTest runner itself ran.

1. Audio analysis and silent-region detection.
2. Metadata persistence, folders, title/transcript search, favorites, recovery.
3. Duplicated audio ownership and permanent deletion restricted to trash.
4. Failed metadata write rollback.
5. Corrupt-library preservation.
6. Trash retention boundaries and preservation of active/unexpired items.
7. Path-traversal metadata rejection.
8. Real audio trimming and byte-identical original restoration.
9. Range deletion and replacement, including frequency checks before/inside/after the splice.
10. Separate processed enhancement output and unchanged original.
11. Real playback transport, rate clamping, seeking, and cancellation of asynchronous preparation.

## Limits

- Full Xcode, XCTest SDK, iOS SDKs, and simulator runtimes are absent. No `xcodebuild` or iOS build/runtime result is claimed.
- Microphone, speech, and location permissions were not granted or exercised by the agent. Hardware recording, speech accuracy, and location naming require user/device validation.
- The native file chooser opened, but automation of its Go To Folder overlay was unreliable. Import is covered at the core level; the file-picker path was not verified end to end.
- Share-sheet delivery, iOS interruption/route-change behavior, prolonged recordings, and multiple-device testing remain unverified.
- No app-wide pixel comparison was performed. Measurements and screens guided the implementation, but appearance is not certified identical.
- No Apple user recordings were played, imported, edited, deleted, or sent anywhere. Runtime tests used synthesized demo audio.

## Parent-observed reference UI

The parent inspected the installed Apple app's UI without playing or editing its recordings. Observed states included the folder/sidebar library, unselected placeholder, selected-recording waveform and overview, ±15-second transport, Options, full-window Edit mode, and Trim mode with yellow range handles, Trim/Delete/Cancel/Apply actions. These are runtime observations separate from the static evidence in `BinaryResearch.md`.
