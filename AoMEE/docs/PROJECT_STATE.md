# AoM:EE Remaster — authoritative project state

Last reviewed: 2026-09-25

## Objective

Remaster the **Age of Mythology: Extended Edition** texture set while preserving the original game's texture population, metadata relationships, and runtime behavior. The project is at the DDT compilation/verification stage for the PBRify V4 masters. Runtime normalization, in-game validation, and final packaging remain after the DDT build.

## Locked baseline

- 7,487 original DDT textures.
- 7,487 logical TGA/BTI pairs: 7,452 normal + 35 recovered exceptions.
- Clean game and `extracted/` are protected local reference data.
- Black Tortoise is archive-only and excluded from production.
- 7,487 PBRify V4 32-bit TGA masters exist locally.

## Canonical DDT compilation

The legacy TextureCompiler must receive an explicit format. BTI-only inference is rejected for Deflated formats.

| Source BTI | Compiler argument | Compile input | DDT byte 6 |
| --- | --- | --- | ---: |
| BC1 | `-c BC1` | 32-bit TGA | 4 |
| BC2 | `-c BC2` | 32-bit TGA | 8 |
| BC3 | `-c BC3` | 32-bit TGA | 9 |
| DeflatedRGBA8 | `-c DeflatedRGBA8` | 32-bit TGA | 10 |
| DeflatedRGB8 | `-c DeflatedRGB8` | temporary true 24-bit TGA | 11 |

The RGB8 conversion is compile-only staging. It removes only the alpha byte from each BGR pixel; the 32-bit PBRify master is never modified. Staged BTIs are UTF-8 without BOM.

The CLI argument is `DeflatedRGB8`; `RGB8` is only the GUI display label.

## Known exception

`textures\ui\ui map blue lagoon.tga` is the only automatic fallback: `BC1 -> BC2`. New compiler failures remain hard failures until investigated.

## Current canary gate

The explicit-format canary has already passed 10/10 real production samples:

- BC1 -> 4
- BC2 -> 8
- BC3 -> 9
- DeflatedRGBA8 -> 10
- DeflatedRGB8 -> 11 with 24-bit input
- Blue Lagoon fallback -> 8

It must pass again after synchronization before the full compile.

## Expected production result

```text
DDT 4  / BC1             1
DDT 8  / BC2            10
DDT 9  / BC3          4827
DDT 10 / DeflatedRGBA8 2559
DDT 11 / DeflatedRGB8    89
TOTAL                  7486
```

The missing one is the archive-only Black Tortoise asset.

## Verification order

```powershell
python .\verify_pbrify_ddt_full_v5.py --skip-extractor
python .\verify_pbrify_ddt_full_v5.py
```

Core DDT integrity must pass before the official decoder is invoked. DDT byte 6 is authoritative for stored format.

## Remaining project work

1. Produce and structurally verify 7,486 production DDTs.
2. Verify them with the official extractor.
3. Test them in a disposable game copy.
4. Perform role/family-aware runtime normalization; do not impose a global 1024 cap.
5. Review the seven >=4096 outputs individually.
6. Validate CT4/noalphatest/player-colour behavior where relevant.
7. Perform in-game validation.
8. Package the final remaster.

## Repository rule

Git is the reproducibility/research record, not storage for multi-gigabyte source/output trees. Keep clean game data, extracted trees, models, PBRify images, generated DDTs, staging and tests local. Keep source-lock evidence, manifests, workflow definitions, canonical tools, verification code, material semantics and concise research conclusions in Git.

Historical experiments may be removed once their conclusions are captured in `TECHNICAL_REFERENCE.md`. Do not retain superseded compiler/verifier generations merely because they have a lower version number.
