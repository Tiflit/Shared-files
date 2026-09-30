# AoM:EE technical reference

Last reviewed: 2026-09-30

## 1. Locked source baseline

The v7 source gate is the canonical source-integrity record.

Clean installation and historical inventory reconcile at 7,487 DDTs. The extracted population is 7,452 normal plus 35 recovered exceptions. All 7,487 logical textures have paired TGA and BTI records.

Do not modify Age of Mythology/ or extracted/ during development.

## 2. PBRify V4

The chosen AI master is 4x-PBRify_UpscalerV4.pth through chaiNNer 0.25.1.

The master is deliberately kept at 4x resolution even though the final runtime resolution is not yet decided. This lets later stages normalize large, uneven or family-inconsistent assets without re-running AI inference.

Alpha is separated before AI processing and restored with exact nearest-neighbour 4x replication.

Observed output snapshot:

- 7,487 outputs.
- 2,295 with max dimension >= 1024.
- 202 with max dimension >= 2048.
- 7 with max dimension >= 4096.
- 1,754 at 1024×1024.

## 3. DDT format semantics

From the reference AoM tooling source:

    format 4  = Dxt1
    format 5  = Dxt1Alpha
    format 6  = Dxt3Swizzled
    format 8  = BC2
    format 9  = BC3
    format 10 = RgbaDeflated
    format 11 = RgbDeflated
    format 12 = AlphaDeflated
    format 13 = RgDeflated

DDT fixed header:

    bytes 0..3   RTS3
    byte  4      properties
    byte  5      alpha bits
    byte  6      format
    byte  7      mip count
    bytes 8..11  width
    bytes 12..15 height

Offset 16 is the beginning of the image-entry table. It is not a header-size field.

Each entry stores an offset and size. For compressed block formats, the expected size is based on 4×4 blocks: 8 bytes per block for BC1 and 16 bytes per block for BC2/BC3.

For DeflatedRGBA8 and DeflatedRGB8, the payload is zlib-compressed raw RGBA8/RGB8 data. Expected raw byte counts are width×height×4 and width×height×3 respectively.

## 4. Canonical explicit compiler mapping

| Source BTI | Compiler argument | Compile input | DDT byte 6 |
| --- | --- | --- | ---: |
| BC1 | -c BC1 | 32-bit TGA | 4 |
| BC2 | -c BC2 | 32-bit TGA | 8 |
| BC3 | -c BC3 | 32-bit TGA | 9 |
| DeflatedRGBA8 | -c DeflatedRGBA8 | 32-bit TGA | 10 |
| DeflatedRGB8 | -c DeflatedRGB8 | temporary true 24-bit TGA | 11 |

The GUI label RGB8 maps to CLI DeflatedRGB8.

Never rely on BTI inference for the Deflated formats: metadata-only compilation silently selected the wrong DDT format.

## 5. BTI and staging hygiene

The legacy compiler emitted an unhandled-token warning when staged BTI files were BOM-prefixed. Staged BTIs are therefore written as UTF-8 without a BOM.

For DeflatedRGB8, only a temporary 24-bit TGA is created. The authoritative 32-bit PBRify master is never changed in place.

## 6. Tiny DeflatedRGBA8 NoMip workaround

The first strict verification of the original full compile found six core failures. All six were tiny format-10 DeflatedRGBA8 textures whose generated secondary mip entry contained a truncated zlib stream.

The exact exceptions are:

    textures\icons\icon settlementminimap 4x4.tga
    textures\ui\blue.tga
    textures\ui\green.tga
    textures\ui\lightblue.tga
    textures\ui\lightgreen.tga
    textures\ui\lightred.tga

Controlled recompilation with staged nomip produced one-mip DDTs that the official TextureExtractor accepted.

The canonical production compiler now:
- adds nomip only to those six staged BTIs;
- checks that those outputs report one mip;
- leaves authoritative BTIs and PBRify masters untouched;
- keeps the strict verifier unchanged.

