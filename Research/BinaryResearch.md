# Voice Memos binary and resource investigation

Observed on 2026-10-20. This is an evidence ledger, not a claim that Apple's source code or all runtime behavior was recovered.

Raw capture filenames below refer to local investigation artifacts. Bulk disassembly, extracted resources, and machine-specific logs are intentionally excluded from the public repository; this authored evidence summary is included.

## Target identity and boundary

The inspected target is `/System/Applications/VoiceMemos.app`, bundle identifier `com.apple.VoiceMemos`, version **3.2 (1380)**, on macOS **26.6.2 (25G83)**.

The main executable is 6,514,016 bytes, SHA-256 `d1fbc6dadbdfeb08c98efdc88de6d440f9cc8c90dfe15d23861a77c236c43f75`. It is a universal Mach-O containing x86_64 and arm64e. REA selected arm64e, slice offset 3,211,264, UUID `494E4CF5-6A70-3C94-B0EB-8358542C0B55`, platform `MACCATALYST`, minimum OS and SDK 26.6.

The binary uses UIKit, AppKit, SwiftUI, AVFoundation/AVFAudio, AudioToolbox, CoreData, CloudKit, Speech, AppIntents, WidgetKit, and Apple's private VoiceMemos framework. The original is a mixed Objective-C/Swift Catalyst app; a fresh SwiftUI app reproduces its observable behavior using a different implementation.

No iOS application binary or simulator was supplied. iOS interaction references below come from Apple's versioned iOS 26 documentation and shared names in the Mac artifact. They are not iOS binary observations.

## REA use and provenance

Read the supplied repository's `AGENTS.md`, `.agents/skills/reverse-engineer-anything/SKILL.md`, its native/artifact and connection guides, and CLI source contracts. The local repository reports REA 6.7.0. Its source tree had no built runtime. The published **REA 6.7.0** runtime was obtained through `npx`, matching that repository version, and invoked from the npm cache. No global installation, REA source change, or client configuration change was made.

`rea doctor --client codex --json` reports missing Hopper/Ghidra/IDA/Kuna and absent/stale client registration. The independent native-macos inspection utilities nevertheless completed artifact, Mach-O, Objective-C dispatch, plist, signature, and asset catalog inspection. No deep decompiler database was opened; each CLI workflow closed its own session.

| File | Operation / evidence ID | Coverage |
| --- | --- | --- |
| `rea-artifact.json` | `inspect_artifact`, `ev_b77cf723769ba5b80f8ee271f04fc8b5cb50f3da2d2a822a6523a974f8b77867` | Bundle inventory; directory identity is not the executable digest |
| `rea-macho.json` | `inspect_macho`, `ev_a24f271e9ec48f2e2b894110fc69a695474c778ba6f2f21d8fce75a90310dcf2` | Selected arm64e layout, dependencies, symbols, metadata |
| `rea-dispatch.json` | `inspect_native_dispatch_metadata`, `ev_88472568d8773dd9f24034e7a97e96e4be61bed89b6e69e5d719d6d595fbc612` | Partial, 20,000-record bound reached; unresolved Swift metadata/ivars preserved |
| `rea-assets.json` | `inspect_asset_catalog`, `ev_d0ee01a181c3f24cc53cfe8e023b171015b9e86aa447686184bcdbe190700b10` | 114 metadata records; image bytes not extracted |
| `rea-plist.json` | `inspect_plist`; ID in file | Info.plist facts |
| `rea-signature.json` | `inspect_signature`; ID in file | Signing and entitlements |
| `rea-doctor.json` | Read-only environment diagnosis | Explains unavailable deep providers |

Additional evidence:

