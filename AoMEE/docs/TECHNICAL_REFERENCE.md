# AoM:EE technical reference

## 1. Locked source baseline

The v7 source gate is the canonical source-integrity record.

Clean installation and historical inventory reconcile at 7,487 DDTs. The extracted population is 7,452 normal plus 35 recovered exceptions. All 7,487 logical textures have paired TGA and BTI records.

Do not modify Age of Mythology/ or extracted/ during development.

## 2. PBRify V4

The chosen AI master is 4x-PBRify_UpscalerV4.pth through chaiNNer 0.25.1.

The master is deliberately kept at 4x resolution even though the final runtime resolution is not yet decided. This lets later stages normalize large, uneven, or family-inconsistent assets without re-running AI inference.

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

## 4. Legacy compiler findings

The first full compile relied on BTI metadata alone. That approach is rejected.

Observed behavior:

- BC1/BC2/BC3 metadata paths can produce their expected formats.
- DeflatedRGBA8 metadata-only compilation silently produced DDT format 4 instead of 10.
- DeflatedRGB8 metadata-only compilation silently produced DDT format 4 instead of 11.
- Explicit -c DeflatedRGBA8 on a 32-bit TGA produced format 10.
- Explicit -c DeflatedRGB8 on a 32-bit TGA still produced format 10.
- Explicit -c DeflatedRGB8 on a real 24-bit TGA produced format 11.
- Passing RGB8 to the CLI is not the correct command; the GUI's RGB8 display label maps to DeflatedRGB8.

The production compiler therefore controls both explicit format and input bit depth.

## 5. BTI BOM problem

The legacy compiler emitted warnings for the BOM-prefixed token alpha in staged BTIs.

Authoritative BTI bytes are preserved. Staged BTIs are decoded as UTF-8, have the BOM removed, and are written back as UTF-8 without a BOM.

This is a staging hygiene change, not an alteration to the historical source metadata.

## 6. RGB8 staging

PBRify masters remain 32-bit.

For an original DeflatedRGB8 texture only:

    32-bit PBRify TGA
            |
            v
    temporary true 24-bit TGA
            |
            v
    -c DeflatedRGB8
            |
            v
    DDT format 11

The 24-bit conversion copies BGR bytes and removes only alpha. It is performed only on a temporary compile input.

## 7. Blue Lagoon failure

Blue Lagoon is the single allowlisted BC1 fallback.

Confirmed observations:

- Original: 256×256.
- PBRify output: 1024×1024.
- BC1 output at 1024×1024 fails in the legacy compiler.
- BC2 at 1024×1024 succeeds.
- Several smaller BC1 dimensions succeeded.
- 832×832 was intermittently unstable in repeat tests.
- Content/alpha mutation tests did not account for the failure.

Interpretation: a legacy BC1 encoder workload/stability problem, not evidence of damaged source pixels.

Only this specific texture receives an automatic BC2 fallback. New failures remain hard failures until individually investigated.

## 8. Recovery and legacy usage

35 exception textures were investigated. 34 were recovered cleanly. special g griffon map.tga is provisional because a complete bundled Gryphon/Griffon family exists in the clean game, including model, animation, material, FX, and sound references, but normal gameplay reachability was not established by the audit.

Black Tortoise has no demonstrated clean-game content reference and is excluded from the production candidate. Its recovery evidence remains archived in the repository reports.

## 9. Material and player-colour research

Full XML material snapshot:

- 20,842 XML files.
- 20,199 with a texture field.
- 5,490 with ColorTransform4.
- 19 with PixelXForm.
- 1,304 unique texture names.
- 2,829 candidate texture/material matches.
- 518 unique textures used with ColorTransform4.
- 80 materials with secondary_texture.
- 3 unique secondary textures.

Player-colour research currently identifies 447 CT4 + noalphatest candidate textures in the latest snapshot. The alpha patterns include both binary and multivalue masks; therefore alpha-bit metadata alone is not sufficient to choose a future texture-family policy.

## 10. Normalization next phase

Do not apply a global 1024 cap merely because 2,295 outputs exceed that size.

The correct next analysis is role-aware and family-aware:

1. Join accurate TGA classification to the 2,295 large outputs.
2. Join those textures to full material XML usage.
3. Identify family/variant relationships and deliberate asymmetries.
4. Review the seven >=4096 outputs individually.
5. Treat UI, icons, terrain, shadows, effects, buildings and units according to their actual runtime role.
6. Measure final DDT size and runtime memory after normalization.

## 11. Verification architecture

The canonical DDT verifier separates two questions:

CORE DDT INTEGRITY
    Header, dimensions, intended format, alpha, properties,
    entry bounds, compressed block sizes, zlib payload integrity,
    hashes and source relationships.

OFFICIAL DECODER
    Whether TextureExtractor can decode the already-valid DDT.

TextureExtractor is not run when the core DDT container already fails. This avoids wasting time and avoids conflating container-format mistakes with decoder limitations.

The extractor-generated BTI format is not used as evidence of DDT storage format. Byte 6 of the DDT itself is authoritative.

## 12. Canonical production format distribution expected after the next compile

    DDT 4  / BC1             1
    DDT 8  / BC2            10
    DDT 9  / BC3          4827
    DDT 10 / DeflatedRGBA8 2559
    DDT 11 / DeflatedRGB8    89
    TOTAL                  7486

Blue Lagoon is included in the DDT 8 count because of its explicit BC2 fallback.

## 13. Reference sources

AoM tooling source:
https://github.com/ptasev/Age-of-Mythology

DDT file implementation:
https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMEngineLibrary/Graphics/Ddt/DdtFile.cs

Image-to-DDT encoding implementation:
https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMEngineLibrary.Graphics.Converters/Graphics/Ddt/ImageDdtConverter.cs

BTI implementation:
https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMEngineLibrary/Graphics/BtiFile.cs

DDT converter UI/CLI mapping:
https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMDdtConverter/Form1.cs

AoM:EE texture-converter reference:
https://steamcommunity.com/workshop/discussions/18446744073709551615/558755529558828765/?appid=266840

chaiNNer:
https://github.com/chaiNNer-org/chaiNNer

chaiNNer releases:
https://github.com/chaiNNer-org/chaiNNer/releases