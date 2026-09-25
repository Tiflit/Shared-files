# Age of Mythology: Extended Edition — texture remaster reference

Last reviewed: 2026-09-25

This directory is the long-term reproducibility and research record for the AoM:EE texture-remaster project. Large source, model, intermediate, and generated-output trees are intentionally kept local.

## Current project state

- Source population: 7,487 original DDT textures.
- Historical extraction: 7,452 normal + 35 recovered exception texture pairs.
- PBRify V4 master: 7,487 32-bit TGAs, produced with chaiNNer 0.25.1 and the 4x-PBRify_UpscalerV4 model.
- The PBRify 4x output is a high-resolution working/master representation; it is not the final runtime-resolution policy.
- Source/extraction integrity is locked and must be preserved.

## Protected local data

These directories/files are deliberately outside Git history:

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

The clean game and extracted trees are source-locked. Never modify them during the remaster workflow.

## Canonical workflow

1. Start from a clean AoM:EE installation.
2. Extract DDTs with the retained TextureExtractor tool.
3. Run the source-lock gate.
4. Stage source TGAs and convert them to PNG for the AI workflow.
5. Run the canonical PBRify V4 chaiNNer workflow.
6. Verify the 4x output dimensions and alpha replication.
7. Run verify_texture_compiler_formats.py when validating the installed compiler/toolchain.
8. Run the explicit compiler canary before a full DDT compile.
9. Run the explicit production DDT compiler.
10. Run the DDT core verifier first without the external decoder, then run it again with the official decoder.
11. Test the resulting DDT set in-game before any normalization or release packaging.

Recommended commands from the project root:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\verify_aomee_source_gate_v7.ps1
    python .\verify_pbrify_production.py --source .\input\production_source_png --output .\processed\PBRify_V4 --report .\processed\pbrify_output_qa_production.csv --expected-count 7487
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\pbrify_compile_canary_v4.ps1
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\pbrify_compile_v4.ps1
    python .\verify_pbrify_ddt_full_v5.py --skip-extractor
    python .\verify_pbrify_ddt_full_v5.py

The exact source/output paths above assume the default local project layout. Keep the authoritative local trees outside Git.

## Canonical compiler rules

The installed legacy TextureCompiler must be given an explicit format. Relying on BTI inference is not acceptable because the executable silently selected DDT format 4 for the Deflated formats.

| Original BTI format | Compiler argument | Compiler input | DDT format byte |
| --- | --- | --- | --- |
| BC1 | -c BC1 | 32-bit TGA | 4 |
| BC2 | -c BC2 | 32-bit TGA | 8 |
| BC3 | -c BC3 | 32-bit TGA | 9 |
| DeflatedRGBA8 | -c DeflatedRGBA8 | 32-bit TGA | 10 |
| DeflatedRGB8 | -c DeflatedRGB8 | temporary true 24-bit TGA | 11 |

The 24-bit RGB8 conversion is a compile-only staging operation. The PBRify master remains 32-bit and is never changed.

Staged BTIs are written as UTF-8 without a BOM because the installed compiler previously reported the BOM-prefixed alpha token as an unhandled token. Authoritative BTIs are never rewritten.

Do not uppercase the mixed-case Deflated compiler arguments. The documented command is DeflatedRGBA8 / DeflatedRGB8.

## Known compiler exception

textures\ui\ui map blue lagoon.tga is the only currently allowlisted automatic fallback.

Its PBRify result is 1024×1024 and the legacy BC1 encoder is unstable in this size/workload region. Repeated diagnostics showed successful BC1 at several smaller dimensions and failure at larger tested dimensions; BC2 consistently succeeded for the Blue Lagoon fallback.

Do not add automatic format fallbacks for new textures. A new compile failure must first be reproduced and investigated.

## Source and recovery baseline

The canonical source-lock evidence is under reports/extraction_integrity_gate_v7/.

Recorded baseline:

- 7,487 clean DDTs.
- 7,487 logical extracted TGAs.
- 7,487 logical extracted BTIs.
- 7,452 normal textures.
- 35 recovered exceptions.
- Clean DDT inventory reconciles with historical inventory.
- TGA-to-BTI pairing passes.
- TGA structural validation passes.

Recovered exceptions are retained as provenance. 34 are cleanly recovered; special g griffon map.tga is explicitly provisional.

Black Tortoise is archive-only and excluded from production because the usage audit did not demonstrate a clean-game content reference.

## Material research snapshot

The full material XML snapshot is retained because future normalization and texture-family analysis depends on the semantic relationships in the materials.

Current snapshot facts:

- 20,842 XML files.
- 20,199 materials with a texture field.
- 5,490 materials with ColorTransform4.
- 19 with PixelXForm.
- 1,304 unique texture names.
- 80 materials with secondary_texture.
- 3 unique secondary textures.

The old weak mtrl_material_index report is not authoritative. Future material indexes should be rebuilt from the XML snapshot with a robust parser.

## Normalization status

Normalization is deliberately not locked yet.

Useful current findings:

- 2,295 PBRify outputs have a maximum dimension of at least 1024.
- 202 reach at least 2048.
- 7 reach at least 4096.
- 1,754 are exactly 1024×1024.

The previous normalization audit had an invalid category join and must not be used to make a global resolution or compression decision. The next normalization phase should join accurate TGA classification, material XML semantics, texture families, and role before choosing any downscaling policy.

## Repository contents worth preserving

- Source-lock scripts and v7 baseline reports.
- Master texture manifest, TGA inventory, classification, and BTI metadata snapshots.
- PBRify V4 workflow definitions.
- PBRify SHA-256 manifest and production QA report.
- The canonical explicit compiler, compiler canary, and DDT verifier.
- Recovery/cut-content provenance reports.
- Full material XML semantic snapshot.
- A compact technical reference documenting discovered format semantics and failure modes.
- The retained AoM File Converter/Texture tools needed by the workflow.

Historical one-off diagnostics and superseded script revisions are intentionally removed. Their important conclusions are summarized in docs/TECHNICAL_REFERENCE.md.

## External references

- AoM tooling source: https://github.com/ptasev/Age-of-Mythology
- DDT implementation: https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMEngineLibrary/Graphics/Ddt/DdtFile.cs
- DDT image encoder: https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMEngineLibrary.Graphics.Converters/Graphics/Ddt/ImageDdtConverter.cs
- BTI implementation: https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMEngineLibrary/Graphics/BtiFile.cs
- AoM DDT converter UI/CLI mapping: https://github.com/ptasev/Age-of-Mythology/blob/master/src/AoMDdtConverter/Form1.cs
- AoM:EE texture-converter reference/discussion: https://steamcommunity.com/workshop/discussions/18446744073709551615/558755529558828765/?appid=266840
- chaiNNer: https://github.com/chaiNNer-org/chaiNNer
- chaiNNer releases: https://github.com/chaiNNer-org/chaiNNer/releases

The exact PBRify model file is intentionally not committed. When its source is finalized, record its provenance and SHA-256 in a future project note.

## Reproducibility rule

Git should contain enough information to reconstruct the workflow and understand every intentional exception, but not gigabytes of source/output files that can be regenerated locally. Every future pipeline change should preserve source-lock evidence and add a concise note explaining what changed and why.