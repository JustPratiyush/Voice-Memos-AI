# Voice Memos-AI

A runnable macOS app and shared iPhone/iPad source project, reconstructed from the installed **Voice Memos 3.2 (1380)** binary, REA evidence, and observed Mac interfaces. The implementation uses SwiftUI, AVFoundation, Speech, and CoreLocation. It does not link Apple's private VoiceMemos framework.

**This is a working reconstruction of the core workflows, not a complete or verified one-to-one clone of Apple's entire app.** The remaining differences and validation gaps are listed in [PARITY.md](PARITY.md). No new generative-AI features have been added.

## Run on this Mac

Build the app using the command below, then open **`build/Voice Memos Replica.app`**. Generated app bundles are not committed.

To rebuild with the installed Command Line Tools:

```sh
./Scripts/build-macos.sh
```

The script produces an ad-hoc signed, sandboxed app in `build/`. It does not install it into Applications. Use `--debug` for a debug build.

To inspect an isolated demo library containing locally synthesized audio:

```sh
open -n "build/Voice Memos Replica.app" --args --demo
```

Quit an existing instance before switching between normal and demo modes. A normal launch starts with an empty library. Demo data is kept in this app's temporary directory, separate from normal recordings.

Microphone permission is requested when recording starts. Speech permission is requested only when **Transcribe Recording** is selected. Location permission is requested only after enabling location-based naming and starting a recording.

## Open in Xcode

Open **`VoiceMemosReplica.xcodeproj`**, choose the **VoiceMemosReplica** scheme, and select **My Mac**, an iPhone simulator, or an iPad simulator.

- Deployment targets: macOS 14+, iOS/iPadOS 17+.
- The app is native SwiftUI on macOS; it is not a Catalyst wrapper.
- A separate `VoiceMemosCore` framework supplies audio and storage.
- For a physical iPhone or iPad, select your development team in Signing & Capabilities.
- The shared scheme includes a `VoiceMemosCoreTests` XCTest target.

**Full Xcode and an iOS SDK were not installed in the working environment.** The Mac app was compiled, signed, and run using Command Line Tools. The Xcode project was generated and structurally validated, but `xcodebuild`, XCTest, iOS compilation, simulator execution, and device signing have not been run.

The project generator uses only Python's standard library. After adding or removing source files:

```sh
./Scripts/generate-xcode-project.py
```

## Implemented workflows

- Record, pause, resume, save, cancel; AAC or Apple Lossless capture.
- Metered live waveform, stored peak waveforms, detailed dragging and overview scrubbing.
- Playback, pause, seeking, 15-second skip, 0.5–2× speed, silence skipping.
- Non-destructive speech enhancement using a local filter and noise gate.
- Trim to selection, remove selection, record a replacement, append at the end.
- Preview edits, undo/redo, save a new copy, retain and restore the original audio.
- Rename, duplicate, favorites, custom folders, move, bulk selection.
- Recently Deleted, recovery, explicit permanent deletion, configurable retention including “Immediately.”
- Title and saved-transcript search.
- Audio import, Open With handling, native sharing.
- On-device transcription with explicit unavailable/permission/error states.
- Optional location-based names, recording-quality and appearance settings.
- Desktop three-column navigation, full-window Mac editor, compact iPhone controls, and iPad split navigation.

## Verification

```sh
./Scripts/test-core.sh
```

The standalone runner executes the same test bodies as the XCTest target, using local assertion shims because this machine has no XCTest SDK. Eleven checks passed, including real audio decoding/export, sample-frequency verification of replacement, exact original restoration, persistence, deletion/recovery, corrupt-library protection, and actual playback preparation/cancellation.

The Mac UI was also exercised with an isolated demo library: selection, playback/pause, playback options, trim, undo, redo, and save-as-new. See [Research/Validation.md](Research/Validation.md) for precise coverage and limitations.

## Layout and binary evidence

[Research/BinaryResearch.md](Research/BinaryResearch.md) records the target hash, REA version, Evidence IDs, inspected classes/selectors, decoded resources, disassembly-derived measurements, and official iOS references.

Examples incorporated into the UI include a 48-point overview waveform, 4-point waveform spacing, 1-point bars, a 32-point time label, and a 976-point minimum desktop width. UIKit/Catalyst measurements do not guarantee identical native SwiftUI rendering.

REA's source repository remains unchanged. The analysis used REA 6.7.0, matching the supplied repository version, plus Apple's installed binary tools. No Hopper/Ghidra/IDA provider was installed, so full method-body decompilation was not performed.

## Storage and extension points

Normal recordings live in `Application Support/dev.recreation.VoiceMemos` inside the app's sandbox container. `Library.json` contains recording/folder metadata; `Recordings/` contains owned audio files. The app never opens Apple's Voice Memos database or its private iCloud container.

The store publishes changes only after an atomic metadata write succeeds. Corrupt or unsupported metadata makes the library read-only instead of overwriting it. Original audio survives edits until the recording is permanently deleted.

- `Sources/VoiceMemosCore/LibraryStore.swift`: persistence and recording operations.
- `Sources/VoiceMemosCore/AudioController.swift`: capture and transport.
- `Sources/VoiceMemosCore/AudioAnalysis.swift`: waveforms, silence detection, enhancement.
- `Sources/VoiceMemosCore/EditingService.swift`: temporary-file audio composition.
- `Sources/VoiceMemosCore/TranscriptionService.swift`: on-device Speech recognition.
- `Sources/VoiceMemosApp/`: SwiftUI screens and application state.

Future AI functionality can consume an owned recording URL and store additional metadata without changing the audio capture or editing implementations.

The icon is original vector-drawn artwork generated by `Scripts/render-icon.swift`; no Apple icon or extracted image is bundled.
