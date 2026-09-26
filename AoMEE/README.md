# Age of Mythology: Extended Edition — texture remaster

Sanitized reproducibility/review snapshot, 2026-09-26.

- 7,487 original DDT textures.
- 7,452 normal + 35 recovered exceptions.
- 7,487 PBRify V4 32-bit masters locally.
- 7,486/7,486 explicit production DDT compilation; zero compile failures/warnings; one documented Blue Lagoon BC1→BC2 fallback; one archive-only Black Tortoise exclusion.
- Latest verifier: 7,471 PASS, 6 core DDT failures, 9 legacy TextureExtractor-only crashes.
- Independent decoder and clean-game runtime validation remain open.

See `docs/PROJECT_STATE.md`, `docs/TECHNICAL_REFERENCE.md`, `docs/EXPERIMENT_LOG.md`, `docs/REPRODUCIBILITY.md`, and `docs/REVIEW_GUIDE.md`.

Large local trees, AI model, generated outputs, full material XML, tests and local tools are intentionally not committed. All committed paths are repository-relative.
