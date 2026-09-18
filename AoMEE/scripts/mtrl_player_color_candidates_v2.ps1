$Project = "D:\AI_upscaling\AoMEE"

$XmlRoot    = "$Project\reports\materials_xml"
$Candidates = "$Project\reports\player_color_candidates.csv"

$OutUsage   = "$Project\reports\mtrl_texture_usage.csv"
$OutSummary = "$Project\reports\mtrl_texture_summary.csv"
$OutCand    = "$Project\reports\mtrl_player_color_candidates_v2.csv"
$OutTxt     = "$Project\reports\mtrl_texture_analysis_summary.txt"

if (-not (Test-Path $XmlRoot)) {
    Write-Host "ERROR: XML directory not found:"
    Write-Host $XmlRoot
    exit
}

if (-not (Test-Path $Candidates)) {
    Write-Host "ERROR: Candidate CSV not found:"
    Write-Host $Candidates
    exit
}

# ------------------------------------------------------------
# Candidate lookup
# ------------------------------------------------------------

$candidateRows = Import-Csv -LiteralPath $Candidates

$candidateLookup = @{}

foreach ($candidate in $candidateRows) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension(
        $candidate.Filename
    )

    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $candidateLookup[$name.Trim().ToLowerInvariant()] = $candidate
    }
}

Write-Host ""
Write-Host "Candidate textures: $($candidateLookup.Count)"
Write-Host ""

# ------------------------------------------------------------
# Find XML files
# ------------------------------------------------------------

$xmlFiles = Get-ChildItem `
    -LiteralPath $XmlRoot `
    -Recurse `
    -File `
    -Filter "*.mtrl.xml" `
    -ErrorAction Stop

$total = $xmlFiles.Count

Write-Host "XML files: $total"
Write-Host ""

# ------------------------------------------------------------
# Output writers
# ------------------------------------------------------------

$usageWriter = [System.IO.StreamWriter]::new(
    $OutUsage,
    $false,
    [System.Text.Encoding]::UTF8
)

$candidateWriter = [System.IO.StreamWriter]::new(
    $OutCand,
    $false,
    [System.Text.Encoding]::UTF8
)

$usageWriter.WriteLine(
    '"MaterialFile","Texture","ColorTransform","PixelXForm"'
)

$candidateWriter.WriteLine(
    '"Filename","Category","MaterialFile","Texture","ColorTransform","PixelXForm"'
)

# ------------------------------------------------------------
# Helper
# ------------------------------------------------------------

function CsvEscape {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    return '"' + ($Value -replace '"', '""') + '"'
}

# Texture statistics:
# key -> object
$textureStats = @{}

$textureMaterials = 0
$candidateMatches = 0
$ct4Materials = 0
$pixelXFormMaterials = 0
$failedFiles = 0

$number = 0

try {

    foreach ($file in $xmlFiles) {

        $number++

        if (($number % 1000) -eq 0) {
            Write-Host "Processed $number / $total"
        }

        try {
            $text = [System.IO.File]::ReadAllText(
                $file.FullName,
                [System.Text.Encoding]::UTF8
            )
        }
        catch {
            $failedFiles++
            continue
        }

        if ([string]::IsNullOrWhiteSpace($text)) {
            $failedFiles++
            continue
        }

        # ----------------------------------------------------
        # Extract texture
        # ----------------------------------------------------

        $textureMatch = [regex]::Match(
            $text,
            '(?is)<texture>\s*(.*?)\s*</texture>'
        )

        if (-not $textureMatch.Success) {
            continue
        }

        $texture = $textureMatch.Groups[1].Value.Trim()

        if ([string]::IsNullOrWhiteSpace($texture)) {
            continue
        }

        $textureMaterials++

        # ----------------------------------------------------
        # Extract color transform
        # ----------------------------------------------------

        $colorTransform = ""

        $ctMatch = [regex]::Match(
            $text,
            '(?is)<color_transform>\s*(.*?)\s*</color_transform>'
        )

        if ($ctMatch.Success) {
            $colorTransform = $ctMatch.Groups[1].Value.Trim()
        }

        if ($colorTransform -eq "4") {
            $ct4Materials++
        }

        # ----------------------------------------------------
        # Extract PixelXForm
        # ----------------------------------------------------

        $pixelXForm = ""

        $pxMatch = [regex]::Match(
            $text,
            '(?i)PixelXForm\d*'
        )

        if ($pxMatch.Success) {
            $pixelXForm = $pxMatch.Value
            $pixelXFormMaterials++
        }

        # ----------------------------------------------------
        # Texture key
        # ----------------------------------------------------

        $textureKey = $texture.Trim().ToLowerInvariant()

        # ----------------------------------------------------
        # Update texture statistics
        # ----------------------------------------------------

        if (-not $textureStats.ContainsKey($textureKey)) {

            $textureStats[$textureKey] = [PSCustomObject]@{
                Texture       = $texture
                Total         = 0
                CT0           = 0
                CT4           = 0
                OtherCT       = 0
                PixelXForm    = 0
            }
        }

        $stat = $textureStats[$textureKey]

        $stat.Total++

        if ($colorTransform -eq "0") {
            $stat.CT0++
        }
        elseif ($colorTransform -eq "4") {
            $stat.CT4++
        }
        else {
            $stat.OtherCT++
        }

        if (-not [string]::IsNullOrWhiteSpace($pixelXForm)) {
            $stat.PixelXForm++
        }

        # ----------------------------------------------------
        # Write usage row
        # ----------------------------------------------------

        $usageWriter.WriteLine(
            (
                "{0},{1},{2},{3}" -f
                (CsvEscape $file.FullName),
                (CsvEscape $texture),
                (CsvEscape $colorTransform),
                (CsvEscape $pixelXForm)
            )
        )

        # ----------------------------------------------------
        # Candidate match
        # ----------------------------------------------------

        if ($candidateLookup.ContainsKey($textureKey)) {

            $candidate = $candidateLookup[$textureKey]

            $candidateMatches++

            $candidateWriter.WriteLine(
                (
                    "{0},{1},{2},{3},{4},{5}" -f
                    (CsvEscape $candidate.Filename),
                    (CsvEscape $candidate.Category),
                    (CsvEscape $file.FullName),
                    (CsvEscape $texture),
                    (CsvEscape $colorTransform),
                    (CsvEscape $pixelXForm)
                )
            )
        }
    }

}
finally {

    $usageWriter.Close()
    $candidateWriter.Close()
}

# ------------------------------------------------------------
# Write texture summary CSV
# ------------------------------------------------------------

$textureStats.Values |
    Sort-Object Texture |
    Export-Csv `
        -LiteralPath $OutSummary `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Create human-readable summary
# ------------------------------------------------------------

$summary = @()

$summary += "AoM:EE MTRL Texture Usage Analysis"
$summary += "=================================="
$summary += ""
$summary += "XML files scanned: $total"
$summary += "Files that could not be read: $failedFiles"
$summary += "Materials with texture field: $textureMaterials"
$summary += "Materials with ColorTransform 4: $ct4Materials"
$summary += "Materials with PixelXForm: $pixelXFormMaterials"
$summary += ""
$summary += "Unique texture names: $($textureStats.Count)"
$summary += "Candidate texture/material matches: $candidateMatches"
$summary += ""

$summary += "TEXTURES USED WITH COLOR_TRANSFORM 4"
$summary += "------------------------------------"

$ct4Textures = @(
    $textureStats.Values |
        Where-Object { $_.CT4 -gt 0 } |
        Sort-Object Texture
)

$summary += "Unique textures: $($ct4Textures.Count)"
$summary += ""

foreach ($s in $ct4Textures) {

    $summary += (
        "{0,-55} Total={1,5} CT0={2,5} CT4={3,5} Other={4,5}" -f `
        $s.Texture,
        $s.Total,
        $s.CT0,
        $s.CT4,
        $s.OtherCT
    )
}

