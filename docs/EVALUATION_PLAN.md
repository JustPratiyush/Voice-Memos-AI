# IR and NLP evaluation plan

Proposed on 25 October 2026. No results are claimed. Dataset sizes below are pilot estimates, not evidence of sufficient statistical power or fine-tuning data.

## Academic focus

Aim for one measurable NLP task and one measurable IR task integrated into a useful native app. Suggested title: **Context-Aware Conversation Analysis Using Hybrid Retrieval and Personal Memory**. The supplied planning brief reports an assigned theme of context-aware neural IR with transformers; course requirements and dual-course acceptance still require instructor confirmation.

The brief reports 10 project marks in each course and a 2–3-person NLP research-project route. These are inherited notes, not independently reviewed handout conclusions in this repository. A frontend/backend/database does not by itself demonstrate parallel or distributed IR.

## NLP experiment

Question: can a trained classifier identify checkable conversational claims better than a classical baseline?

- Baseline: TF-IDF plus logistic regression.
- Candidate: fine-tuned small pretrained transformer if labels and compute justify it.
- Supporting tasks: entities, ambiguity, commitments, and supporting-span extraction.
- Report precision, recall, F1, confusion/error analysis, and supporting-span accuracy where applicable.

## IR experiment

Question: does contextual hybrid retrieval improve useful evidence and memory retrieval over lexical or dense retrieval alone?

Compare TF-IDF/cosine, BM25, dense embeddings, hybrid retrieval (candidate: reciprocal rank fusion), and optionally hybrid plus reranker. Use the same corpus, queries, and relevance judgments. Evaluate external evidence and memory relevance separately, and retrieval independently of generation. BM25 and advanced rerankers are proposed choices, not asserted course requirements.

## Pilot data and leakage controls

Start with roughly 20–30 consented/scripted conversations, a few hundred labeled utterances, and 100–150 checkable claims. Revisit size after observing class balance, disagreement, and feasibility.

- Separate development/test conversations; hold out speakers or related scenarios where feasible.
- Independently double-annotate a subset and report disagreement.
- Preserve a dated evidence snapshot and distinguish publication from retrieval dates.
- Mark scripted examples as synthetic; report spontaneous-conversation performance separately.
- Keep test annotations and future outcomes out of training and retrieval inputs.
- Do not treat many claims from one conversation as independent user trials.
- Keep private conversations out of the public repository and demonstrations unless separately authorized.

## Measurements

| Component | Proposed measures |
| --- | --- |
| Transcription | WER and targeted errors in names, quantities, dates, negation |
| Claim extraction | Precision/recall/F1 and supporting-span accuracy |
| Retrieval | Recall@10 and nDCG@10 from judged relevance |
| Evidence assessment | Accuracy or macro-F1, uncertainty handling, counterevidence coverage |
| Debrief | Human-checked citation support and unsupported-assertion rate |
| Personal usefulness | Actionability, relevant concerns, unresolved claims/commitments identified |
| Device feasibility | Latency, battery, storage on agreed target hardware |

## Ablations and checks

Compare summary-only, evidence-grounded debrief without memory, and evidence-grounded debrief with approved memory while holding generation model constant. Change preferences while holding claims and evidence fixed: factual verdicts should not change. Evaluate ambiguous references, compound claims, stale or mismatched statistics, uncertain transcription, missing evidence, and contradictory sources.

Report small-study results as preliminary. FEVER is a reference for evidence-based verification, not a replacement for conversational-task evaluation. Agree annotation rules, rating rubrics, and success thresholds before collecting final results.

## Course connections

Speech recognition/multilingual NLP; text classification and transformers; NER and sequence labeling; inverted indexes, term weighting and probabilistic retrieval; ranking comparison; grounded QA/summarization; evaluation, bias and ethics. Rocchio feedback is relevant only if explicit judgments actually modify retrieval.
