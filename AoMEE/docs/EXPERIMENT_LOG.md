# Experiment log

## Production compile
7,486/7,486 DDTs compiled with zero failures/warnings. One Blue Lagoon BC1→BC2 fallback; one archive-only Black Tortoise exclusion. Final bytes: 4=1, 8=10, 9=4827, 10=2559, 11=89.

## DDT verifier
7,471 PASS, 6 CORE FAIL, 9 EXTRACTOR FAIL. Core failures are lower-mip zlib failures in tiny DeflatedRGBA8 textures.

## TextureExtractor controls
Uppercase `.DDT` invocation was treated as a directory by the installed extractor; byte-identical lowercase `.ddt` copies were processed. Generated BC2 files passed structural checks but some crashed the extractor. Dimension tests, solid-colour images, deterministic synthetic images and a manually assembled two-mip 72x64 BC2 file reproduced crashes. No simple monotonic size/block threshold was found.

Conclusion: the legacy extractor has a reproducible compatibility problem with some generated BC2 DDTs, but the trigger remains unresolved; it is a secondary decoder test.

## Compiler findings
BTI inference can silently select the wrong format for Deflated formats. Explicit compiler arguments are therefore mandatory. A UTF-8 BOM in staged BTI metadata caused an unhandled `alpha` token. DeflatedRGB8 requires a true 24-bit temporary TGA.

## Blue Lagoon
1024x1024 PBRify BC1 was unstable through the legacy encoder; explicit BC2 succeeded. Only this texture is allowlisted for fallback.

## Source/recovery
Source lock: 7,487 DDTs, 7,452 normal extractions, 35 recovered exceptions. 34 recovered cleanly; one Gryphon/Griffon map remains provisional.

## Normalization
A previous global normalization audit had an invalid category join. No global 1024 cap was adopted; future work is role/family aware.