- `otool-arm64e-disassembly.txt`: Apple `otool -arch arm64e -tvV`, static instructions, no target execution.
- `otool-objc-stubs.txt` and `otool-objc-selrefs.txt`: Objective-C call-stub and selector-reference sections.
- `otool-dependencies.txt`, `otool-load-commands.txt`: Apple tool cross-checks.
- `localizations-en.json`: English dictionary decoded with Python `plistlib` from `Contents/Resources/Localizable.loctable`.
- `Resources-Localizable.loctable.json`: full decoded localization table.
- `Settings.bundle-Root.plist.json`: parsed settings declarations.
- `dispatch-selected-classes.json`: focused projection of REA metadata.
- `style-constants-derived.json`: 108 simple constant-return methods with instruction text and original-file ranges for loaded constants.
- `style-context-disassembly.json`: conditional style methods whose branches require interpretation.
- `source-manifest.json`: source/output hashes and collection details.

## Feature ledger

The first column describes the reconstruction surface. Selector presence and localization strings establish implementation vocabulary; they do not establish that every option is enabled on every device or every state.

| Surface | Binary/resource anchors | Conclusion and remaining gap |
| --- | --- | --- |
| Record, pause, resume, replace | `RCMainViewController`: `startNewRecordingAction`, `toggleRecording`, `pauseRecording`, `resumeRecording:`, `replaceRecording:`, `endRecording`; `RCRecordingView` state properties | Capture/edit state paths are present. Sample rate, exact audio session options, replacement transaction implementation remain unknown. |
| Playback and seeking | `playRecording`, `stopPlayback`, `jumpSelectionForward`, `jumpSelectionBackward`, `setCurrentTime:withUUID:`; `RCWaveformViewController` scrubbing/zoom/current-time properties | Separate playback/detail waveform/overview mechanisms. Apple's guide confirms 15-second skip controls. Exact timing and waveform rendering algorithm not recovered. |
| Trim/delete selection | `exitTrimMode`, `cancelTrimMode`, `_openForModifyRecordingWithUUID:enterTrim:`, selectedTimeRange, `canSaveTrimChanges`, `shouldSaveAsNew`; trim/delete localization keys | Select a range; trim retains it, delete removes it; original or new recording choices. Undo is present. No claim of Apple's edit engine reimplementation. |
| Library/folders | `RCApplicationModel`: `voiceMemosRecordingsFolder`, `capturedOnWatchRecordingsFolder`, `favoriteRecordingsFolder`, `recentlyDeletedRecordingsFolder`, `userFolders`; move/delete methods | Built-in and custom folder model. Folder deletion has variants deleting recordings or permanently erasing them. Watch/Music Memos visibility may depend on content. |
| Favorites | `setFavorite:forRecordingWithUUID:`, `toggleFavoriteForUUID:`, `currentSelectionIsFavorite`; Favorite/Unfavorite keys | Favorite is recording metadata; Favorites is a built-in filter. |
| Rename/search | `performRenameWithNewTitle:forUUID:`, `renameFolder:toName:`; title/transcript search placeholders | Search UI supports titles and transcripts when transcription is available. Locale-sensitive matching/ranking are unknown. |
| Duplicate/share | `duplicateRecording`, `shareRecording:`, `RCCopyTranscriptActivity`, `RCMoveToFolderActivity`; copy suffix and export options | Recording duplication, share sheet, transcript copy, move actions exist. Codec/container and effect baking need runtime comparison. |
| Recently Deleted | `deleteRecordingsWithUUIDs:...`, recover/erase confirmation methods, `performClearAllRecentlyDeleted` | Soft delete, recover selected/all, erase selected/all. Settings declare 30-day default. |
| Playback options | `setEnhanced:forUUID:`, `setRemoveSilence:forUUID:`, `setPlaybackSpeed:forUUID:`, `setLayerMix:forUUID:`, speech-isolator setters | Per-recording speed, enhance, silence skipping, layer mix, Studio Voice. Exact DSP/skip thresholds/slider speed mapping not recovered. |
| Spatial/Studio Voice | `hasSpatialRecording`, `currentSelectionHasSpatialRecording`, localized restrictions | Studio Voice applies only to spatial recordings. Enhance and Skip Silence cannot be enabled for spatial recordings according to packaged messages. Device-specific capability needs runtime verification. |
| Layers | `separateRecordingLayers:`, `hasMultipleTracks`, layer record/replace/resume labels and share export modes | Layer playback, mix, separation, and sharing vocabulary. Apple guide says layer recording is on supported iPhones; do not assume Mac capture supports it. |
| Transcription | `RCLiveTranscription`, `RCRecordingTranscriptionService`, Swift `TranscriptView`/`TranscriptionCompiler`, `toggleTranscriptView`, `copyTranscript:` | Transcript UI and live transcription infrastructure. Apple's private model, availability decisions, download behavior, accuracy, and word alignment are not recovered. |
| Settings | Root.plist preference specifiers | Clear Deleted choices 0/1/7/30/-1 days, default 30; Audio Quality 0/1 (Lossy/Lossless), default 0; location-based naming default true. |
| App extensions | Bundle inventory | Record widget, Settings widget, Intents extension, Spotlight index extension are bundled. Their full behavior has not been reconstructed. |
| iCloud/continuity | CloudKit imports, app group/iCloud entitlements, localization strings, Apple documentation | Original integrates Apple services. A separate bundle cannot adopt Apple's private container or identity. No Apple account data was read. |

