# Technical reference

## DDT layout

Fixed header: `RTS3`, properties, alpha bits, format byte, mip count, width, height. The image-entry table starts at byte 16; each entry contains offset and stored size.

BC1 uses 8 bytes per 4x4 block; BC2/BC3 use 16. Deflated formats contain zlib-compressed raw pixel data. DDT byte 6 is authoritative for stored format.

Relevant bytes: 4=BC1, 5=Dxt1Alpha, 6=Dxt3Swizzled, 8=BC2, 9=BC3, 10=DeflatedRGBA8, 11=DeflatedRGB8, 12=DeflatedR8, 13=DeflatedRG8.

## Compiler rules

Explicit compiler arguments are mandatory: BC1, BC2, BC3, DeflatedRGBA8, DeflatedRGB8. DeflatedRGB8 requires a temporary true 24-bit TGA; the 32-bit PBRify master is never changed in place. Staged BTIs are UTF-8 without BOM.

The legacy compiler can silently select the wrong format when relying on BTI inference, especially for Deflated formats.

## Blue Lagoon

`textures/ui/ui map blue lagoon.tga` is the only automatic BC1 → BC2 fallback. Its 1024x1024 PBRify result is unstable through the legacy BC1 encoder; explicit BC2 succeeds. New failures are not automatically converted.

## Verification architecture

Core validation checks PBRify/DDT hashes, TGA structure, DDT header, format, alpha, dimensions, table bounds/non-overlap, block sizes and zlib integrity. The legacy TextureExtractor runs only after core validation and is not used to redefine DDT storage format.

## Current failures

Six tiny DeflatedRGBA8 DDTs have lower-mip zlib streams rejected by standard zlib even though their entry ranges and stored sizes are internally consistent. They require targeted investigation against originals/compiler/runtime.

Nine structurally valid generated BC2 DDTs crash the legacy TextureExtractor with an access violation. Synthetic images and controlled dimensions reproduced the problem, so it is not specific to PBRify content. The crash trigger was not reduced to a simple stable rule.

## Recovery

35 exception textures were investigated; 34 recovered cleanly and one Gryphon/Griffon map remains provisional. Black Tortoise is excluded from production because clean-game runtime/content usage was not established.

## Material research

The local material snapshot contains 20,842 XML files, 20,199 with texture fields, 5,490 with ColorTransform4, 19 with PixelXForm, 1,304 unique texture names, and 80 materials with secondary_texture. Alpha metadata alone is insufficient for future player-colour/CT4 policy.

## Normalization

Do not globally cap at 1024. Current PBRify output counts: 2,295 >=1024, 202 >=2048, 7 >=4096, and 1,754 exactly 1024x1024. Future normalization must join accurate classification, material semantics, family relationships and runtime role.

## References

- https://github.com/ptasev/Age-of-Mythology
- https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMEngineLibrary/Graphics/Ddt/DdtFile.cs
- https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMEngineLibrary.Graphics.Converters/Graphics/Ddt/ImageDdtConverter.cs
- https://github.com/chaiNNer-org/chaiNNer
