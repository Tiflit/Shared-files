$ErrorActionPreference = 'Stop'

$Root     = 'D:\AI_upscaling\AoMEE'
$TestRoot = Join-Path $Root 'tests\greek_model_comparison'
$Template = Join-Path $Root 'AoMEE textures upscaling.chn'
$ChainOut = Join-Path $TestRoot 'chains'

if (-not (Test-Path -LiteralPath $Template -PathType Leaf)) {
    throw "Existing ChaiNNer chain not found: $Template"
}

New-Item -ItemType Directory -Force -Path $ChainOut | Out-Null

$models = @(
    [PSCustomObject]@{
        Name = 'SwinIR'
        Checkpoint = 'D:\AI_upscaling\AoMEE\models\SwinIR\001_classicalSR_DF2K_s64w8_SwinIR-M_x4.pth'
    },
    [PSCustomObject]@{
        Name = 'DRCT'
        Checkpoint = 'D:\AI_upscaling\AoMEE\models\DRCT\DRCT-L_X4.pth'
    },
    [PSCustomObject]@{
        Name = 'DAT'
        Checkpoint = 'D:\AI_upscaling\AoMEE\models\DAT\DAT_x4.pth'
    }
)

$inputDir = Join-Path $TestRoot 'original'
$hatOut   = Join-Path $TestRoot 'HAT'

if (-not (Test-Path -LiteralPath $inputDir -PathType Container)) {
    throw "Greek comparison input folder not found: $inputDir`nRun prepare_greek_model_comparison.ps1 first."
}

foreach ($m in $models) {

    if (-not (Test-Path -LiteralPath $m.Checkpoint -PathType Leaf)) {
        throw "Checkpoint not found: $($m.Checkpoint)"
    }

    $candidateOut = Join-Path $TestRoot $m.Name
    New-Item -ItemType Directory -Force -Path $candidateOut | Out-Null
    New-Item -ItemType Directory -Force -Path $hatOut | Out-Null

    $json = Get-Content -LiteralPath $Template -Raw -Encoding UTF8 | ConvertFrom-Json

    $nodes = @($json.content.nodes)

    # ------------------------------------------------------------
    # Input folder: use exactly the same 24 Greek originals for
    # every candidate comparison.
    # ------------------------------------------------------------
    $loadImages = @(
        $nodes |
            Where-Object { $_.data.schemaId -eq 'chainner:image:load_images' }
    )

    if ($loadImages.Count -ne 1) {
        throw "Expected exactly one Load Images node, found $($loadImages.Count)."
    }

    $loadImages[0].data.inputData.'0' = $inputDir

    # ------------------------------------------------------------
    # Keep HAT Sharper as the fixed control.
    # Replace only the old HAT SRx4 model branch with the candidate.
    # ------------------------------------------------------------
    $modelNodes = @(
        $nodes |
        Where-Object { $_.data.schemaId -eq 'chainner:pytorch:load_model' }
    )

    if ($modelNodes.Count -ne 2) {
        throw "Expected exactly two Load Model nodes in the template, found $($modelNodes.Count)."
    }

    $candidateModel = @(
        $modelNodes |
            Where-Object {
                [string]$_.data.inputData.'0' -match 'Real_HAT_GAN_SRx4\.pth$'
            }
    )

    if ($candidateModel.Count -ne 1) {
        throw "Could not uniquely identify the HAT SRx4 model node; found $($candidateModel.Count)."
    }

    $candidateModel[0].data.inputData.'0' = $m.Checkpoint

    # ------------------------------------------------------------
    # Save nodes:
    #   HAT Sharper -> tests\greek_model_comparison\HAT
    #   Candidate   -> tests\greek_model_comparison\<Model>
    #
    # Also change output format from TGA to PNG. PNG is lossless and
    # keeps the initial visual comparison independent of DDT encoding.
    # ------------------------------------------------------------
    $saveNodes = @(
        $nodes |
        Where-Object { $_.data.schemaId -eq 'chainner:image:save' }
    )

    if ($saveNodes.Count -ne 2) {
        throw "Expected exactly two Save Image nodes in the template, found $($saveNodes.Count)."
    }

    $hatSave = @(
        $saveNodes |
            Where-Object {
                [string]$_.data.inputData.'1' -match 'HAT_sharper$'
            }
    )

    $oldCandidateSave = @(
        $saveNodes |
            Where-Object {
                [string]$_.data.inputData.'1' -match 'HAT_SRx4$'
            }
    )

    if ($hatSave.Count -ne 1 -or $oldCandidateSave.Count -ne 1) {
        throw "Could not uniquely identify the HAT Sharper and HAT SRx4 save nodes. HAT=$($hatSave.Count), candidate=$($oldCandidateSave.Count)."
    }

    $hatSave[0].data.inputData.'1' = $hatOut
    $hatSave[0].data.inputData.'4' = 'png'

    $oldCandidateSave[0].data.inputData.'1' = $candidateOut
    $oldCandidateSave[0].data.inputData.'4' = 'png'

    # ------------------------------------------------------------
    # Write a standalone .chn.
    # ------------------------------------------------------------
    $safeName = "Greek_HAT_vs_$($m.Name).chn"
    $chainPath = Join-Path $ChainOut $safeName

    $json |
        ConvertTo-Json -Depth 100 |
        Set-Content -LiteralPath $chainPath -Encoding UTF8

    Write-Host "Created: $chainPath" -ForegroundColor Green
}

# A small run manifest helps keep the comparison reproducible.
$manifest = @(
    [PSCustomObject]@{
        Chain = Join-Path $ChainOut 'Greek_HAT_vs_SwinIR.chn'
        Control = 'HAT Sharper'
        Candidate = 'SwinIR-M Classical SR x4'
    }
    [PSCustomObject]@{
        Chain = Join-Path $ChainOut 'Greek_HAT_vs_DRCT.chn'
        Control = 'HAT Sharper'
        Candidate = 'DRCT-L x4'
    }
    [PSCustomObject]@{
        Chain = Join-Path $ChainOut 'Greek_HAT_vs_DAT.chn'
        Control = 'HAT Sharper'
        Candidate = 'DAT x4'
    }
)

$manifest |
    Export-Csv -LiteralPath (Join-Path $ChainOut 'chain_manifest.csv') `
              -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host 'AoM:EE GREEK COMPARISON CHAINS CREATED' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "Chain folder: $ChainOut"
Write-Host ''
Write-Host 'Each chain runs HAT Sharper + one candidate on the SAME 24 inputs.'
Write-Host 'Alpha remains on the existing nearest-neighbour branch.'
Write-Host 'Outputs are PNG for the initial lossless visual comparison.'
