# AoMEE repository cleanup record

Reviewed: 2026-09-30

The repository cleanup was completed for the current main snapshot on 2026-09-30. The goal is to keep Git useful for reproducibility and future analysis without retaining gigabytes of disposable test inputs/outputs.

## Remove from Git; keep/regenerate locally

    Age of Mythology/
    extracted/
    input/production_source/
    input/production_source_png/
    models/
    processed/PBRify_V4/
    processed/PBRify_V4_no_tiling_attempt/
    processed/DDT_PBRify_V4/
    processed/DDT_PBRify_V4_explicit/
    reports/materials_xml/
    tests/

The large local trees are ignored by .gitignore.

## Remove superseded top-level code

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
    diagnose_blue_lagoon_compile_v2.ps1
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

Keep the current v4 compiler/canary, v5 DDT verifier, source gate, production verifier and compiler-format verifier.

## Remove superseded generated outputs

    processed/PBRify_V4_compile.log
    processed/PBRify_V4_compile_manifest.csv
    processed/pbrify_output_qa_tiled256.csv

Keep the current explicit compile manifest/log and current PBRify SHA/QA records.

## Remove superseded reports

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

The current source-lock v7 records, current DDT verification v5, current material/XML-derived records, current player-colour/CT4 snapshots, recovery evidence, and PBRify SHA/QA records remain.

## Tool cleanup

Remove the unpacked tools/AoM Model Editor 1.2.1/ tree and keep its ZIP archive.

The committed Model Editor log is removed as disposable application-local history.

## Historical tracking

Raw test payloads are removed, but their conclusions are preserved in docs/HISTORICAL_TESTS.md and the technical reference. In particular, retain the explicit compiler mapping, Blue Lagoon fallback diagnosis, six NoMip findings, legacy TextureExtractor control results, source/recovery counts and model-selection conclusions.

## Privacy/repository hygiene

The cleanup removes the user-local user.cfg, the application log, and other disposable local artifacts. A searchable text scan found no obvious occurrences of C:\Users\philg, D:\AI_upscaling, OneDrive, common personal email domains, or private-LAN prefixes in the indexed repository text. This is a hygiene check, not a guarantee about Git history or unindexed binary content.

Do not commit local absolute paths, account identifiers, personal email addresses, LAN addresses or unrelated application logs in future artifacts.
