# Legacy TextureExtractor control findings

Snapshot: 2026-09-26.

This document records the final controlled tests performed against the 2014 `TextureExtractor.exe`. The extractor is **not** the primary DDT-integrity gate; these tests exist to characterize a legacy decoder compatibility problem.

## Reproduction baseline

- The installed extractor accepts a lowercase `.ddt` single-file input.
- An uppercase `.DDT` single-file invocation was interpreted as an input directory and returned `-1`.
- Byte-identical lowercase copies were therefore used for controlled tests.
- Generated DDTs were independently checked for header, dimensions, format, mip count, entry bounds and exact BC2 payload sizes before extraction was attempted.

## BC2 observations

All of the following controlled files were structurally valid BC2 DDTs with the expected payload size.

| Dimensions | BC2 blocks | Payload | Extractor |
|---|---:|---:|---|
| 32x32 | 8x8 | 1,024 | PASS |
| 64x32 | 16x8 | 2,048 | PASS |
| 96x32 | 24x8 | 3,072 | PASS |
| 128x32 | 32x8 | 4,096 | PASS |
| 56x64 | 14x16 | 3,584 | PASS |
| 61x64 | 16x16 | 4,096 | PASS |
| 64x61 | 16x16 | 4,096 | PASS |
| 63x63 | 16x16 | 4,096 | PASS |
| 68x64 | 17x16 | 4,352 | PASS |
| 64x56 | 16x14 | 3,584 | PASS |
| 68x64 | 17x16 | 4,352 | PASS (solid-color control) |
| 72x64 | 18x16 | 4,608 | FAIL, `-1073741819` |
| 60x60 | 15x15 | 3,600 | FAIL, `-1073741819` |
| 60x64 | 15x16 | 3,840 | FAIL, `-1073741819` |
| 64x60 | 16x15 | 3,840 | FAIL, `-1073741819` |
| 68x60 | 17x15 | 4,080 | FAIL, `-1073741819` |
| 60x68 | 15x17 | 4,080 | FAIL, `-1073741819` |
| 128x64 | 32x16 | 8,192 | FAIL, `-1073741819` |
| 128x128 | 32x32 | 16,384 | FAIL, `-1073741819` |
| 256x256 | 64x64 | 65,536 | FAIL, `-1073741819` |
| 512x512 | 128x128 | 262,144 | FAIL, `-1073741819` |
| 1024x1024 | 256x256 | 1,048,576 | FAIL, `-1073741819` |

The same behavior was reproduced with real AoM:EE-derived BC2 data, deterministic synthetic images, solid-color controls, and a manually assembled two-mip 72x64 BC2 DDT.

## What the controls establish

1. The failure is not explained by malformed DDT structure or an incorrect BC2 payload-size calculation.
2. It is not simply an RGBA-content issue: deterministic and solid-color controls reproduce both PASS and FAIL cases.
3. It is not a simple monotonic payload-size threshold: some smaller payloads fail while larger nearby geometries pass.
4. It is not solely a width or height multiple-of-four issue: 61x64, 64x61 and 63x63 pass, while 60x64 and 64x60 fail.
5. It is not solely a single-mip issue: a manually assembled valid two-mip 72x64 BC2 DDT also crashes the extractor, while the compiler's ordinary 72x64 output reported one mip.
6. Large generated BC2 files can therefore be valid according to the project DDT verifier while remaining incompatible with this legacy extractor.

The exact trigger remains unresolved. No universal decoder rule should be inferred from the crash boundary.

## Interpretation for the project

The core DDT verifier remains the authoritative structural gate. A legacy TextureExtractor crash is recorded as a secondary compatibility result, not as evidence that the DDT is malformed.

Before release, an independent BC2 decoder and a clean AoM:EE runtime test should be used to establish actual format/runtime validity. Do not alter otherwise-valid generated DDTs solely to satisfy the legacy extractor without independent evidence.
