# Personal conversation intelligence

Planning baseline: 25 October 2026. Project: **Voice Memos-AI**.

This document captures future intent. It does not claim that the proposed intelligence features exist or have been evaluated. For the current recorder implementation, see the [README](../README.md) and [parity record](../PARITY.md).

## Product purpose

An iOS app records or imports voice memos and conversations, transcribes them with an open model, and helps answer:

> Given what was said, the available evidence, and what matters to me, what should I understand—and what should I do next?

Go beyond summaries: identify important claims, investigate them, connect them to relevant approved personal context, explain implications, and surface unresolved questions. Support independent judgment rather than persuasion toward a predetermined conclusion.

## Decision status

| Item | Status |
| --- | --- |
| iOS voice-memo/conversation experience | Explicit goal |
| Open-model transcription | Explicit goal; model undecided |
| Fact-checking and analysis beyond summaries | Explicit goal |
| Personal context and memory | Explicit goal; behavior undecided |
| Substantial IR/NLP implementation and evaluation | Explicit goal |
| Evidence-linked personal debrief | Recommended primary output |
| Reviewable claims and proposed memories | Recommended design |
| Local transcription plus backend research | Candidate architecture |
| Startup pitches/collaboration proposals first | Suggested scope, not an agreed restriction |
| Second Look | Suggested name, not selected |

## Proposed experience

1. **Record or import.** Support recordings, audio imports, and transcripts. Recommend participant consent and an unambiguous recording indicator. Universal capture of another app's call on the same iPhone is outside the proposed first version; platform constraints need checking during implementation.
2. **Review transcript and context.** Show speaker labels, timestamps, editable text, and playback at the relevant passage. Check uncertain names, quantities, dates, and negations. Allow explicit user context about intentions or circumstances; do not invent it from tone.
3. **Review extracted statements.** Let users correct, exclude, or clarify the items selected for analysis.
4. **Research and assess.** Retrieve evidence and counterevidence with appropriate dates and scope; retrieve relevant approved memories separately.
5. **Read a personal debrief.** Start with a short overview and expand into claim cards, citations, transcript excerpts, and possible next steps.
6. **Review proposed memories.** Offer a small number of goals, constraints, decisions, commitments, or open questions to accept, edit, or discard.

## Statement treatment

| Type | Treatment |
| --- | --- |
| Checkable factual claim | Retrieve evidence and assess support |
| Causal claim | Assess the causal connection, not just correlation |
| Prediction | Identify assumptions and uncertainty |
| Value judgment | Explain priorities and tradeoffs |
| Personal experience | Preserve speaker attribution; separate from generalizations |
| Proposal/commitment | Extract responsibilities, conditions, deadlines, and unresolved terms |
| Ambiguous reference | Ask for clarification or leave unresolved |

Split compound claims. Match evidence to the precise entity, quantity, time period, and geography. Absence of evidence does not establish falsity; a relevant search result does not establish truth.

## Debrief contract

Answer what matters, what the evidence supports, how it relates to the user, what may be overlooked, and what remains to be done. Assessments should follow:

> My assessment is X, because of Y. Z would change it.

Possible factual labels: supported, contradicted, insufficient evidence, mixed, and needs clarification. Predictions and values require separate treatment. Check every speaker, including the user. Describe arguments without inferring enduring personality traits, private motives, or diagnoses from one exchange.

## Evidence record

Retain original wording, speaker, transcript location/audio timestamp, atomic interpretation, entities/quantities/dates/geography, and unresolved ambiguity. Preserve search queries, supporting and contradicting passages, source URL/publisher/publication date when available, retrieval date, assessment, limitations, and correction history. Citations must support the actual conclusion.

Start research experiments with a saved, curated evidence collection, then consider live search. Avoid sending unnecessary personal names or full private conversations to external search services.

## Memory contract

| Category | Meaning |
| --- | --- |
| Recorded statement | A speaker said something in a specific conversation |
| User-provided context | The user's explanation of intent or experience |
| Confirmed preference/goal | Explicitly approved information for future personalization |
| External evidence | A source supports a claim within a stated scope and period |
| AI interpretation | A tentative assessment, not an established personal fact |

Preserve provenance and dates; support correction and deletion. Review changed preferences instead of silently rewriting history. Repetition must not turn an assertion into a fact. Personalization changes relevance and recommendations, not factual judgments when claim and evidence are fixed.

## Candidate architecture

Record/import → editable, attributed transcript → claim/entity/proposal extraction → separate personal-memory and external-evidence retrieval → evidence assessment → sourced debrief → user-reviewed memory updates.

Native SwiftUI can own capture, playback, review, and controls. A speech model can supply transcription/alignment. An analysis service can orchestrate extraction, retrieval, and generation. Lexical and embedding indexes can manage memories and evidence separately. Storage needs ownership, provenance, retention, and deletion controls.

Whisper/WhisperKit and Gemma 3n were discussed as candidates; none has been selected or benchmarked. Whisper and Wispr Flow are different projects. Local transcription does not make the entire pipeline local if subsequent processing sends transcripts or memories to a backend.

## Differentiation

The intended distinction is an inspectable connection between conversation, approved memory, external evidence, and recommendations, backed by measured performance. Memory plus advice alone is not a claimed world-first invention. Portfolio claims should reflect implementation, experiments, error analysis, and limitations.