$summary += ""
$summary += "PLAYER-COLOR CANDIDATES WITH CT4 USAGE"
$summary += "---------------------------------------"

$candidateCt4 = @()

foreach ($s in $candidateRows) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension(
        $s.Filename
    ).Trim().ToLowerInvariant()

    if ($textureStats.ContainsKey($name)) {

        $stat = $textureStats[$name]

        if ($stat.CT4 -gt 0) {

            $candidateCt4 += $stat
        }
    }
}

$candidateCt4 |
    Sort-Object Texture |
    ForEach-Object {

        $summary += (
            "{0,-55} Total={1,5} CT0={2,5} CT4={3,5}" -f `
            $_.Texture,
            $_.Total,
            $_.CT0,
            $_.CT4
        )
    }

$summary += ""
$summary += "PLAYER-COLOR CANDIDATES WITH NO CT4 USAGE"
$summary += "------------------------------------------"

$candidateNoCt4 = @()

foreach ($s in $candidateRows) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension(
        $s.Filename
    ).Trim().ToLowerInvariant()

    if ($textureStats.ContainsKey($name)) {

        $stat = $textureStats[$name]

        if ($stat.CT4 -eq 0) {

            $candidateNoCt4 += $stat
        }
    }
}

$candidateNoCt4 |
    Sort-Object Texture |
    ForEach-Object {

        $summary += (
            "{0,-55} Total={1,5} CT0={2,5} Other={3,5}" -f `
            $_.Texture,
            $_.Total,
            $_.OtherCT
        )
    }

$summary += ""
$summary += "OUTPUT"
$summary += "------"
$summary += $OutUsage
$summary += $OutSummary
$summary += $OutCand
$summary += $OutTxt

$summary |
    Set-Content `
        -LiteralPath $OutTxt `
        -Encoding UTF8

Write-Host ""
Write-Host "=============================================="
Write-Host "DONE"
Write-Host "=============================================="
Write-Host ""
Write-Host "XML files scanned:      $total"
Write-Host "Unread/failed:          $failedFiles"
Write-Host "Materials with texture: $textureMaterials"
Write-Host "Unique textures:        $($textureStats.Count)"
Write-Host "CT4 materials:          $ct4Materials"
Write-Host "PixelXForm materials:   $pixelXFormMaterials"
Write-Host "Candidate matches:      $candidateMatches"
Write-Host ""
Write-Host "Summary:"
Write-Host $OutTxt