Controlled NoMip runs emitted legacy UNHANDLED token encountered warnings on some assets. Warning allowance is asset-scoped and does not weaken unrelated compiler-error handling.

## 7. Blue Lagoon fallback

textures\ui\ui map blue lagoon.tga is the single allowlisted automatic fallback.

Confirmed observations:

- Original: 256×256.
- PBRify output: 1024×1024.
- BC1 output at 1024×1024 fails in the legacy compiler.
- BC2 at 1024×1024 succeeds.
- Several smaller BC1 dimensions succeed.
- 832×832 was intermittently unstable in repeat tests.
- Content/alpha mutation tests did not account for the failure.

Interpretation: a legacy BC1 encoder workload/stability issue, not evidence of damaged source pixels.

Only this specific texture receives automatic BC2 fallback. New failures remain hard failures until individually investigated.

## 8. Legacy TextureExtractor compatibility

Controlled tests reproduced crashes in the installed legacy TextureExtractor on structurally valid BC2 DDTs. The failure was reproduced with real AoM-derived data, deterministic synthetic content, solid-color controls and manually assembled valid files.

The experiments ruled out a simple malformed-payload explanation, a simple content explanation, a simple width/height multiple-of-four rule and a single-mip-only explanation. The exact legacy trigger remains unresolved.

The project therefore treats TextureExtractor as a secondary decoder-compatibility test. See docs/HISTORICAL_TESTS.md.

## 9. Recovery and source exceptions

35 exception textures were investigated. 34 were recovered cleanly. special g griffon map.tga is provisional because a complete bundled Gryphon/Griffon family exists in the clean game, but normal gameplay reachability was not established by the audit.

Black Tortoise has no demonstrated clean-game content reference and is excluded from production.

## 10. Material and player-colour research

Full XML material snapshot:

- 20,842 XML files.
- 20,199 with a texture field.
- 5,490 with ColorTransform4.
- 19 with PixelXForm.
- 1,304 unique texture names.
- 80 materials with secondary_texture.
- 3 unique secondary textures.

Player-colour/CT4 research remains a future normalization input. Do not infer a global runtime policy from alpha bits alone.

## 11. Normalization next phase

Do not apply a global 1024 cap merely because many PBRify outputs exceed that size.

The correct next analysis is role-aware and family-aware:

1. Join accurate TGA classification to the large-output population.
2. Join those textures to full material XML usage.
3. Identify family/variant relationships and deliberate asymmetries.
4. Review the seven >=4096 outputs individually.
5. Treat UI, icons, terrain, shadows, effects, buildings and units according to actual runtime role.
6. Measure final DDT size and runtime memory after normalization.

## 12. Verification architecture

The canonical DDT verifier separates:

CORE DDT INTEGRITY
    Header, dimensions, intended format, alpha, properties,
    entry bounds, compressed block sizes, zlib payload integrity,
    hashes and source relationships.

OFFICIAL DECODER
    Whether TextureExtractor can decode the already-valid DDT.

The latest core-only gate passes all 7,486 production DDTs. The official extractor is a separate ongoing test and must not be used to infer DDT storage format.

DDT byte 6 is authoritative for stored format.

## 13. Current production distribution

    DDT 4  / BC1             1
    DDT 8  / BC2            10
    DDT 9  / BC3          4827
    DDT 10 / DeflatedRGBA8 2559
    DDT 11 / DeflatedRGB8    89
    TOTAL                  7486

Blue Lagoon is included in the DDT 8 count because of its explicit BC2 fallback.

## 14. Historical test retention

Raw experimental test trees are intentionally removed from Git after their conclusions are captured. The retained historical record is docs/HISTORICAL_TESTS.md, together with the current source-lock and verification reports.

No historical raw test result should be treated as a current runtime-release gate unless it is explicitly described as such in the current project state.
