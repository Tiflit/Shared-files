# Age of Mythology: Extended Edition — texture remaster reference

Last reviewed: 2026-09-30

This directory is the long-term reproducibility and research record for the AoM:EE texture-remaster project. Git contains workflow definitions, verification code, source-lock evidence, concise research results, and retained tools. Large source, model, intermediate, generated-output, and experimental test trees are kept local.

## Current verified state

- Source population: 7,487 original DDT textures.
- Historical extraction: 7,452 normal + 35 recovered exception texture pairs.
- PBRify V4 master: 7,487 32-bit TGAs, produced with chaiNNer 0.25.1 and the 4x-PBRify_UpscalerV4 model.
- Fresh explicit production compile: 7,486/7,486 DDTs, zero compile failures, zero warning tokens, zero missing/unexpected outputs.
- Current explicit format distribution: byte 4=1, byte 8=10, byte 9=4,827, byte 10=2,559, byte 11=89.
- One archive-only Black Tortoise texture is excluded from production. Blue Lagoon is the only automatic BC1→BC2 fallback.
- The fresh strict core DDT verification passes 7,486/7,486 with zero core failures. The official TextureExtractor verification is running separately.
- The six tiny DeflatedRGBA8 assets now use a targeted staged nomip workaround; authoritative BTIs and PBRify masters remain untouched.
- The explicit format canary is validated at 16/16.

The next runtime gate is the official extractor result. After that, use a disposable clean-game runtime copy for in-game validation before any resolution normalization or release packaging.

## Protected local data

These are intentionally outside Git history:

    Age of Mythology/
    extracted/
    input/production_source/
    input/production_source_png/
    models/
    processed/PBRify_V4/
    processed/PBRify_V4_no_tiling_attempt/
    processed/DDT_PBRify_V4/
    processed/DDT_PBRify_V4_explicit/
    tests/
    reports/materials_xml/

The clean game and extracted trees are source-locked. Never modify them during the remaster workflow.

## Canonical workflow

1. Start from a clean AoM:EE installation.
2. Extract DDTs with the retained TextureExtractor tool.
3. Run the source-lock gate.
4. Stage source TGAs and convert them to PNG for the AI workflow.
5. Run the canonical PBRify V4 chaiNNer workflow.
6. Verify the 4x output dimensions and alpha replication.
7. Run the explicit compiler canary.
8. Run the explicit production DDT compiler.
9. Run the DDT core verifier first without the external decoder, then run it again with the official decoder.
10. Test the resulting DDT set in-game before any normalization or release packaging.

Recommended commands from the project root:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\verify_aomee_source_gate_v7.ps1
    python .\verify_pbrify_production.py --source .\input\production_source_png --output .\processed\PBRify_V4 --report .\processed\pbrify_output_qa_production.csv --expected-count 7487
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\pbrify_compile_canary_v4.ps1
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\pbrify_compile_v4.ps1
    python .\verify_pbrify_ddt_full_v5.py --skip-extractor
    python .\verify_pbrify_ddt_full_v5.py

## Canonical compiler rules

The installed legacy TextureCompiler must be given an explicit format. Relying on BTI inference is not acceptable because the executable silently selected the wrong DDT format for the Deflated formats.

| Original BTI format | Compiler argument | Compiler input | DDT format byte |
| --- | --- | --- | --- |
| BC1 | -c BC1 | 32-bit TGA | 4 |
| BC2 | -c BC2 | 32-bit TGA | 8 |
| BC3 | -c BC3 | 32-bit TGA | 9 |
| DeflatedRGBA8 | -c DeflatedRGBA8 | 32-bit TGA | 10 |
| DeflatedRGB8 | -c DeflatedRGB8 | temporary true 24-bit TGA | 11 |

For RGB8, the 24-bit conversion is compile-only staging. The PBRify master remains 32-bit and is never changed.

Staged BTIs are written as UTF-8 without a BOM. Authoritative BTIs are never rewritten.

Six tiny DeflatedRGBA8 assets require targeted nomip staging because the legacy compiler generated truncated secondary mips for them. The exact exceptions are:

    textures\icons\icon settlementminimap 4x4.tga
    textures\ui\blue.tga
    textures\ui\green.tga
    textures\ui\lightblue.tga
    textures\ui\lightgreen.tga
    textures\ui\lightred.tga

Only the staged BTI receives nomip. The canonical compiler asserts one mip for these six outputs. Other compiler warnings remain hard failures.

## DDT verification architecture

The strict verifier separates two questions:

CORE DDT INTEGRITY
    Header, dimensions, intended format, alpha, properties,
    entry bounds, compressed block sizes, zlib payload integrity,
    hashes and source relationships.

OFFICIAL DECODER
    Whether the legacy TextureExtractor can decode the already-valid DDT.

The core verifier remains the authoritative integrity gate. A legacy extractor crash does not by itself prove that a DDT container is malformed. Controlled BC2 decoder findings are summarized in docs/HISTORICAL_TESTS.md.

## Source and recovery baseline

- 7,487 clean DDTs.
- 7,487 logical extracted TGAs.
- 7,487 logical extracted BTIs.
- 7,452 normal textures.
- 35 recovered exceptions.
- 34 recovered exceptions are clean; special g griffon map.tga remains provisional.
- Black Tortoise is archive-only and excluded from production.

## Normalization status

Normalization is deliberately not locked.

The 4x PBRify master is retained so normalization can be role-aware and family-aware rather than forcing a global resolution cap. Current size snapshot:

- 2,295 outputs have max dimension >= 1024.
- 202 reach >= 2048.
- 7 reach >= 4096.
- 1,754 are exactly 1024×1024.

The next normalization phase must join accurate TGA classification, full material XML semantics, texture families and runtime role before a final resolution/compression policy is chosen.

## Repository and branch policy

main is the authoritative current project record.

aomee-review-sanitized-2026-09-26 is a compact historical review snapshot from before the final NoMip/core-verifier repair. It is retained as an archival reference, not as the current baseline.

aomee-repo-streamline-pre-ddt is an older pre-DDT checkpoint whose branch tip has now been compacted to the sanitized historical review snapshot. Its full historical commit ancestry remains intact; it is not a working baseline.

Raw tests are not part of the long-term repository. Their important outcomes are retained in docs/HISTORICAL_TESTS.md, docs/TECHNICAL_REFERENCE.md, and the current source-lock/current-verification reports.

## External references

- AoM tooling source: https://github.com/ptasev/Age-of-Mythology
- DDT implementation: https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMEngineLibrary/Graphics/Ddt/DdtFile.cs
- DDT image encoder: https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMEngineLibrary.Graphics.Converters/Graphics/Ddt/ImageDdtConverter.cs
- BTI implementation: https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMEngineLibrary/Graphics/BtiFile.cs
- AoM DDT converter UI/CLI mapping: https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMDdtConverter/Form1.cs
- AoM:EE texture-converter reference/discussion: https://steamcommunity.com/workshop/discussions/18446744073709551615/558755529558828765/?appid=266840
- chaiNNer: https://github.com/chaiNNer-org/chaiNNer
- chaiNNer releases: https://github.com/chaiNNer-org/chaiNNer/releases

The exact PBRify model file is intentionally not committed. Its provenance and SHA-256 should be recorded when the model source is finalized.
