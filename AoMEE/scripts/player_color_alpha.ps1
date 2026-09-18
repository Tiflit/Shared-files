$Project = "D:\AI_upscaling\AoMEE"
$Reports = Join-Path $Project "reports"

$CandidateFile = Join-Path $Reports "player_color_texture_set.csv"
$TgaInventory  = Join-Path $Reports "tga_classification.csv"

$OutputCsv = Join-Path $Reports "player_color_alpha_analysis.csv"
$SummaryTxt = Join-Path $Reports "player_color_alpha_analysis_summary.txt"

if (-not (Test-Path $CandidateFile)) {
    throw "Candidate file not found: $CandidateFile"
}

if (-not (Test-Path $TgaInventory)) {
    throw "TGA classification file not found: $TgaInventory"
}

Write-Host "Loading candidate textures..."
$candidates = Import-Csv $CandidateFile

Write-Host "Loading TGA inventory..."
$inventory = Import-Csv $TgaInventory

# Build a lookup by TGA filename without extension.
$lookup = @{}

foreach ($row in $inventory) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension([string]$row.Filename)

    if ([string]::IsNullOrWhiteSpace($name)) {
        continue
    }

    $key = $name.ToLowerInvariant()

    if (-not $lookup.ContainsKey($key)) {
        $lookup[$key] = New-Object System.Collections.Generic.List[object]
    }

    $lookup[$key].Add($row)
}

$results = New-Object System.Collections.Generic.List[object]
$missing = New-Object System.Collections.Generic.List[string]
$duplicates = New-Object System.Collections.Generic.List[string]

foreach ($candidate in $candidates) {

    # The player_color_texture_set.csv uses "Texture".
    $texture = [string]$candidate.Texture

    if ([string]::IsNullOrWhiteSpace($texture)) {
        continue
    }

    $key = $texture.ToLowerInvariant()

    if (-not $lookup.ContainsKey($key)) {
        $missing.Add($texture)
        continue
    }

    $matches = $lookup[$key]

    if ($matches.Count -gt 1) {
        $duplicates.Add("$texture`t$($matches.Count)")
    }

    foreach ($row in $matches) {

        $width  = [int]$row.Width
        $height = [int]$row.Height
        $pixels = [int]$row.Pixels

        $transparent = [int]$row.TransparentPixels
        $partial     = [int]$row.PartialAlphaPixels
        $opaque      = [int]$row.OpaquePixels

        if ($pixels -gt 0) {
            $transparentPct = ($transparent / $pixels) * 100
            $partialPct     = ($partial / $pixels) * 100
            $opaquePct       = ($opaque / $pixels) * 100
            $nonTransparent = $partial + $opaque
            $nonTransparentPct = ($nonTransparent / $pixels) * 100
        }
        else {
            $transparentPct = 0
            $partialPct = 0
            $opaquePct = 0
            $nonTransparentPct = 0
        }

        # This is the important metric for our RGB-preservation operation:
        # every pixel where original alpha > 0 would have its original RGB restored.
        if ($nonTransparent -eq 0) {
            $maskClass = "FullyTransparent"
        }
        elseif ($transparent -eq 0) {
            $maskClass = "FullyOpaque"
        }
        elseif ($partial -eq 0) {
            if ($nonTransparentPct -le 1) {
                $maskClass = "BinaryVerySparse"
            }
            elseif ($nonTransparentPct -le 5) {
                $maskClass = "BinarySparse"
            }
            elseif ($nonTransparentPct -le 25) {
                $maskClass = "BinaryModerate"
            }
            elseif ($nonTransparentPct -le 75) {
                $maskClass = "BinaryBroad"
            }
            else {
                $maskClass = "BinaryVeryBroad"
            }
        }
        else {
            if ($nonTransparentPct -le 5) {
                $maskClass = "GradedSparse"
            }
            elseif ($nonTransparentPct -le 25) {
                $maskClass = "GradedModerate"
            }
            elseif ($nonTransparentPct -le 75) {
                $maskClass = "GradedBroad"
            }
            else {
                $maskClass = "GradedVeryBroad"
            }
        }

        $results.Add([PSCustomObject]@{
            Texture              = $texture
            Filename             = $row.Filename
            Path                 = $row.Path
            Width                = $width
            Height               = $height
            Pixels               = $pixels
            HasAlpha             = $row.HasAlpha
            AlphaValueCount      = $row.AlphaValueCount
            TransparentPixels    = $transparent
            PartialAlphaPixels   = $partial
            OpaquePixels         = $opaque
            TransparentPct       = [math]::Round($transparentPct, 4)
            PartialPct           = [math]::Round($partialPct, 4)
            OpaquePct             = [math]::Round($opaquePct, 4)
            NonTransparentPct    = [math]::Round($nonTransparentPct, 4)
            MaskClass             = $maskClass

            # Preserve material metadata from the candidate set where available.
            AlphaBits             = $candidate.AlphaBits
            CT0                    = $candidate.CT0
            CT4                    = $candidate.CT4
            NoAlphaTest            = $candidate.NoAlphaTest
        })
    }
}

