# Parity and remaining work

The installed reference is Voice Memos 3.2 (1380) on macOS 26.6.2. Its binary is a mixed UIKit/Catalyst, Objective-C, and Swift implementation. This project implements a native SwiftUI interpretation using public APIs.

| Area | Current result | Remaining gap |
| --- | --- | --- |
| Mac library and playback | Implemented and exercised in the running app | No exhaustive screenshot/state comparison; SwiftUI toolbar, sheet, typography, and scaling differences remain |
| iPhone / iPad | Adaptive source and native Xcode targets | No iOS binary, SDK, simulator, or device was available; compilation and runtime validation remain outstanding |
| Capture | AVAudioRecorder, pause/resume, AAC/ALAC, metering, permission/error handling | Microphone permission and physical capture were not exercised; no acoustic comparison or hardware matrix |
| Playback | Real AVAudioPlayer transport, seeking, rate, ±15 seconds | No headphones/Bluetooth/background/lock-screen device matrix |
| Trim, delete range, replace, append | Real exported audio; original retention; undo/redo; save-as-new | Exports use AAC/M4A, including edits of lossless input; no sample-exact equivalence with Apple's editing engine |
| Enhancement | Real high-/low-pass filtering and smoothed noise gate | Apple's private enhancement algorithm is not recovered or reproduced |
| Skip Silence | Measured RMS threshold and silent-region skipping | Apple's thresholds, edge timing, and DSP are unknown |
| Transcription | Public Speech framework, on-device only, saved-text search and sharing | Requires supported device/language/models; no word alignment, live capture transcript, transcript-driven seeking, or accuracy equivalence |
| Folders / favorites / duplicate / trash | Local persistent operations and recovery | Exact Apple bulk interaction and folder-delete transaction behavior is not fully reproduced |
| Settings | Quality, retention, location naming, appearance; retention on launch/reactivation/preference change and immediate removal when selected | Location naming defaults off here; Apple's default is on |
| Sharing / import | Native ShareLink, audio importer, Open With handler | No special spatial/layer export choices; shares the stored file without baking playback-only effects |
| iCloud sync | Not implemented | Requires a separately provisioned container, identity, sync/conflict design, and multi-device tests; Apple's private container cannot be reused |
| Spatial audio / Studio Voice | Not implemented | Supported-device capture and rendering, spatial metadata, and Apple's private audio behavior are unresolved |
| Layered recording | Not implemented | Multitrack capture, mixing, separation, playback controls, and compatible export are unresolved |
| Watch / continuity | Not implemented | No watchOS app, watch-import integration, or continuity implementation |
| Widgets / App Intents / Spotlight | Not implemented | Separate extension targets and system integration testing remain |
| Localization / accessibility | System labels and adjustable waveform controls | English only; no comprehensive VoiceOver, keyboard, Dynamic Type, RTL, or localization audit |
| Lifecycle recovery | Permission cancellation, interrupted-capture save path, playback preparation cancellation | No crash/relaunch recovery of an in-progress capture and no full termination/background stress testing |

The evidence supports individual layout measurements and feature vocabulary. It does not establish recovered source, whole-program equivalence, or a completed reproduction of every device-specific feature.

To reach whole-app parity, the next required inputs are full Xcode with iOS runtimes, a supported iPhone for spatial/layered capture, and developer signing/iCloud provisioning. Deeper binary analysis and a version-specific state-by-state comparison would also be needed before describing the recreation as exact.
