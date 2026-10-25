# Project memory

Updated: 25 October 2026. Durable project context for future contributors and coding sessions.

## Current instruction

This update is planning and documentation only. Do not interpret this roadmap as authorization to start implementing AI features. Begin implementation only when requested.

## Identity and intent

- Repository/project name: **Voice Memos-AI**. **Second Look** is an unconfirmed product-name suggestion.
- Existing foundation: native SwiftUI macOS recorder and shared iOS source. Mac core workflows have been exercised; full Apple Voice Memos parity and iOS runtime validation remain incomplete. See [PARITY.md](PARITY.md).
- Future product: an iOS conversation and voice-memo app that uses an open transcription model, researches important statements, retrieves relevant approved personal context, and produces an evidence-grounded personal debrief.
- The output should help users understand what matters, what evidence supports, how it relates to their goals, what they may be overlooking, and what to do next.
- Meaningful, separately evaluated IR and NLP work is a core goal, alongside personal usefulness and a credible portfolio project.
- No open speech model, research backend, retrieval pipeline, or personal-memory system has been selected or implemented. The current Apple Speech transcription service is existing infrastructure, not the final open-model choice.

## Preserve these distinctions

- Explicit goals are not the same as recommended implementation choices.
- A speaker's recorded agreement is not automatically the user's belief or preference.
- Keep recorded statements, user explanations, approved goals/preferences, external evidence, and AI interpretations separate.
- Personalization changes relevance and recommendations, **not factual verdicts** for the same claim and evidence.
- Repeated assertions and agreement between AI models are not independent evidence.
- Prefer inspectable evidence and acknowledged uncertainty over confident unsupported advice.
- Private example conversations are not public datasets, verified answer keys, or permission to publish participant information.

## Recommended next milestone — not yet accepted scope

Start with an imported transcript: review text/context, correct extracted claims, inspect evidence cards, read a personal debrief, and review proposed memories. Connect recording and open-model transcription afterward. The existing recorder remains the foundation; this is a recommendation for validating analysis usefulness, not a decision to abandon native UI work.

## Open choices

Product name; initial scenarios and languages; target devices; local/backend boundary; models; search provider and budget; memory approval/retention/deletion; team and timeline; course acceptance; evaluation data and success thresholds. Startup/collaboration scenarios and English–Hindi code-switching are candidates, not restrictions.

## Reading order

1. [Product brief](docs/PRODUCT_BRIEF.md)
2. [Roadmap and open decisions](docs/ROADMAP.md)
3. [Research and evaluation plan](docs/EVALUATION_PLAN.md)
4. [Planning provenance](docs/PLANNING_SOURCES.md)
5. [Existing implementation limits](PARITY.md)

This file preserves project context in the repository; it is not a claim that any assistant has permanent cross-chat memory. Update it when the user makes decisions, with dates and explicit status changes.
