# Age of Mythology: Extended Edition — texture remaster

This directory is the reproducibility and review record for an AoM:EE texture-remaster project.

## Review baseline — 2026-09-26

- 7,487 original DDT textures define the source population.
- 7,452 normal textures + 35 recovered exceptions form the extracted source set.
- 7,487 PBRify V4 32-bit masters exist locally.
- The explicit compiler completed 7,486/7,486 production DDTs: zero compile failures, zero warning tokens, one documented Blue Lagoon fallback, and one archive-only Black Tortoise exclusion.
- The current full verifier has 7,471 passing rows, 6 core DDT failures and 9 legacy TextureExtractor-only crashes. The six core failures remain open; the extractor crashes are a secondary compatibility finding.
- Independent-decoder and clean-game runtime validation are still pending.
- Final runtime-resolution normalization is deliberately not locked.

See `docs/PROJECT_STATE.md`, `docs/TECHNICAL_REFERENCE.md`, `docs/EXPERIMENT_LOG.md`, `docs/REPRODUCIBILITY.md`, and `docs/REVIEW_GUIDE.md`.

## What is not committed

The clean game, extracted source, AI model, PBRify masters, generated DDTs, tests, full material XML snapshot and local tools remain outside this review snapshot. This keeps the branch small and avoids developer-specific or retraceable local data.

## Reproduction outline

1. Start with a clean AoM:EE installation.
2. Create the local layout documented in `docs/REPRODUCIBILITY.md`.
3. Obtain the external PBRify V4 model.
4. Run the ChaiNNer 0.25.1 workflow.
5. Run the explicit compiler and core DDT verifier.
6. Validate representative outputs with an independent decoder and then in a disposable clean-game copy.

Canonical scripts resolve paths from the checkout; they do not require the original developer's local path.

## Privacy rule

Committed files should contain repository-relative paths only. No home directory, drive-letter path, cloud-sync path, machine-local log or unnecessary local identifier belongs in a review snapshot.
