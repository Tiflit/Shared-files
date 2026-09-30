# AoMEE repository retention policy

Last reviewed: 2026-09-30

Keep an artifact when it is needed to reproduce the workflow, understand an intentional exception, or rebuild future analysis.

Do not keep an artifact merely because it was generated during an experiment.

## Keep

- Source-lock code and v7 baseline evidence.
- PBRify workflow definitions.
- PBRify SHA-256 manifest and current production QA snapshot.
- Canonical explicit compiler, 16-case canary and v5 DDT verifier.
- TGA, BTI and classification inventories.
- Recovery and legacy-usage evidence.
- Full material XML semantic snapshot locally; do not commit the raw corpus.
- Latest meaningful material, CT4/noalphatest and player-colour research snapshots.
- AoM tools required by the workflow.
- docs/HISTORICAL_TESTS.md as the compact historical record for discarded experiments.

## Regenerate locally

- Clean game files.
- Extracted TGA/BTI trees.
- AI model files.
- PBRify image outputs.
- Production DDT outputs.
- Temporary staging and test outputs.
- Source/PNG staging trees.
- Raw material XML/MTRL corpus.

## Delete when superseded

- Earlier compiler/verifier generations once their findings are incorporated into the technical reference.
- One-off diagnostics whose conclusions are recorded.
- Duplicate reports with identical content.
- Empty, checkpoint-only or missing-only reports.
- Generated logs that do not preserve useful reproducibility information.
- Raw test inputs/outputs after their conclusions are summarized.

## Branch policy

main is the authoritative current branch.

aomee-review-sanitized-2026-09-26 is a compact archival review snapshot and should not be treated as current.

aomee-repo-streamline-pre-ddt is a historical pre-DDT branch. It may retain older evidence for provenance, but it should not be used as a working baseline.

## Source-of-truth order

1. Clean game and extracted source, protected locally.
2. Source-lock v7 evidence.
3. PBRify V4 masters and their SHA-256 manifest.
4. Original authoritative BTI metadata.
5. DDT byte 6 for actual stored format.
6. Full material XML snapshot in the protected local workspace.
7. Current core DDT verification.
8. Derived analysis reports and historical summaries.
