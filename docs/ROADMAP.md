# Roadmap and decision register

Baseline: 25 October 2026. Proposed sequence, not a committed schedule. No new code is authorized by this document.

## Existing foundation

The repository already contains a SwiftUI recorder/editor, audio services, local library, tests, and binary research. Mac validation is documented; iOS runtime validation and full feature parity remain open. Future intelligence work must not be described as already implemented.

## Proposed milestones

| Stage | Intended deliverable | Review before advancing |
| --- | --- | --- |
| 0. Agree scope | Initial scenario/languages, processing boundary, privacy expectations, evaluation plan | Explicit user decisions; instructor agreement if used for coursework |
| 1. Transcript-first debrief | Reviewed transcript/context, editable claims, linked evidence passages, uncertainty-aware debrief, proposed memories | Useful analysis on consented/scripted examples; inspectable citations; success thresholds agreed beforehand |
| 2. Recording integration | Connect native recording/import and selected open-model transcription to the same flow | Device feasibility, transcription errors, alignment, latency/battery/storage measurements |
| 3. Retrieval and memory experiments | Separate evidence/memory indexes, attributable memory controls, baseline comparisons | Held-out evaluation; no leakage; factual judgments invariant to preference changes |
| 4. Broader validation | Spontaneous conversations, error analysis, device testing, documented limitations | Claims proportionate to measured results and sample size |

Academic experiments may run alongside the product milestones; the stage order is not a requirement to postpone baselines.

## Proposed first milestone

Reproduce the useful parts of a manual conversation-analysis workflow from an imported transcript. Permit optional context, review/correction/exclusion of extracted claims, evidence cards with real links and passages, a concise personal debrief, and approval/edit/discard of proposed memories.

Use private examples only with appropriate permission and handling. They are desired-depth examples, not verified answer keys. Use scripted or consented examples for public demonstrations; do not publish source conversations by default.

## Open decisions

| Decision | Current state / next evidence needed |
| --- | --- |
| Product and academic names | Voice Memos-AI repository name established; Second Look and academic title are suggestions |
| Initial scenario | Pitches, collaborations, factual disagreements suggested; no restricted domain selected |
| Language coverage | English–Hindi code-switching relevant; target languages undecided |
| Target device | iPhone model, OS floor, acceptable latency/battery/storage need agreement |
| Speech model | Evaluate open candidates on target-language/device data |
| Processing boundary | Local vs backend; explicitly disclose what leaves the device |
| Memory policy | Approval, correction, history, retention, deletion, cloud behavior undecided |
| Evidence providers | Search/source types, budget, saved corpus, freshness policy undecided |
| Team and schedule | Not selected |
| Academic acceptance | Confirm team rules, instructor expectations, and whether distinct experiments can support both courses |
| Dataset and success thresholds | Agree annotation scope, split strategy, judgments, and usefulness criteria before evaluation |

## Deferred candidates

Universal same-device call capture, live interventions, automatic personality profiles, autonomous actions, and broad political-truth claims are outside the proposed first version. Topic clustering, cross-lingual retrieval, and explicit relevance feedback are possible later extensions. Existing recorder parity work is tracked separately in [PARITY.md](../PARITY.md).

## Change log

- **25 October 2026:** Consolidated supplied planning brief into public-safe project documents. No model, backend, implementation schedule, or product restriction selected. No application code changed.
