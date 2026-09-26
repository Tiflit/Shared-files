# Authoritative project state

Last reviewed: 2026-09-26.

## Objective

Produce a reproducible AoM:EE texture remaster while preserving the original texture population, visual intent, alpha semantics and material relationships. Runtime normalization and release packaging are not locked.

## Source baseline

- 7,487 original DDTs.
- 7,452 normal + 35 recovered exceptions.
- 7,487 logical TGA/BTI pairs in the protected local extraction.
- Black Tortoise is archive-only and excluded from the production candidate.
- Special Gryphon/Griffon recovery remains provisional for runtime reachability.

## PBRify V4

- chaiNNer 0.25.1.
- 4x PBRify V4 model.
- 7,487 local 32-bit TGA masters.
- Exact 4x output dimensions and nearest-neighbour alpha replication were verified.
- 2,295 outputs have max dimension >=1024; 202 >=2048; 7 >=4096; 1,754 are exactly 1024x1024.

## Explicit compile

Authoritative source counts: BC1=3, BC2=9, BC3=4827, DeflatedRGBA8=2559, DeflatedRGB8=89.

Production result: DDT byte 4=1, byte 8=10, byte 9=4827, byte 10=2559, byte 11=89; total 7,486.

Latest compile: expected 7486, compiled 7486, DDTs present 7486, fallbacks 1, failures 0, warnings 0, missing 0, unexpected 0.

## Current verifier

Latest full run: expected 7486, PASS 7471, FAIL 15, CORE FAIL 6, EXTRACTOR FAIL 9.

The six core failures are lower-mip zlib-decode failures in tiny DeflatedRGBA8 files. The nine extractor-only failures pass core checks and then crash the legacy 2014 TextureExtractor. Controlled BC2 tests reproduced the extractor crash with real and synthetic data; no simple stable crash predicate was established.

Core DDT integrity is therefore the primary gate and TextureExtractor is a secondary compatibility test.

## Open work

1. Resolve the six lower-mip DeflatedRGBA8 failures.
2. Validate representative DDTs with an independent decoder.
3. Test the 7,486-D​​DT set in a disposable clean-game copy.
4. Review the seven >=4096 PBRify masters.
5. Build role/family-aware normalization.
6. Revalidate CT4/player-colour/noalphatest semantics.
7. Package only after runtime and reproducibility review.

Do not impose a global 1024 cap.

## Repository boundary

Git is the reproducibility record, not the multi-gigabyte workspace. Clean game, extracted source, model, PBRify masters, generated DDTs, tests/staging and full material XML remain local.
