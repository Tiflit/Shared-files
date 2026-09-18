$Project = "D:\AI_upscaling\AoMEE"

$XmlRoot   = "$Project\reports\materials_xml"
$Candidates = "$Project\reports\player_color_candidates.csv"

$OutIndex   = "$Project\reports\mtrl_material_index.csv"
$OutMatches = "$Project\reports\mtrl_player_color_candidates.csv"
$OutSummary = "$Project\reports\mtrl_material_index_summary.txt"

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

foreach ($row in $candidateRows) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension($row.Filename)

    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $candidateLookup[$name.ToLowerInvariant()] = $row
    }
}

Write-Host ""
Write-Host "Candidate textures: $($candidateLookup.Count)"
Write-Host ""

# ------------------------------------------------------------
# XML files
# ------------------------------------------------------------

$xmlFiles = Get-ChildItem `
    -LiteralPath $XmlRoot `
    -Recurse `
    -File `
    -Filter "*.mtrl.xml" `
    -ErrorAction Stop

$total = $xmlFiles.Count

Write-Host "XML files found: $total"
Write-Host ""

# ------------------------------------------------------------
# CSV helper
# ------------------------------------------------------------

function CsvEscape {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    $Value = $Value -replace '"', '""'

    return '"' + $Value + '"'
}

# ------------------------------------------------------------
# Output files
# ------------------------------------------------------------

$indexWriter = [System.IO.StreamWriter]::new(
    $OutIndex,
    $false,
    [System.Text.Encoding]::UTF8
)

$matchWriter = [System.IO.StreamWriter]::new(
    $OutMatches,
    $false,
    [System.Text.Encoding]::UTF8
)

try {

    # Headers
    $indexWriter.WriteLine(
        '"MaterialFile","Texture","SecondaryTexture","Bumpmap","Specmap","Glossmap","EmissiveMap","ColorTransform","Flags","PixelXForm"'
    )

    $matchWriter.WriteLine(
        '"CandidateFilename","Category","MaterialFile","Texture","ColorTransform","Flags","PixelXForm"'
    )

    $ctCounts = @{}
    $textureCount = 0
    $candidateMatches = 0
    $pixelXFormCount = 0
    $processed = 0

    foreach ($file in $xmlFiles) {

        $processed++

        if (($processed % 1000) -eq 0) {
            Write-Host "Processed $processed / $total"
        }

        try {
            $text = Get-Content `
                -LiteralPath $file.FullName `
                -Raw `
                -ErrorAction Stop
        }
        catch {
            continue
        }

        # ----------------------------------------------------
        # Extract fields
        # ----------------------------------------------------

        $texture = ""
        $secondary = ""
        $bumpmap = ""
        $specmap = ""
        $glossmap = ""
        $emissive = ""
        $colorTransform = ""
        $flags = ""
        $pixelXForm = ""

        $m = [regex]::Match(
            $text,
            '(?is)<texture>\s*(.*?)\s*</texture>'
        )
        if ($m.Success) {
            $texture = $m.Groups[1].Value.Trim()
        }

        $m = [regex]::Match(
            $text,
            '(?is)<secondary_texture>\s*(.*?)\s*</secondary_texture>'
        )
        if ($m.Success) {
            $secondary = $m.Groups[1].Value.Trim()
        }

        $m = [regex]::Match(
            $text,
            '(?is)<bumpmap>\s*(.*?)\s*</bumpmap>'
        )
        if ($m.Success) {
            $bumpmap = $m.Groups[1].Value.Trim()
        }

        $m = [regex]::Match(
            $text,
            '(?is)<specmap>\s*(.*?)\s*</specmap>'
        )
        if ($m.Success) {
            $specmap = $m.Groups[1].Value.Trim()
        }

        $m = [regex]::Match(
            $text,
            '(?is)<glossmap>\s*(.*?)\s*</glossmap>'
        )
        if ($m.Success) {
            $glossmap = $m.Groups[1].Value.Trim()
        }

        $m = [regex]::Match(
            $text,
            '(?is)<emissivemap>\s*(.*?)\s*</emissivemap>'
        )
        if ($m.Success) {
            $emissive = $m.Groups[1].Value.Trim()
        }

        $m = [regex]::Match(
            $text,
            '(?is)<color_transform>\s*(.*?)\s*</color_transform>'
        )
        if ($m.Success) {
            $colorTransform = $m.Groups[1].Value.Trim()
        }

        $m = [regex]::Match(
            $text,
            '(?is)<flags>\s*(.*?)\s*</flags>'
        )
        if ($m.Success) {
            $flags = $m.Groups[1].Value.Trim()
            $flags = $flags -replace '\s+', ' '
        }

        $pxMatches = [regex]::Matches(
            $text,
            '(?i)PixelXForm\d*'
        )

        if ($pxMatches.Count -gt 0) {

            $px = @()

            foreach ($pxMatch in $pxMatches) {
                if (-not ($px -contains $pxMatch.Value)) {
                    $px += $pxMatch.Value
                }
            }

            $pixelXForm = $px -join '; '
            $pixelXFormCount++
        }

        if (-not [string]::IsNullOrWhiteSpace($texture)) {
            $textureCount++
        }

        # Count color transforms.
        $ctKey = $colorTransform

        if ([string]::IsNullOrWhiteSpace($ctKey)) {
            $ctKey = "(blank)"
        }

        if ($ctCounts.ContainsKey($ctKey)) {
            $ctCounts[$ctKey]++
        }
        else {
            $ctCounts[$ctKey] = 1
        }

        # ----------------------------------------------------
        # Write material index row
        # ----------------------------------------------------

        $indexWriter.WriteLine(
            (
                "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f
                (CsvEscape $file.FullName),
                (CsvEscape $texture),
                (CsvEscape $secondary),
                (CsvEscape $bumpmap),
                (CsvEscape $specmap),
                (CsvEscape $glossmap),
                (CsvEscape $emissive),
                (CsvEscape $colorTransform),
                (CsvEscape $flags),
                (CsvEscape $pixelXForm)
            )
        )

        # ----------------------------------------------------
        # Check candidate texture
        # ----------------------------------------------------

        if (-not [string]::IsNullOrWhiteSpace($texture)) {

            $textureKey = [System.IO.Path]::GetFileNameWithoutExtension(
                $texture
            ).ToLowerInvariant()

            if ($candidateLookup.ContainsKey($textureKey)) {

                $candidate = $candidateLookup[$textureKey]
                $candidateMatches++

                $matchWriter.WriteLine(
                    (
                        "{0},{1},{2},{3},{4},{5},{6}" -f
                        (CsvEscape $candidate.Filename),
                        (CsvEscape $candidate.Category),
                        (CsvEscape $file.FullName),
                        (CsvEscape $texture),
                        (CsvEscape $colorTransform),
                        (CsvEscape $flags),
                        (CsvEscape $pixelXForm)
                    )
                )
            }
        }
    }
}
finally {

    $indexWriter.Close()
    $matchWriter.Close()
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$summary = @()

$summary += "AoM:EE MTRL Material Index"
$summary += "=========================="
$summary += ""
$summary += "XML files scanned: $total"
$summary += "Materials with texture field: $textureCount"
$summary += "Candidate texture/material matches: $candidateMatches"
$summary += "Materials containing PixelXForm: $pixelXFormCount"
$summary += ""

$summary += "COLOR TRANSFORM COUNTS"
$summary += "----------------------"

$ctCounts.GetEnumerator() |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,8}" -f $_.Key, $_.Value)
    }

$summary += ""
$summary += "OUTPUT"
$summary += "------"
$summary += $OutIndex
$summary += $OutMatches
$summary += $OutSummary

$summary |
    Set-Content `
        -LiteralPath $OutSummary `
        -Encoding UTF8

Write-Host ""
Write-Host "=============================================="
Write-Host "DONE"
Write-Host "=============================================="
Write-Host ""
Write-Host "XML files scanned: $total"
Write-Host "Materials with texture: $textureCount"
Write-Host "Candidate matches: $candidateMatches"
Write-Host "Materials with PixelXForm: $pixelXFormCount"
Write-Host ""
Write-Host "Summary:"
Write-Host $OutSummary