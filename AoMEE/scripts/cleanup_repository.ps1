param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$Project = Split-Path -Parent $PSScriptRoot
Set-Location $Project

$gitRoot = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) {
    throw "Not inside a Git working tree."
}
$gitRoot = $gitRoot.Trim()

function Show-Action {
    param([string]$Action, [string]$Path)
    if ($Apply) {
        Write-Host "$Action`t$Path"
    } else {
        Write-Host "[DRY-RUN] $Action`t$Path"
    }
}

function Remove-TrackedCached {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        if ($Apply) {
            git rm -r -f --cached --ignore-unmatch -- "AoMEE/$p" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Failed to untrack: $p" }
        }
        Show-Action "UNTRACK" "AoMEE/$p"
    }
}

function Remove-TrackedWorkingTree {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        if ($Apply) {
            git rm -r -f --ignore-unmatch -- "AoMEE/$p" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Failed to remove: $p" }
        }
        Show-Action "REMOVE" "AoMEE/$p"
    }
}

Write-Host "============================================"
Write-Host "AoMEE REPOSITORY CLEANUP"
Write-Host "============================================"
Write-Host "Project: $gitRoot"
Write-Host ""

if (-not $Apply) {
    Write-Host "DRY RUN. Re-run with -Apply to perform the changes."
    Write-Host ""
}

# Large/regenerable trees: remove from Git index but KEEP local files.
Remove-TrackedCached @(
    'Age of Mythology'
    'extracted'
    'input/production_source'
    'input/production_source_png'
    'models'
    'processed/PBRify_V4'
    'processed/PBRify_V4_no_tiling_attempt'
    'processed/DDT_PBRify_V4'
    'processed/DDT_PBRify_V4_explicit'
)

# Generated tests are disposable.
Remove-TrackedWorkingTree @('tests')

# Remove raw converted MTRL copies from Git and disk; XML snapshot remains.
$rawMtrl = @(git ls-files -- 'AoMEE/reports/materials_xml/*.mtrl' 'AoMEE/reports/materials_xml/*.MTRL')
foreach ($p in $rawMtrl) {
    if ($Apply) {
        git rm -f --ignore-unmatch -- $p | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to remove: $p" }
    }
    Show-Action "REMOVE" $p
}

# Keep the archival ZIP; remove the unpacked duplicate.
Remove-TrackedWorkingTree @('tools/AoM Model Editor 1.2.1')

# Superseded root-level scripts and generated outputs.
Remove-TrackedWorkingTree @(
    'audit_aomee_normalization_v1.py'
    'compile_pbrify_production.ps1'
    'compiler_format_probe.py'
    'compiler_format_probe_v2.py'
    'compiler_format_probe_v3.py'
    'diagnose_blue_lagoon_bc1_content.py'
    'diagnose_blue_lagoon_bc1_dimensions.py'
    'diagnose_blue_lagoon_bc1_limit.py'
    'diagnose_blue_lagoon_bc1_parallelism.py'
    'diagnose_blue_lagoon_bc1_repeatability.py'
    'diagnose_blue_lagoon_compile.ps1'
    'pbrify_compile_canary_v3.ps1'
    'pbrify_compile_v2.ps1'
    'pbrify_compile_v3.ps1'
    'verify_pbrify_canary.ps1'
    'verify_pbrify_ddt_full_v1.py'
    'verify_pbrify_ddt_full_v2.py'
    'verify_pbrify_ddt_full_v3.py'
    'verify_pbrify_ddt_full_v4.py'
    'verify_pbrify_output.py'
    'verify_pbrify_output_v2.py'
    'user.cfg'
    '~aom_pgs_atlantis2.scx'
    '~aom_pgs_greece2.scx'
    'processed/PBRify_V4_compile.log'
    'processed/PBRify_V4_compile_manifest.csv'
    'processed/pbrify_output_qa_tiled256.csv'
)

