# AoM:EE Remaster — authoritative project state

Last reviewed: 2026-09-30

## Objective

Remaster the Age of Mythology: Extended Edition texture set while preserving the original texture population, metadata relationships and runtime behavior. The 4x PBRify V4 masters are complete. The explicit DDT compiler is now producing the full intended production set and the strict core verifier passes.

## Locked source baseline

- 7,487 original DDT textures are authoritative.
- 7,487 logical TGA/BTI pairs exist in the locked extraction: 7,452 normal + 35 recovered exceptions.
- The clean game copy and extracted/ tree are protected local reference data.
- Black Tortoise is archive-only and excluded from production.
- special g griffon map.tga remains a provisional recovered exception.

## PBRify baseline

- Canonical workflow: chaiNNer 0.25.1 + 4x-PBRify_UpscalerV4.pth.
- 7,487 PBRify V4 masters exist locally as 32-bit TGAs.
- PBRify masters are never modified for compiler staging.
- The 4x master is retained because runtime normalization has not yet been finalized.

## Current DDT build checkpoint

Fresh explicit production compile on 2026-09-30:

    Expected textures : 7486
    Compiled          : 7486
    DDTs present      : 7486
    Fallbacks         : 1
    Failures          : 0
    Warning tokens    : 0
    Missing DDTs      : 0
    Unexpected DDTs   : 0

Format distribution:

    byte 4  = 1
    byte 8  = 10
    byte 9  = 4827
    byte 10 = 2559
    byte 11 = 89

The one fallback is Blue Lagoon BC1→BC2. The one omitted source asset is the archive-only Black Tortoise texture.

## Known tiny-mip workaround

Exactly six tiny DeflatedRGBA8 assets receive nomip during production staging because the legacy compiler otherwise generates a truncated secondary mip. The six paths are documented in README.md and TECHNICAL_REFERENCE.md.

The workaround affects only staged BTIs. Authoritative BTIs and 4x PBRify masters are untouched. The strict verifier is intentionally unchanged.

## Verification checkpoint

The latest core-only verification is:

    Expected DDTs : 7486
    Final rows    : 7486
    PASS          : 7486
    FAIL          : 0
    CORE FAIL     : 0
    EXTRACTOR SKIP: 7486

This establishes a clean current DDT container/format/payload baseline. The official TextureExtractor run is the next independent decoder checkpoint and is currently in progress.

## Canary checkpoint

The explicit compiler canary is now validated at 16/16 PASS.

The canary covers all five explicit format mappings, Blue Lagoon fallback, the 24-bit RGB8 staging path, and all six NoMip exceptions.

## Expected production distribution

    DDT 4  / BC1             1
    DDT 8  / BC2            10
    DDT 9  / BC3          4827
    DDT 10 / DeflatedRGBA8 2559
    DDT 11 / DeflatedRGB8    89
    TOTAL                  7486

## What remains

1. Complete the official TextureExtractor verification.
2. Copy the resulting DDT set into a disposable clean-game runtime test environment.
3. Validate startup, menus, representative maps, units, UI, effects, shadows and recovered/provisional assets in-game.
4. Perform role-aware/family-aware normalization; do not impose a global 1024 cap.
5. Review the seven >=4096 PBRify outputs individually.
6. Validate CT4/player-colour/noalphatest families after any normalization.
7. Package only after runtime validation and reproducibility checks.

## Repository cleanup checkpoint

On 2026-09-30 the committed raw test trees and superseded one-off compiler/probe artifacts were removed from main. Their important conclusions are retained in:

- docs/HISTORICAL_TESTS.md
- docs/TECHNICAL_REFERENCE.md
- reports/extraction_integrity_gate_v7/
- reports/ddt_full_verification_v5/
- current PBRify SHA/QA records.

Large local source/output/material trees remain local and ignored.

## Fresh-conversation handoff

Authoritative branch: main.

Current local authoritative production output:

    processed\DDT_PBRify_V4_explicit\

Current production compile manifest/log:

    processed\PBRify_V4_explicit_compile_manifest.csv
    processed\PBRify_V4_explicit_compile.log

Current core verification report:

    reports\ddt_full_verification_v5\ddt_full_verification_v5.csv
    reports\ddt_full_verification_v5\ddt_full_verification_v5_summary.txt

Next command after the extractor finishes:

    python .\verify_pbrify_ddt_full_v5.py

Do not begin resolution normalization or performance work until the DDT set passes the decoder/runtime gates.
