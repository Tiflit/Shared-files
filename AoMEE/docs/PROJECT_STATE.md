# AoM:EE Remaster — authoritative project state

Last reviewed: 2026-09-25

## Objective

Remaster the **Age of Mythology: Extended Edition** texture set while preserving the original game's texture population, metadata relationships, and runtime behavior. The current work is at the final DDT compilation/verification stage for the PBRify V4 texture masters. Runtime normalization, in-game validation, and final packaging remain after the DDT build.

## Locked source baseline

- 7,487 original DDT textures are the authoritative population.
- 7,487 logical TGA/BTI pairs exist in the locked extraction: 7,452 normal + 35 recovered exceptions.
- The clean game copy and `extracted/` tree are protected local reference data.
- Black Tortoise is archive-only and excluded from the production set.

## PBRify baseline

- Canonical workflow: chaiNNer 0.25.1 + `4x-PBRify_UpscalerV4.pth`.
- 7,487 PBRify V4 masters exist locally as 32-bit TGAs.
- PBRify masters are never modified for compiler staging.
- The 4x master is intentionally retained because runtime resolution/normalization has not yet been finalized.

## Canonical DDT compilation

The legacy TextureCompiler must receive an explicit format. The original BTI-only path is rejected for Deflated formats.

| Source BTI | Compiler argument | Compile input | DDT byte 6 |
| --- | --- | --- | ---: |
| BC1 | `-c BC1` | 32-bit TGA | 4 |
| BC2 | `-c BC2` | 32-bit TGA | 8 |
| BC3 | `-c BC3` | 32-bit TGA | 9 |
| DeflatedRGBA8 | `-c DeflatedRGBA8` | 32-bit TGA | 10 |
| DeflatedRGB8 | `-c DeflatedRGB8` | temporary true 24-bit TGA | 11 |

For `DeflatedRGB8`, the temporary 24-bit TGA removes only the alpha byte from each BGR pixel. The authoritative 32-bit PBRify master is untouched. The temporary BTI is UTF-8 without a BOM and retains the original metadata values.

The installed compiler previously treated `RGB8` as an invalid CLI value; the GUI label `RGB8` corresponds to the compiler argument `DeflatedRGB8`.

## Known exception

`textures\ui\ui map blue lagoon.tga` is the only automatic fallback:

`BC1 -> BC2`

This is an explicit, allowlisted workaround for the legacy BC1 encoder's instability on the 1024x1024 PBRify result. New compiler failures must remain hard failures until individually investigated.

## Canary gate

The corrected explicit-format canary has already passed 10/10 against real production samples:

- BC1 -> 4
- BC2 -> 8
- BC3 -> 9
- DeflatedRGBA8 -> 10
- DeflatedRGB8 -> 11 with 24-bit compiler input
- Blue Lagoon fallback -> 8

The canary must pass again after repository synchronization before the full build.

## Expected production result

The authoritative source-format population is expected to compile to 7,486 production DDTs:

```text
DDT 4  / BC1             1
DDT 8  / BC2            10
DDT 9  / BC3          4827
DDT 10 / DeflatedRGBA8 2559
DDT 11 / DeflatedRGB8    89
TOTAL                  7486
```

The missing 1 of 7,487 is the archive-only Black Tortoise asset.

## Verification gate

Run the core verifier before the official extractor:

```powershell
python .\verify_pbrify_ddt_full_v5.py --skip-extractor
```

Only after the core container/format/payload checks pass:

```powershell
python .\verify_pbrify_ddt_full_v5.py
```

The DDT's byte 6 is authoritative for stored format. The extractor is a separate decoder test and must not be used to infer the DDT format.

## What remains after the DDT build

1. Verify all 7,486 production DDTs structurally.
2. Verify all 7,486 with the official extractor.
3. Replace/test the DDT set against the clean game in a disposable runtime copy.
4. Perform role-aware/family-aware normalization; do not impose a global 1024 cap.
5. Review the seven >=4096 PBRify outputs individually.
6. Validate player-colour/CT4/noalphatest behavior where relevant.
7. Test the remaster in-game.
8. Package the final release only after runtime validation.

## Repository rule

Git is the reproducibility and research record, not the storage location for the multi-gigabyte working trees. Keep clean game data, extracted trees, models, PBRify image masters, generated DDTs, staging and tests local. Keep source-lock evidence, manifests, workflow definitions, canonical tools, verification code, material semantics, and concise research conclusions in Git.

Historical experiments may be removed once their conclusions are captured in `TECHNICAL_REFERENCE.md`. Do not retain obsolete compiler/verifier generations merely because they have a lower version number.
