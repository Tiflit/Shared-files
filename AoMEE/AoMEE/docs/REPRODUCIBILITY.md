# Reproducibility guide

## Local layout

Use the checkout itself as the project root:

```text
AoMEE/
  Age of Mythology/                         clean local game
  extracted/                                extracted TGA/BTI
  input/                                    local staging
  models/PBRify/                            local AI model
  processed/PBRify_V4/                      4x masters
  processed/DDT_PBRify_V4_explicit/        compiled DDTs
  tests/                                    local diagnostics
  reports/                                  committed evidence
  tools/                                    locally supplied AoM tools
```

## Required inputs

A clean AoM:EE installation and the AoM texture tools are required locally. The 4x PBRify V4 model is external/local and deliberately not committed. The canonical ChaiNNer workflow targets chaiNNer 0.25.1.

## Command sequence

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\extract_aomee_ddt.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\verify_aomee_source_gate_v7.ps1
python .\convert_aom_tga_to_png.py .\input\production_source .\input\production_source_png
python .\verify_pbrify_production.py --source .\input\production_source_png --output .\processed\PBRify_V4 --report .\reports\pbrify\pbrify_output_qa_production.csv --expected-count 7487
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\pbrify_compile_canary_v4.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\pbrify_compile_v4.ps1
python .\verify_pbrify_ddt_full_v5.py --skip-extractor
python .\verify_pbrify_ddt_full_v5.py
python .\verify_repository_hygiene.py
```

The PBRify inference step itself is performed through the committed ChaiNNer workflow and local model.

## Expected checkpoints

Source: 7,487 DDTs; 7,452 normal + 35 recovered.

PBRify: 7,487 32-bit masters, exact 4x dimensions, exact 4x nearest-neighbour alpha replication.

Compile: 7,486 DDTs, one archive-only exclusion, one Blue Lagoon fallback, zero compiler failures/warnings.

Verifier: core DDT validation first; legacy TextureExtractor only as a secondary compatibility check.

## Reproducibility philosophy

Verify transformations using file counts, relative paths, SHA-256 hashes, dimensions, bit depth, explicit format, alpha semantics, DDT entry bounds/sizes and runtime/decoder tests. Generated products do not need to live in Git.
