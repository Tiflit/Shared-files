# AoMEE repository retention policy

Keep an artifact when it is needed to reproduce the workflow, understand an intentional exception, or rebuild future analysis.

Do not keep an artifact merely because it was generated during an experiment.

## Keep

- Source-lock code and v7 baseline evidence.
- PBRify workflow definitions.
- PBRify SHA-256 manifest and production QA snapshot.
- Canonical compiler, canary and DDT verifier.
- TGA, BTI and classification inventories.
- Recovery and legacy-usage evidence.
- Full material XML semantic snapshot.
- Latest meaningful material, CT4, noalphatest and player-colour research snapshots.
- AoM tools required by the workflow.

## Regenerate locally

- Clean game files.
- Extracted TGA/BTI trees.
- AI model files.
- PBRify image outputs.
- Production DDT outputs.
- Temporary staging and test outputs.
- Source/PNG staging trees.

## Delete when superseded

- Earlier revisions of a compiler or verifier after their findings are incorporated into the technical reference.
- One-off diagnostics whose conclusions are recorded.
- Duplicate reports with identical content.
- Empty or missing-only reports.
- Generated logs that do not preserve useful reproducibility information.

## Source-of-truth order

1. Clean game and extracted source, protected locally.
2. Source-lock v7 evidence.
3. PBRify V4 master and its SHA-256 manifest.
4. Original authoritative BTI metadata.
5. DDT byte 6 for actual stored format.
6. Full material XML snapshot.
7. Derived analysis reports.