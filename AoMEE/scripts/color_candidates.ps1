$Project = "D:\AI_upscaling\AoMEE"

$CandidatesCsv = "$Project\reports\player_color_candidates.csv"
$MaterialsRoot = "$Project\Age of Mythology"
$OutCsv = "$Project\reports\player_color_material_evidence.csv"
$OutTxt = "$Project\reports\player_color_material_evidence_summary.txt"

if (-not (Test-Path $CandidatesCsv)) {
    Write-Host "ERROR: Candidate CSV not found:"
    Write-Host $CandidatesCsv
    exit 1
}

if (-not (Test-Path $MaterialsRoot)) {
    Write-Host "ERROR: Game directory not found:"
    Write-Host $MaterialsRoot
    exit 1
}

$candidates = Import-Csv $CandidatesCsv

# Build a lookup using the texture filename WITHOUT .tga.
$candidateLookup = @{}

foreach ($c in $candidates) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($c.Filename).Trim().ToLowerInvariant()

    if (-not $candidateLookup.ContainsKey($baseName)) {
        $candidateLookup[$baseName] = @()
    }

    $candidateLookup[$baseName] += $c
}

Write-Host "Candidates loaded: $($candidates.Count)"
Write-Host "Scanning material XML..."

$results = New-Object System.Collections.Generic.List[object]

$xmlFiles = Get-ChildItem `
    -Path $MaterialsRoot `
    -Recurse `
    -Filter "*.mtrl.xml" `
    -File `
    -ErrorAction SilentlyContinue

Write-Host "Material files found: $($xmlFiles.Count)"

$count = 0

foreach ($file in $xmlFiles) {

    $count++

    if (($count % 500) -eq 0) {
        Write-Host "Processed $count / $($xmlFiles.Count)..."
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
    }
    catch {
        continue
    }

    # Find every <texture> node.
    $textureNodes = $xml.SelectNodes("//texture")

    foreach ($textureNode in $textureNodes) {

        if ($null -eq $textureNode) {
            continue
        }

        $textureName = $textureNode.InnerText.Trim()

        if ([string]::IsNullOrWhiteSpace($textureName)) {
            continue
        }

        $key = [System.IO.Path]::GetFileNameWithoutExtension($textureName).Trim().ToLowerInvariant()

        if (-not $candidateLookup.ContainsKey($key)) {
            continue
        }

        # Find the nearest material node containing this texture.
        $materialNode = $textureNode.ParentNode

        while ($null -ne $materialNode -and $materialNode.Name -notin @(
            "material",
            "mtrl"
        )) {
            $materialNode = $materialNode.ParentNode
        }

        $colorTransform = ""

        if ($null -ne $materialNode) {
            $ctNode = $materialNode.SelectSingleNode(".//color_transform")

            if ($null -ne $ctNode) {
                $colorTransform = $ctNode.InnerText.Trim()
            }
        }

        # Also check the nearest ancestor if the XML uses a different structure.
        if ([string]::IsNullOrWhiteSpace($colorTransform)) {
            $ancestor = $textureNode.ParentNode

            while ($null -ne $ancestor) {

                $ctNode = $ancestor.SelectSingleNode("./color_transform")

                if ($null -ne $ctNode) {
                    $colorTransform = $ctNode.InnerText.Trim()
                    break
                }

                $ancestor = $ancestor.ParentNode
            }
        }

        foreach ($candidate in $candidateLookup[$key]) {

            $results.Add(
                [PSCustomObject]@{
                    Filename        = $candidate.Filename
                    Category        = $candidate.Category
                    CandidateAlpha  = $candidate.AlphaValueCount
                    OpaquePixels    = $candidate.OpaquePixels
                    OpaqueCoverage  = $candidate.OpaqueCoveragePct
                    MaterialFile    = $file.FullName
                    TextureReference= $textureName
                    ColorTransform  = $colorTransform
                }
            )
        }
    }
}

$results |
    Sort-Object Filename, ColorTransform, MaterialFile |
    Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8

# Summary
$summary = @()

$summary += "AoM:EE Player-Color Material Evidence"
$summary += "====================================="
$summary += ""
$summary += "Candidate textures: $($candidates.Count)"
$summary += "Material references found: $($results.Count)"
$summary += ""

$summary += "CANDIDATES WITH MATERIAL REFERENCES"
$summary += "-----------------------------------"

$matched = $results |
    Group-Object Filename |
    Sort-Object Name

$summary += "Matched textures: $($matched.Count)"
$summary += "Unmatched textures: $($candidates.Count - $matched.Count)"
$summary += ""

$summary += "COLOR TRANSFORM COUNTS"
$summary += "----------------------"

$results |
    Group-Object ColorTransform |
    Sort-Object Name |
    ForEach-Object {
        $name = $_.Name
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = "(blank)"
        }

        $summary += ("{0,-20} {1,6}" -f $name, $_.Count)
    }

$summary += ""
$summary += "CANDIDATES REFERENCED WITH COLOR_TRANSFORM 4"
$summary += "--------------------------------------------"

$ct4 = $results |
    Where-Object { $_.ColorTransform -eq "4" } |
    Group-Object Filename |
    Sort-Object Name

$summary += "Textures: $($ct4.Count)"
$summary += ""

foreach ($g in $ct4) {
    $summary += $g.Name
}

$summary += ""
$summary += "CANDIDATES WITHOUT COLOR_TRANSFORM 4"
$summary += "-------------------------------------"

$nonCt4 = $candidates |
    Where-Object {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Filename).Trim().ToLowerInvariant()

        -not (
            $results |
            Where-Object {
                $_.Filename -eq $_.Filename
            }
        )
    }

$summary += "(Detailed per-texture evidence is in the CSV.)"

$summary | Set-Content -Path $OutTxt -Encoding UTF8

Write-Host ""
Write-Host "DONE"
Write-Host "----"
Write-Host "CSV:"
Write-Host $OutCsv
Write-Host ""
Write-Host "Summary:"
Write-Host $OutTxt
Write-Host ""
Write-Host "Material references: $($results.Count)"
Write-Host "Textures referenced with ColorTransform 4: $($ct4.Count)"