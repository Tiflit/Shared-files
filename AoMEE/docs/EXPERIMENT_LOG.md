# Experiment log

Snapshot: 2026-09-26.

## Production compile
7,486/7,486 DDTs compiled with zero compiler failures/warnings. One Blue Lagoon BC1→BC2 fallback; one archive-only Black Tortoise exclusion. Final bytes: format 4=1, format 8=10, format 9=4,827, format 10=2,559, format 11=89.

## DDT verifier
Latest full run: 7,471 PASS, 6 CORE FAIL, 9 EXTRACTOR FAIL. The six core failures are lower-mip zlib failures in tiny DeflatedRGBA8 textures. The nine extractor-only cases pass core structural checks and then crash the legacy TextureExtractor.

## TextureExtractor controls
The installed 2014 TextureExtractor treats an uppercase `.DDT` single-file input as a directory; lowercase `.ddt` works as the single-file form. Byte-identical copies were used to remove filename-case and copy-corruption variables.

Generated BC2 DDTs were checked independently for exact block geometry, payload size, header values and entry bounds before extraction. Controlled real-data and synthetic tests reproduced extractor access violations. The controls included deterministic content, solid-color content, non-multiple-of-four dimensions, large dimensions and a manually assembled valid two-mip 72x64 file.

Important observations:

- 68x64 (17x16 BC2 blocks, 4,352-byte payload) passes.
- 72x64 (18x16, 4,608 bytes) fails.
- 56x64 (14x16, 3,584 bytes) passes, while 60x60 (15x15, 3,600 bytes) fails.
- 61x64, 64x61 and 63x63 pass despite padded 16x16 block grids.
- 128x32 passes, while 128x64 fails.
- 128x64 through 1024x1024 fail in the large synthetic set.

These results rule out a simple malformed-payload explanation and do not establish a single monotonic size or block-count threshold. The exact legacy-extractor trigger remains unresolved. See `docs/EXTRACTOR_CONTROL_FINDINGS.md`.

## Compiler findings
BTI inference can silently select the wrong format for Deflated formats. Explicit compiler arguments are therefore mandatory. A UTF-8 BOM in staged BTI metadata caused an unhandled `alpha` token. DeflatedRGB8 requires a true 24-bit temporary TGA; the 32-bit PBRify master must not be changed in place.

## Blue Lagoon
`textures/ui/ui map blue lagoon.tga` was unstable through the legacy BC1 encoder at 1024x1024. Explicit BC2 succeeded. Only this texture is allowlisted for BC1→BC2 fallback.

## Source/recovery
Source lock: 7,487 DDTs, 7,452 normal extractions, 35 recovered exceptions. 34 recovered cleanly; one Gryphon/Griffon map remains provisional.

## Normalization
A previous global normalization audit had an invalid category join. No global 1024 cap was adopted. Future normalization must be role/family aware and validated against material semantics, player-colour behavior and runtime results.