# Superseded report sets. Current v7/material/player-colour snapshots remain.
Remove-TrackedWorkingTree @(
    'reports/ddt_full_verification_v2'
    'reports/ddt_full_verification_v3'
    'reports/extraction_integrity_gate'
    'reports/extraction_integrity_gate_v5'
    'reports/normalization_audit_v1'
    'reports/mtrl_cli_test'
    'reports/ddt_extraction_report.csv'
    'reports/bti_missing_expected.csv'
    'reports/bti_orphaned.csv'
    'reports/master_texture_manifest_missing_ddt.csv'
    'reports/ct4_without_noalphatest.txt'
    'reports/mtrl_conversion_errors.txt'
    'reports/mtrl_conversion_log.txt'
    'reports/mtrl_material_index.csv'
    'reports/mtrl_material_index_summary.txt'
    'reports/mtrl_player_color_candidates.csv'
    'reports/mtrl_player_color_candidates_v2.csv'
    'reports/mtrl_player_color_candidates_summary_v2.txt'
    'reports/player_color_bti.csv'
    'reports/player_color_bti_summary.txt'
    'reports/player_color_candidates.csv'
    'reports/player_color_candidates_summary.txt'
    'reports/player_color_intersection.csv'
    'reports/player_color_intersection_summary.txt'
    'reports/player_color_material_evidence.csv'
    'reports/player_color_material_evidence_summary.txt'
    'reports/player_color_mtrl_matches.csv'
    'reports/player_color_mtrl_matches_summary.txt'
    'reports/player_color_signal_matrix.csv'
    'reports/player_color_signal_matrix_v2.csv'
    'reports/player_color_signal_matrix_v2_summary.txt'
    'reports/noalphatest_groups.txt'
    'reports/noalphatest_without_ct4.csv'
    'reports/noalphatest_without_ct4_material_signals.csv'
    'reports/noalphatest_without_ct4_material_signals.txt'
    'reports/noalphatest_without_ct4_summary.txt'
    'reports/patched_to_verify_inventory.csv'
)

# Retain only the latest useful analysis/repro scripts under AoMEE/scripts.
$keepScripts = @(
    'extract_all_ddt.ps1'
    'inventory_tga.ps1'
    'master_classification.ps1'
    'mtrl_batch_convert_v2.ps1'
    'bti_metadata_analysis.ps1'
    'ct4_alphatest_reconciliation.ps1'
    'ct4_texture_analysis.ps1'
    'mtrl_player_color_candidates_v2.ps1'
    'mtrl_secondary_filter_map.ps1'
    'noalphatest_analysis.ps1'
    'nomip_classification.ps1'
    'nomip_tex_test.ps1'
    'player_color_alpha.ps1'
    'player_color_intersection.ps1'
    'player_color_signal_matrix_v3.ps1'
    'player_color_validation.ps1'
    'scan_bti.ps1'
    'build_remaster_benchmark.ps1'
    'cleanup_repository.ps1'
)

$trackedScripts = @(git ls-files -- 'AoMEE/scripts/*.ps1')
$removeScripts = @()

foreach ($path in $trackedScripts) {
    $leaf = Split-Path -Leaf $path
    if ($path -like 'AoMEE/scripts/*.ps1' -and $keepScripts -notcontains $leaf) {
        $removeScripts += $path
    }
    elseif ($path -like 'AoMEE/scripts/*/*.ps1') {
        $removeScripts += $path
    }
}

foreach ($path in $removeScripts) {
    if ($Apply) {
        git rm -f --ignore-unmatch -- $path | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to remove: $path" }
    }
    Show-Action "REMOVE" $path
}

Write-Host ""
Write-Host "============================================"
if ($Apply) {
    Write-Host "CLEANUP APPLIED"
    Write-Host ""
    Write-Host "Next:"
    Write-Host "  git status --short"
    Write-Host "  git diff --stat"
    Write-Host "  git add AoMEE"
    Write-Host "  git commit -m ""Clean AoMEE remaster reference repo"""
} else {
    Write-Host "DRY RUN COMPLETE"
    Write-Host "Run with -Apply to make the changes."
}
Write-Host "============================================"
