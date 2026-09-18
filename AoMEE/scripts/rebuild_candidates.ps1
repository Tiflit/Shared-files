$Project = "D:\AI_upscaling\AoMEE"

$Usage      = "$Project\reports\mtrl_texture_usage.csv"
$Candidates = "$Project\reports\player_color_candidates.csv"

$OutCsv = "$Project\reports\mtrl_player_color_candidates_fixed.csv"
$OutTxt = "$Project\reports\mtrl_player_color_candidates_fixed_summary.txt"

if (-not (Test-Path $Usage)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Usage
    exit
}

if (-not (Test-Path $Candidates)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Candidates
    exit
}

Write-Host ""
Write-Host "Loading candidate list..."

$candidateRows = Import-Csv -LiteralPath $Candidates

$candidateLookup = @{}

foreach ($c in $candidateRows) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension(
        $c.Filename
    )

    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $candidateLookup[$name.Trim().ToLowerInvariant()] = $c
    }
}

Write-Host "Candidates: $($candidateLookup.Count)"
Write-Host ""
Write-Host "Reading material usage table..."

$usageRows = Import-Csv -LiteralPath $Usage

Write-Host "Usage rows: $($usageRows.Count)"
Write-Host ""

$results = @()

foreach ($u in $usageRows) {

    if ([string]::IsNullOrWhiteSpace($u.Texture)) {
        continue
    }

    $key = $u.Texture.Trim().ToLowerInvariant()

    if (-not $candidateLookup.ContainsKey($key)) {
        continue
    }

    $c = $candidateLookup[$key]

    $results += [PSCustomObject]@{
        CandidateFilename = $c.Filename
        Category          = $c.Category
        MaterialFile      = $u.MaterialFile
        Texture           = $u.Texture
        ColorTransform    = $u.ColorTransform
        PixelXForm        = $u.PixelXForm
    }
}

$results |
    Sort-Object CandidateFilename, MaterialFile |
    Export-Csv `
        -LiteralPath $OutCsv `
        -NoTypeInformation `
        -Encoding UTF8

$uniqueTextures = @(
    $results |
        Select-Object -ExpandProperty CandidateFilename -Unique
)

$uniqueMaterials = @(
    $results |
        Select-Object -ExpandProperty MaterialFile -Unique
)

$ct4Textures = @(
    $results |
        Where-Object { $_.ColorTransform -eq "4" } |
        Select-Object -ExpandProperty CandidateFilename -Unique
)

$ct0Textures = @(
    $results |
        Where-Object { $_.ColorTransform -eq "0" } |
        Select-Object -ExpandProperty CandidateFilename -Unique
)

$both = @()

foreach ($name in $uniqueTextures) {

    $has0 = $results |
        Where-Object {
            $_.CandidateFilename -eq $name -and
            $_.ColorTransform -eq "0"
        }

    $has4 = $results |
        Where-Object {
            $_.CandidateFilename -eq $name -and
            $_.ColorTransform -eq "4"
        }

    if ($has0 -and $has4) {
        $both += $name
    }
}

$out = @()

$out += "AoM:EE Player-Color Candidate Material Analysis"
$out += "================================================"
$out += ""
$out += "Candidate textures: $($candidateLookup.Count)"
$out += "Material/texture references: $($results.Count)"
$out += "Unique candidate textures matched: $($uniqueTextures.Count)"
$out += "Unique material files involved: $($uniqueMaterials.Count)"
$out += ""
$out += "Unique candidates with CT0: $($ct0Textures.Count)"
$out += "Unique candidates with CT4: $($ct4Textures.Count)"
$out += "Unique candidates with BOTH CT0 and CT4: $($both.Count)"
$out += ""

$out += "BY CATEGORY"
$out += "-----------"

$results |
    Group-Object Category |
    Sort-Object Name |
    ForEach-Object {
        $out += ("{0,-22} {1,6}" -f $_.Name, $_.Count)
    }

$out += ""
$out += "CANDIDATES WITH CT4"
$out += "------------------"

$ct4Textures |
    Sort-Object |
    ForEach-Object {
        $out += $_
    }

$out += ""
$out += "CANDIDATES WITH BOTH CT0 AND CT4"
$out += "--------------------------------"

$both |
    Sort-Object |
    ForEach-Object {
        $out += $_
    }

$out += ""
$out += "OUTPUT"
$out += "------"
$out += $OutCsv
$out += $OutTxt

$out |
    Set-Content `
        -LiteralPath $OutTxt `
        -Encoding UTF8

Write-Host ""
Write-Host "=============================================="
Write-Host "DONE"
Write-Host "=============================================="
Write-Host ""
Write-Host "Material/texture references: $($results.Count)"
Write-Host "Unique candidate textures:   $($uniqueTextures.Count)"
Write-Host "Candidates with CT0:         $($ct0Textures.Count)"
Write-Host "Candidates with CT4:         $($ct4Textures.Count)"
Write-Host "Candidates with BOTH:        $($both.Count)"
Write-Host ""
Write-Host "Summary:"
Write-Host $OutTxt