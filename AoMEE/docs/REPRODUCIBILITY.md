# Reproducibility guide

This repository is a sanitized review snapshot, not a complete redistribution of the game, source assets, AI model or generated production outputs.

## Required local inputs

The reviewer must supply independently:

- a clean, legally obtained AoM:EE installation;
- the AoM texture extraction/compiler tools used by the project;
- the 4x PBRify V4 model (`4x-PBRify_UpscalerV4.pth`);
- the source texture/BTI inputs described by the manifests and project notes.

The canonical upscaling environment was chaiNNer 0.25.1. The committed `pbrify_workflow_sanitized.chn` is a sanitized parameter/path snapshot; it intentionally contains no absolute paths or embedded model. It should be treated as a review record rather than as a guaranteed drop-in chaiNNer graph export.

## Sanitized project layout

```text
AoMEE/
  Age of Mythology/                 # local clean game/source tree; not committed
  extracted/                        # local extraction/recovery outputs; not committed
  input/                            # local source assets; not committed
  models/                           # local AI model; not committed
  processed/                        # local PBRify/DDT outputs; not committed
  reports/materials_xml/            # local material corpus; not committed
  tests/                            # local experimental trees; not committed
  tools/                            # local third-party/project binaries; not committed
  docs/                             # committed methodology and findings
```

All committed project references are repository-relative. The `.gitignore` deliberately excludes the large/private local trees above.

## Reproduction sequence

1. Place the required local inputs under the relative layout above.
2. Run `python verify_repository_hygiene.py` before creating a review snapshot.
3. Extract the source DDT population with `extract_aomee_ddt.ps1` using the local TextureExtractor.
4. Recreate the PBRify V4 4x pass with the documented workflow parameters and verify dimensions/bit depth/alpha replication.
5. Generate compiler sidecar metadata from the authoritative BTIs and use explicit compiler format arguments; do not rely on implicit BTI inference.
6. Compile the production DDTs and compare counts, formats, alpha semantics and output paths against the documented checkpoints.
7. Run the core DDT verifier independently of the legacy TextureExtractor.
8. Treat legacy TextureExtractor crashes as a secondary compatibility result. The controlled BC2 findings are documented in `docs/EXTRACTOR_CONTROL_FINDINGS.md`.
9. Before any release decision, perform independent-decoder validation and a clean-game runtime test.

## Current checkpoints

- Source population: 7,487 original DDTs.
- Extraction/recovery: 7,452 normal + 35 recovered exceptions.
- PBRify V4 masters: 7,487 local 32-bit masters.
- Explicit production compile: 7,486 DDTs, zero compiler failures/warnings, one documented Blue Lagoon fallback and one archive-only Black Tortoise exclusion.
- Latest verifier: 7,471 PASS, 6 core failures and 9 legacy-extractor-only failures.

These are review checkpoints, not claims that the final remaster is release-ready. The six core zlib failures, independent decoding and runtime behavior remain open.