## Static style measurements

These derive from REA's method addresses and original arm64e instruction bytes. They are conditional implementation facts, not a pixel-equivalence test. Sizes are UIKit logical points; Catalyst's final desktop scaling and layout can alter observed screen pixels.

Straight-line methods were accepted only when every instruction could be interpreted as `adrp`, `ldr dN`, `mov`, `fmov`, and `ret`, with no calls/branches. All instruction lines and file ranges are retained in `style-constants-derived.json`.

| Selector | Returned value |
| --- | --- |
| `overviewWaveformHeight` | 48 |
| `overviewWaveformCornerRadius` | 4 |
| `waveformWaveWidth` / `overviewWaveformWaveWidth` | 1 |
| `waveformWaveVerticalPadding` / overview counterpart | 10 |
| `toolbarContainerHeight` | 50 |
| `libraryCellDescriptionHeight` | 60 |
| `recordingCellStackViewVerticalLayoutMargin` | 11 |
| `descriptionCompactViewTitleToSecondaryPadding` | 5 |
| `transcriptViewHorizontalMargins` | 24 |
| `centerContentTranscriptViewWidthMultiplier` | 0.85 |
| `timeLineTickWidth` | 1 |
| major / minor tick height | 10 / 5 |
| `selectionOverlayBorderWidth` | 2 |
| `selectionKnobRadius` | 3.5 |
| `trimHandleCornerRadius` | 4 |
| `minimumSecondaryColumnWidth` | 384 |
| `splitViewSeparatorWidth` | 0.5 |
| `playbackViewWidthToCollapseToolbarButtons` | 500 |
| `recordingControlAnimationDuration` / transport duration | 0.2 seconds |
| `recordingControlAlphaWhenPressed` | 0.5 |
| `playbackSettingsCollectionViewCellMinHeight` | 50 |
| `centerClusterWidthLibrary` | 165 |
| `libraryCenterClusterControlSize` | 55 × 66 |

Conditional style derivations:

- Call stub `0x1001b85c0` loads selector slot `0x1002a66f8`. Chained pointer `0x80000001f65eb` resolves to the `__objc_methname` string `_isIOSMac` at `0x1001f65eb`. This is the branch predicate used by the methods below.
- `minimumSceneSize` at `0x10000b60c` selects **976 × 500** when `_isIOSMac` is true, **0 × 700** otherwise. Constants are at `0x100227b28`, `0x100227b30`, `0x100227b38`.
- `recordButtonHeight` at `0x10000c4f0`: **44** on the Mac branch, **60** on the other branch.
- `recordButtonOuterStrokeWidth` at `0x10000c520`: **2** on the Mac branch, **4** otherwise.
- `playbackViewTimeLabelFont` at `0x10000bf58`: Mac branch loads UIFont and UIFontWeightBold, supplies size **32**; non-Mac branch uses the LargeTitle text style's point size.
- `playbackViewTimeSectionHeight` at `0x10000c018`: **116** on Mac, **70** otherwise.
- `sidebarCollectionViewTopPadding` at `0x10000dc24`: **7** on Mac, **0** otherwise.
- `descriptionViewScalableTitleFontForRecordingCollectionViewCell`: Mac selects Headline, non-Mac Body, and both load Semibold.
- `descriptionViewScalableTitleFontForCardView`: Mac selects Title3, non-Mac Title2, and both load Bold.
- `waveformHorizontalSpacing` calls the selector `waveformWaveWidth` (stub `0x1001d74a0`, slot `0x1002ae2b0`, string `0x100219cbf`) and adds 3, yielding **4** for the observed width method.

