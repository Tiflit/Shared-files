# Age of Mythology: Extended Edition — texture remaster

Sanitized reproducibility/review snapshot, 2026-09-26.

- 7,487 original DDT textures.
- 7,452 normal + 35 recovered exceptions.
- 7,487 local PBRify V4 32-bit masters.
- 7,486/7,486 explicit production DDT compilation; zero compiler failures/warnings; one documented Blue Lagoon BC1→BC2 fallback; one archive-only Black Tortoise exclusion.
- Latest verifier: 7,471 PASS, 6 core DDT failures, 9 legacy TextureExtractor-only crashes.
- Controlled BC2 tests reproduced the legacy extractor crash with both real and synthetic data; the DDTs remained structurally valid. No universal extractor crash rule has been established.
- Independent decoder and clean-game runtime validation remain open.

See `docs/PROJECT_STATE.md`, `docs/TECHNICAL_REFERENCE.md`, `docs/EXPERIMENT_LOG.md`, `docs/EXTRACTOR_CONTROL_FINDINGS.md`, `docs/REPRODUCIBILITY.md`, and `docs/REVIEW_GUIDE.md`.

The repository preserves methodology, decisions, failure modes and review checkpoints without committing the large local game/source trees, AI model, generated production outputs, full material XML corpus, experimental test trees or local binaries. All committed paths are repository-relative.

This branch is intended for external review before further normalization or release work.
