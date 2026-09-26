# Technical reference

DDT header: RTS3, properties, alpha bits, format, mip count, width, height. Entry table starts at byte 16; each entry has offset/stored size. BC1=8 bytes per 4x4 block; BC2/BC3=16. Deflated formats contain zlib-compressed raw pixels. DDT byte 6 is authoritative.

Relevant format bytes: 4=BC1, 8=BC2, 9=BC3, 10=DeflatedRGBA8, 11=DeflatedRGB8.

Explicit compiler arguments are mandatory. DeflatedRGB8 uses a temporary true 24-bit TGA; the 32-bit PBRify master is never changed in place. Staged BTIs are UTF-8 without BOM.

Only `textures/ui/ui map blue lagoon.tga` is allowlisted for BC1→BC2 fallback because its 1024x1024 PBRify result is unstable through the legacy BC1 encoder.

Core verification covers hashes, TGA structure, DDT header/format/alpha/dimensions, entry bounds/non-overlap, block sizes and zlib integrity. The legacy TextureExtractor is secondary.

Six tiny DeflatedRGBA8 lower-mip streams remain unresolved. Nine structurally valid generated BC2 DDTs reproduce a legacy extractor access violation; controlled real-data and synthetic tests show the same class of failure across several dimensions and content patterns. The tests do not establish a single monotonic size/block threshold or a malformed-payload cause. See `docs/EXTRACTOR_CONTROL_FINDINGS.md`.

Material snapshot: 20,842 XML files; 20,199 with texture fields; 5,490 with ColorTransform4; 19 with PixelXForm; 1,304 unique texture names; 80 materials with secondary_texture. Alpha metadata alone is insufficient for future CT4/player-colour policy.

Do not globally cap at 1024. Future normalization must join accurate classification, material semantics, family relationships and runtime role.

References:
- https://github.com/ptasev/Age-of-Mythology
- https://github.com/chaiNNer-org/chaiNNer
- https://github.com/Kim2091/Kim2091-Models/releases
