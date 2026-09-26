# Experiment log — review snapshot

## Explicit production compile

7,486/7,486 production DDTs compiled with zero failures and zero warning tokens. One Blue Lagoon BC1→BC2 fallback was used; one archive-only Black Tortoise texture was excluded. Final format distribution: byte 4=1, byte 8=10, byte 9=4827, byte 10=2559, byte 11=89.

## DDT verifier

Latest full run: 7,471 PASS, 6 CORE FAIL, 9 EXTRACTOR FAIL. The six core failures are lower-mip zlib failures in tiny DeflatedRGBA8 textures. The nine extractor-only failures pass core validation and then crash the legacy TextureExtractor.

## Extractor controls

A clean uppercase `.DDT` invocation was interpreted as a directory by the installed extractor; byte-identical lowercase `.ddt` copies were processed. With invocation controlled, clean BC2/A1 and generated BC2/A1 were compared.

Generated BC2 files passed structural checks but some crashed the extractor. Synthetic dimensions showed both passing and failing cases; there was no simple monotonic width, height, payload or block-count threshold. Solid-colour and deterministic synthetic sources reproduced the crash, proving PBRify content is not required. A manually assembled valid two-mip 72x64 BC2 file also crashed.

Conclusion: the legacy extractor has a reproducible compatibility problem with some generated BC2 DDTs, but the exact trigger remains unresolved. It is a secondary decoder test rather than the primary DDT validity gate.

## Compiler format discovery

Relying on BTI inference is rejected because the legacy compiler can silently choose the wrong format for Deflated formats. Explicit `-c DeflatedRGBA8` produces byte 10. Explicit `-c DeflatedRGB8` produces byte 11 only when given a true 24-bit TGA. A UTF-8 BOM in staged BTI metadata caused an unhandled `alpha` token; staged copies are therefore written without BOM.

## Blue Lagoon

The 1024x1024 PBRify Blue Lagoon BC1 path is unstable in the legacy encoder. Smaller dimension tests succeeded; production-sized BC1 did not. Explicit BC2 succeeded. Only this texture is allowlisted for the fallback.

## Source/recovery history

The source lock established 7,487 DDTs, 7,452 normal extractions and 35 recovered exceptions. 34 recovered cleanly; the Gryphon/Griffon map remains provisional for runtime reachability.

## Normalization history

An earlier global normalization audit had an invalid category join and is not authoritative. No global 1024 cap has been adopted. Future work must be role/family aware and use material semantics.
