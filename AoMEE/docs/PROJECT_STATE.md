# Project state — 2026-09-26

## Objective
Reproducible AoM:EE texture remaster preserving source population, visual intent, alpha semantics and material relationships. Runtime normalization/release packaging are not locked.

## Source
7,487 original DDTs; 7,452 normal + 35 recovered; 7,487 logical TGA/BTI pairs. Black Tortoise is archive-only. One Gryphon/Griffon recovery remains provisional.

## PBRify V4
chaiNNer 0.25.1, 4x PBRify V4, 7,487 local 32-bit masters. Exact 4x dimensions and nearest-neighbour alpha replication verified. 2,295 outputs >=1024, 202 >=2048, 7 >=4096, 1,754 exactly 1024x1024.

## Explicit compile
Authoritative counts: BC1=3, BC2=9, BC3=4827, DeflatedRGBA8=2559, DeflatedRGB8=89. Production DDT bytes: 4=1, 8=10, 9=4827, 10=2559, 11=89; total 7,486. Compile: 7486/7486, zero failures/warnings, one fallback, no missing/unexpected outputs.

## Verifier
Latest full run: 7,471 PASS, 6 CORE FAIL, 9 EXTRACTOR FAIL. The six core failures are tiny DeflatedRGBA8 lower-mip zlib failures. The nine extractor-only cases pass core checks and then crash the 2014 TextureExtractor. Controlled BC2 tests reproduced this with real and synthetic data; no simple stable crash predicate was established.

Core DDT integrity is the primary gate; TextureExtractor is secondary.

## Open work
Resolve the six zlib failures; independent-decoder validation; clean-game runtime test; review seven >=4096 masters; role/family-aware normalization; CT4/player-colour/noalphatest revalidation; release packaging.

Do not impose a global 1024 cap.