$results |
    Sort-Object Texture |
    Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8

# -------------------------
# Build summary
# -------------------------

$summary = New-Object System.Collections.Generic.List[string]

$summary.Add("AoM:EE Player-Color Candidate Alpha Analysis")
$summary.Add("============================================")
$summary.Add("")
$summary.Add("Candidate textures: $($candidates.Count)")
$summary.Add("Matched TGAs:       $($results.Count)")
$summary.Add("Missing TGAs:       $($missing.Count)")
$summary.Add("Duplicate names:    $($duplicates.Count)")
$summary.Add("")

$summary.Add("MASK CLASS DISTRIBUTION")
$summary.Add("-----------------------")

$results |
    Group-Object MaskClass |
    Sort-Object Name |
    ForEach-Object {
        $summary.Add(("{0,-22} {1,5}" -f $_.Name, $_.Count))
    }

$summary.Add("")
$summary.Add("NON-TRANSPARENT COVERAGE")
$summary.Add("------------------------")

$bins = @(
    @{ Name = "0%";           Min = 0;  Max = 0 },
    @{ Name = "0-1%";         Min = 0;  Max = 1 },
    @{ Name = "1-5%";         Min = 1;  Max = 5 },
    @{ Name = "5-10%";        Min = 5;  Max = 10 },
    @{ Name = "10-25%";       Min = 10; Max = 25 },
    @{ Name = "25-50%";       Min = 25; Max = 50 },
    @{ Name = "50-75%";       Min = 50; Max = 75 },
    @{ Name = "75-90%";       Min = 75; Max = 90 },
    @{ Name = "90-100%";      Min = 90; Max = 100 }
)

foreach ($bin in $bins) {

    if ($bin.Name -eq "0%") {
        $count = @(
            $results |
            Where-Object { $_.NonTransparentPct -eq 0 }
        ).Count
    }
    else {
        $count = @(
            $results |
            Where-Object {
                $_.NonTransparentPct -gt $bin.Min -and
                $_.NonTransparentPct -le $bin.Max
            }
        ).Count
    }

    $summary.Add(("{0,-12} {1,5}" -f $bin.Name, $count))
}

$summary.Add("")
$summary.Add("ALPHA VALUE COUNTS")
$summary.Add("------------------")

$results |
    Group-Object AlphaValueCount |
    Sort-Object { [int]$_.Name } |
    ForEach-Object {
        $summary.Add(("{0,-12} {1,5}" -f $_.Name, $_.Count))
    }

$summary.Add("")
$summary.Add("FULLY OPAQUE TEXTURES")
$summary.Add("----------------------")

$results |
    Where-Object { $_.MaskClass -eq "FullyOpaque" } |
    Sort-Object Texture |
    ForEach-Object {
        $summary.Add($_.Texture)
    }

$summary.Add("")
$summary.Add("FULLY TRANSPARENT TEXTURES")
$summary.Add("--------------------------")

$results |
    Where-Object { $_.MaskClass -eq "FullyTransparent" } |
    Sort-Object Texture |
    ForEach-Object {
        $summary.Add($_.Texture)
    }

$summary.Add("")
$summary.Add("VERY SPARSE MASKS (<=5% NON-TRANSPARENT)")
$summary.Add("----------------------------------------")

$results |
    Where-Object { $_.NonTransparentPct -gt 0 -and $_.NonTransparentPct -le 5 } |
    Sort-Object NonTransparentPct, Texture |
    ForEach-Object {
        $summary.Add(("{0,8:N3}%  {1}" -f $_.NonTransparentPct, $_.Texture))
    }

if ($missing.Count -gt 0) {
    $summary.Add("")
    $summary.Add("MISSING TGAS")
    $summary.Add("------------")

    foreach ($name in ($missing | Sort-Object)) {
        $summary.Add($name)
    }
}

if ($duplicates.Count -gt 0) {
    $summary.Add("")
    $summary.Add("DUPLICATE TGA BASENAMES")
    $summary.Add("-----------------------")

    foreach ($name in ($duplicates | Sort-Object)) {
        $summary.Add($name)
    }
}

$summary | Set-Content $SummaryTxt -Encoding UTF8

Write-Host ""
Write-Host "============================================"
Write-Host "Analysis complete."
Write-Host "Matched:   $($results.Count) / $($candidates.Count)"
Write-Host "Missing:   $($missing.Count)"
Write-Host "Duplicate: $($duplicates.Count)"
Write-Host ""
Write-Host "CSV:"
Write-Host $OutputCsv
Write-Host ""
Write-Host "Summary:"
Write-Host $SummaryTxt
Write-Host "============================================"