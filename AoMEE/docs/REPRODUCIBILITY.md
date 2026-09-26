# Reproducibility guide

Local layout:

```text
AoMEE/
  Age of Mythology/
  extracted/
  input/
  models/PBRify/
  processed/PBRify_V4/
  processed/DDT_PBRify_V4_explicit/
  tests/
  reports/
  tools/
```

Required locally: clean AoM:EE installation, AoM texture tools, and 4x PBRify V4 model. The canonical workflow targets chaiNNer 0.25.1.

Recommended sequence:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\extract_aomee_ddt.ps1
python .\verify_repository_hygiene.py
# run the committed ChaiNNer workflow with project-relative paths
# run the explicit compiler and then the core DDT verifier
```

Expected checkpoints: source 7,487; PBRify 7,487 masters; explicit compile 7,486 DDTs; zero compiler failures/warnings. Current core verifier still has six documented failures.

Verify with counts, relative paths, SHA-256, dimensions, bit depth, explicit format, alpha semantics, DDT entry bounds/sizes and independent/runtime tests. Generated products do not need to live in Git.
