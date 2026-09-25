# AoMEE cleanup checklist

Reviewed 2026-09-25. The GitHub connector currently permits creation/update but rejected destructive deletion calls, so this file records the exact cleanup to apply in the local checkout before the next production compile.

## Remove from Git and keep local only

Age of Mythology/
extracted/
input/production_source/
input/production_source_png/
models/
processed/PBRify_V4/
processed/PBRify_V4_no_tiling_attempt/
processed/DDT_PBRify_V4/
processed/DDT_PBRify_V4_explicit/

## Remove generated test data

tests/

## Remove obsolete top-level scripts

audit_aomee_normalization_v1.py
compile_pbrify_production.ps1
compiler_format_probe.py
compiler_format_probe_v2.py
compiler_format_probe_v3.py
diagnose_blue_lagoon_bc1_content.py
diagnose_blue_lagoon_bc1_dimensions.py
diagnose_blue_lagoon_bc1_limit.py
diagnose_blue_lagoon_bc1_parallelism.py
diagnose_blue_lagoon_bc1_repeatability.py
diagnose_blue_lagoon_compile.ps1
pbrify_compile_canary_v3.ps1
pbrify_compile_v2.ps1
pbrify_compile_v3.ps1
verify_pbrify_canary.ps1
verify_pbrify_ddt_full_v1.py
verify_pbrify_ddt_full_v2.py
verify_pbrify_ddt_full_v3.py
verify_pbrify_ddt_full_v4.py
verify_pbrify_output.py
verify_pbrify_output_v2.py
user.cfg
~aom_pgs_atlantis2.scx
~aom_pgs_greece2.scx
processed/PBRify_V4_compile.log
processed/PBRify_V4_compile_manifest.csv
processed/pbrify_output_qa_tiled256.csv

## Remove obsolete report trees/files

reports/ddt_full_verification_v2/
reports/ddt_full_verification_v3/
reports/extraction_integrity_gate/
reports/extraction_integrity_gate_v5/
reports/normalization_audit_v1/
reports/mtrl_cli_test/
reports/ddt_extraction_report.csv
reports/bti_missing_expected.csv
reports/bti_orphaned.csv
reports/master_texture_manifest_missing_ddt.csv
reports/ct4_without_noalphatest.txt
reports/mtrl_conversion_errors.txt
reports/mtrl_conversion_log.txt
reports/mtrl_material_index.csv
reports/mtrl_material_index_summary.txt
reports/mtrl_player_color_candidates.csv
reports/mtrl_player_color_candidates_v2.csv
reports/mtrl_player_color_candidates_summary_v2.txt
reports/player_color_bti.csv
reports/player_color_bti_summary.txt
reports/player_color_candidates.csv
reports/player_color_candidates_summary.txt
reports/player_color_intersection.csv
reports/player_color_intersection_summary.txt
reports/player_color_material_evidence.csv
reports/player_color_material_evidence_summary.txt
reports/player_color_mtrl_matches.csv
reports/player_color_mtrl_matches_summary.txt
reports/player_color_signal_matrix.csv
reports/player_color_signal_matrix_v2.csv
reports/player_color_signal_matrix_v2_summary.txt
reports/noalphatest_groups.txt
reports/noalphatest_without_ct4.csv
reports/noalphatest_without_ct4_material_signals.csv
reports/noalphatest_without_ct4_material_signals.txt
reports/noalphatest_without_ct4_summary.txt
reports/patched_to_verify_inventory.csv

## Remove raw converted MTRL duplicates

reports/materials_xml/**/*.mtrl

Keep the 20,842 XML files in reports/materials_xml/.

## Tool cleanup

Remove the unpacked tools/AoM Model Editor 1.2.1/ directory. Keep the corresponding ZIP archive.

## Keep

Keep pbrify_compile_v4.ps1, pbrify_compile_canary_v4.ps1, verify_pbrify_ddt_full_v5.py, verify_texture_compiler_formats.py, verify_pbrify_production.py, the four retained PBRify workflows, source-lock tooling/reports, recovery/usage evidence, current material/player-colour research snapshots, PBRify V4 SHA/QA records, AoM File Converter, TextureCompiler/TextureExtractor/nvtt, and the full material XML snapshot.