## Architecture map

REA decoded 450 Objective-C class/metaclass records, 116 protocol records, 16 categories, 4,906 dispatch implementations, 1,329 ivars, 26 Swift conformances, and 71 Swift dispatch slots. These are returned record counts, not an exhaustive type inventory. Dispatch coverage reached its configured maximum and reports unresolved Swift records.

- `RCMainViewController` coordinates browsing, recording, editing, playback, selection, confirmations, folders, and undo.
- `RCApplicationModel` extends `RCSavedRecordingsModel`; `RCRecordingsModelInteractor` mediates model operations.
- `RCFoldersCollectionViewController` and `RCRecordingsCollectionViewController` provide collection-based navigation and recording rows.
- `RCRecordingViewController`, `RCRecordingCardViewController`, and `RCPlaybackViewController` own recording/editor/card/playback surfaces.
- `RCWaveformViewController` and rendering/selection-overlay classes maintain time ranges, zoom, playheads, and selections.
- `RCPlaybackSettingsCollectionViewController` and switch/slider cells expose effect controls.
- Swift transcript hosting views and compiler/service classes coexist with this UIKit structure.

A reconstruction may use a SwiftUI navigation model, a persistent recording store, an AVFoundation audio service, and a waveform view. That is an implementation design choice, not recovered Apple source.

## Public iOS/macOS references

Version-pinned Apple references were read on 2026-10-20:

- [macOS 26 playback](https://support.apple.com/guide/voice-memos/play-a-recording-vma2c8c0a040/3.2/mac/26): playback, seeking, effects, layer mix, spatial capability boundaries.
- [iOS 26 recording](https://support.apple.com/guide/iphone/iph4d2a39a3b/26/ios/26): basic recording, pause/resume, recording modes.
- [iOS 26 edit/delete](https://support.apple.com/guide/iphone/edit-or-delete-a-recording-iphc9bdaee83/26/ios/26): yellow range handles, trim versus removal, replacement, save choices, recovery.
- [iOS 26 playback](https://support.apple.com/guide/iphone/play-it-back-iphebbd067ce/26/ios/26): playback controls and options.
- [macOS 26 shortcuts](https://support.apple.com/guide/voice-memos/keyboard-shortcuts-vm5b49792b0d/3.2/mac/26): Cmd-N record, Space play/pause, Cmd-D duplicate, Cmd-T trim, Delete, Cmd-S save, Cmd-left/right skip, Cmd-Z undo, Shift-Cmd-Z redo, Cmd-comma settings, Control-Cmd-S sidebar.

## Coverage and unresolved work

| Question | Status |
| --- | --- |
| Identify installed Mac artifact and architecture | Answered |
| Recover resource labels, settings defaults, asset names | Answered within packaged files inspected |
| Map core feature entry points | Partially answered through metadata/resources |
| Recover useful exact layout constants | Partially answered; 108 simple methods plus selected conditional methods |
| Recover full algorithms/pseudocode | Unresolved; no deep analysis provider |
| Verify runtime UI/state behavior | Outside this worker's scope; parent performs app observation |
| Establish iOS binary parity | Unresolved; no iOS binary/runtime |
| Reproduce private DSP, sync, spatial capture, widgets, indexing | Unresolved |
| Prove visual or behavioral equivalence of a new app | Unresolved; requires a full state matrix and device testing |

No private user recordings, transcript contents, Apple account data, or Voice Memos database rows were read.
