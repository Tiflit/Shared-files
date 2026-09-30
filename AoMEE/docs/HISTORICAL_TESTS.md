# AoM:EE historical test record

Last reviewed: 2026-09-30

Raw experimental trees were intentionally removed from the Git repository after their useful conclusions were captured. This document is the compact historical record for those discarded tests.

## Compiler format probes

The early compiler-format probe generations established the canonical mapping:

- BC1 → DDT byte 4 with -c BC1.
- BC2 → DDT byte 8 with -c BC2.
- BC3 → DDT byte 9 with -c BC3.
- DeflatedRGBA8 → DDT byte 10 with -c DeflatedRGBA8.
- DeflatedRGB8 → DDT byte 11 only when the compiler receives a true 24-bit TGA through -c DeflatedRGB8.
- The GUI label RGB8 is not the correct CLI argument.
- BTI-only inference is rejected for the Deflated formats.

The retained current verifier/compiler documents encode these findings; the individual probe payloads are not needed for normal reproduction.

## Blue Lagoon compiler diagnostics

textures\ui\ui map blue lagoon.tga was repeatedly tested because the legacy BC1 encoder failed at the 1024×1024 PBRify result.

Controlled content, alpha, dimension, repeatability and parallelism tests did not identify damaged source content as the cause. BC2 succeeded consistently for the affected workload.

Result: Blue Lagoon is the one explicit and allowlisted automatic fallback, BC1→BC2. New compiler failures remain hard failures until independently investigated.

## Tiny DeflatedRGBA8 mip investigation

The first strict full DDT verification found six CORE failures:

    textures\icons\icon settlementminimap 4x4.tga
    textures\ui\blue.tga
    textures\ui\green.tga
    textures\ui\lightblue.tga
    textures\ui\lightgreen.tga
    textures\ui\lightred.tga

All were format-10 DeflatedRGBA8 textures whose generated secondary mip contained a truncated zlib stream.

Controlled staged nomip recompilation produced one-mip DDTs accepted by the official TextureExtractor. The current compiler therefore applies nomip only to these exact assets and the strict verifier remains unchanged.

The final fresh production rebuild now compiles 7,486/7,486 with zero warnings/failures, and the current core-only verifier passes 7,486/7,486.

## Legacy TextureExtractor controls

The 2014 TextureExtractor was tested independently against structurally valid BC2 DDTs.

Important controlled observations included:

| Dimensions | Blocks | Payload | Extractor |
| --- | ---: | ---: | --- |
| 68×64 | 17×16 | 4,352 | PASS |
| 72×64 | 18×16 | 4,608 | FAIL |
| 56×64 | 14×16 | 3,584 | PASS |
| 60×60 | 15×15 | 3,600 | FAIL |
| 61×64 | 16×16 | 4,096 | PASS |
| 64×61 | 16×16 | 4,096 | PASS |
| 63×63 | 16×16 | 4,096 | PASS |
| 128×32 | 32×8 | 4,096 | PASS |
| 128×64 | 32×16 | 8,192 | FAIL |
| 256×256 | 64×64 | 65,536 | FAIL |

The same broad behavior was reproduced with real AoM-derived data and deterministic synthetic/solid-color controls.

These tests ruled out several simple explanations but did not establish the exact crash trigger. Therefore the legacy extractor is a secondary compatibility test, not the primary DDT integrity gate. Independent decoding plus clean-game runtime validation remains required before release.

## PBRify/model comparison tests

The historical model-comparison trees were used to select and validate PBRify V4 against alternative upscalers and visual samples.

The retained project conclusion is that 4x PBRify V4 is the current working/master representation. Raw comparison images are disposable and should not be committed merely to preserve that conclusion.

No final runtime resolution policy was chosen from those visual comparisons.

## Source/recovery and metadata tests

The historical extraction/recovery experiments established:

- 7,487 source DDT textures.
- 7,452 normal extraction pairs.
- 35 recovered exceptions.
- 34 cleanly recovered exceptions.
- special g griffon map.tga remains provisional.
- Black Tortoise is archive-only and excluded from production.

Material/CT4/player-colour experiments remain represented by the current meaningful reports and by the technical reference; superseded indexes and duplicate intermediate reports are removed.

## Cleanup principle

A test artifact stays in Git only when it is itself a current input, current gate output, or uniquely useful reproducibility evidence. Otherwise, preserve the result and delete the payload.
