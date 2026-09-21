$ErrorActionPreference = 'Stop'

# ============================================================
# AoM:EE Visual Model Comparison
#
# Creates a new ChaiNNer graph from the already validated
# Greek four-model graph.
#
# ONLY changes:
#   - input directory
#   - four output directories
#
# Model checkpoints and processing settings are preserved.
#
# ============================================================

$Root = 'D:\AI_upscaling\AoMEE'

$Template = Join-Path `
    $Root `
    'tests\greek_model_comparison\AoMEE textures upscaling.chn'

$TestRoot = Join-Path `
    $Root `
    'tests\visual_model_comparison'

$InputDir = Join-Path `
    $TestRoot `
    'original'

$OutputFile = Join-Path `
    $TestRoot `
    'AoMEE visual model comparison.chn'

# ------------------------------------------------------------
# Verify template and input
# ------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Template -PathType Leaf)) {
    throw "Template ChaiNNer graph not found:`n$Template"
}

if (-not (Test-Path -LiteralPath $InputDir -PathType Container)) {
    throw "Visual benchmark input folder not found:`n$InputDir"
}

# ------------------------------------------------------------
# Create output folders
# ------------------------------------------------------------

$Models = @(
    'HAT'
    'SwinIR'
    'DRCT'
    'DAT'
)

foreach ($Model in $Models) {

    $OutputDir = Join-Path `
        $TestRoot `
        $Model

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $OutputDir |
        Out-Null
}

# ------------------------------------------------------------
# Load graph
# ------------------------------------------------------------

$jsonText = Get-Content `
    -LiteralPath $Template `
    -Raw `
    -Encoding UTF8

$Graph = $jsonText | ConvertFrom-Json

$Nodes = @($Graph.content.nodes)

# ------------------------------------------------------------
# Find Load Images node
# ------------------------------------------------------------

$LoadImages = @(
    $Nodes |
        Where-Object {
            $_.data.schemaId -eq 'chainner:image:load_images'
        }
)

if ($LoadImages.Count -ne 1) {
    throw `
        "Expected exactly one Load Images node; found $($LoadImages.Count)."
}

$LoadImages[0].data.inputData.'0' = $InputDir

# ------------------------------------------------------------
# Verify four model nodes
# ------------------------------------------------------------

$ModelNodes = @(
    $Nodes |
        Where-Object {
            $_.data.schemaId -eq 'chainner:pytorch:load_model'
        }
)

if ($ModelNodes.Count -ne 4) {
    throw `
        "Expected exactly four Load Model nodes; found $($ModelNodes.Count)."
}

# ------------------------------------------------------------
# Verify model checkpoints remain unchanged
# ------------------------------------------------------------

$ExpectedModels = @{
    'HAT'    = 'D:\AI_upscaling\AoMEE\models\HAT\Real_HAT_GAN_sharper.pth'
    'SwinIR' = 'D:\AI_upscaling\AoMEE\models\SwinIR\001_classicalSR_DF2K_s64w8_SwinIR-M_x4.pth'
    'DRCT'   = 'D:\AI_upscaling\AoMEE\models\DRCT\DRCT-L_X4.pth'
    'DAT'    = 'D:\AI_upscaling\AoMEE\models\DAT\DAT_x4.pth'
}

foreach ($Name in $ExpectedModels.Keys) {

    $Matches = @(
        $ModelNodes |
            Where-Object {
                [string]$_.data.inputData.'0' `
                    -eq $ExpectedModels[$Name]
            }
    )

    if ($Matches.Count -ne 1) {
        throw `
            "Expected exactly one $Name model node with checkpoint:`n" +
            "$($ExpectedModels[$Name])`n" +
            "Found: $($Matches.Count)"
    }
}

# ------------------------------------------------------------
# Find four Save nodes
# ------------------------------------------------------------

$SaveNodes = @(
    $Nodes |
        Where-Object {
            $_.data.schemaId -eq 'chainner:image:save'
        }
)

if ($SaveNodes.Count -ne 4) {
    throw `
        "Expected exactly four Save nodes; found $($SaveNodes.Count)."
}

# ------------------------------------------------------------
# Change output folders.
#
# The existing graph is authoritative for which save node belongs
# to which model. We identify each by its current Greek output path.
# ------------------------------------------------------------

foreach ($SaveNode in $SaveNodes) {

    $CurrentPath = [string]$SaveNode.data.inputData.'1'

    $MatchedModel = $null

    foreach ($Model in $Models) {

        if (
            $CurrentPath.ToLower().EndsWith(
                '\' + $Model.ToLower()
            )
        ) {
            $MatchedModel = $Model
            break
        }
    }

    if ($null -eq $MatchedModel) {
        throw `
            "Could not identify model for Save node:`n$CurrentPath"
    }

    $NewOutput = Join-Path `
        $TestRoot `
        $MatchedModel

    $SaveNode.data.inputData.'1' = $NewOutput

    # Preserve every other Save-node setting exactly as it exists
    # in the validated Greek graph.
}

# ------------------------------------------------------------
# Final structural validation
# ------------------------------------------------------------

$FinalLoadImages = @(
    $Nodes |
        Where-Object {
            $_.data.schemaId -eq 'chainner:image:load_images'
        }
)

if (
    $FinalLoadImages.Count -ne 1 -or
    [string]$FinalLoadImages[0].data.inputData.'0' -ne $InputDir
) {
    throw 'Final Load Images path validation failed.'
}

$FinalSaveNodes = @(
    $Nodes |
        Where-Object {
            $_.data.schemaId -eq 'chainner:image:save'
        }
)

foreach ($Model in $Models) {

    $ExpectedOutput = Join-Path `
        $TestRoot `
        $Model

    $Matches = @(
        $FinalSaveNodes |
            Where-Object {
                [string]$_.data.inputData.'1' `
                    -eq $ExpectedOutput
            }
    )

    if ($Matches.Count -ne 1) {
        throw `
            "Output validation failed for $Model."
    }
}

# ------------------------------------------------------------
# Serialize new graph
# ------------------------------------------------------------

$OutputJson = $Graph | ConvertTo-Json -Depth 100

[System.IO.File]::WriteAllText(
    $OutputFile,
    $OutputJson,
    [System.Text.UTF8Encoding]::new($false)
)

# ------------------------------------------------------------
# Report
# ------------------------------------------------------------

Write-Host ''
Write-Host '============================================' `
    -ForegroundColor Cyan

Write-Host 'AoM:EE VISUAL MODEL COMPARISON CHAIN' `
    -ForegroundColor Cyan

Write-Host '============================================' `
    -ForegroundColor Cyan

Write-Host ''

Write-Host 'Input:'
Write-Host "  $InputDir"

Write-Host ''

Write-Host 'Outputs:'

foreach ($Model in $Models) {

    Write-Host (
        "  {0}: {1}" -f `
        $Model, `
        (Join-Path $TestRoot $Model)
    )
}

Write-Host ''

Write-Host 'Models verified:'
Write-Host '  HAT    = Real_HAT_GAN_sharper.pth'
Write-Host '  SwinIR = 001_classicalSR_DF2K_s64w8_SwinIR-M_x4.pth'
Write-Host '  DRCT   = DRCT-L_X4.pth'
Write-Host '  DAT    = DAT_x4.pth'

Write-Host ''

Write-Host 'Graph:'
Write-Host "  $OutputFile"

Write-Host ''

Write-Host 'The original Greek graph was not modified.'
Write-Host 'The clean AoMEE installation was not modified.'
Write-Host ''