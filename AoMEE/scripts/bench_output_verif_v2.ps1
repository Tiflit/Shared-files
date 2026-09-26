$Root = 'D:\AI_upscaling\AoMEE\tests\remaster_benchmark'

$Manifest = Import-Csv "$Root\remaster_benchmark_manifest.csv"

$SharperFiles = Get-ChildItem "$Root\HAT_sharper" -Recurse -File
$SRx4Files    = Get-ChildItem "$Root\HAT_SRx4" -Recurse -File

function Normalize-PathPart($p) {
    return ($p -replace '\\','/').TrimStart('/').ToLowerInvariant()
}

function Find-BestOutput($files, $original) {

    $orig = Normalize-PathPart $original
    $origNoExt = [IO.Path]::ChangeExtension($orig, $null)

    $parts = $origNoExt.Split('/')

    # Try longest suffix first.
    for ($n = $parts.Count; $n -ge 2; $n--) {

        $suffix = ($parts[($parts.Count-$n)..($parts.Count-1)] -join '/')

        $matches = @(
            $files | Where-Object {
                $rel = Normalize-PathPart $_.FullName.Substring(
                    $_.PSDrive.Root.Length
                )

                $relNoExt = [IO.Path]::ChangeExtension($rel, $null)

                $relNoExt.EndsWith($suffix)
            }
        )

        if ($matches.Count -eq 1) {
            return $matches[0]
        }
    }

    # Final fallback: unique filename
    $name = [IO.Path]::GetFileName($orig)

    $matches = @(
        $files | Where-Object {
            $_.Name.ToLowerInvariant() -eq $name
        }
    )

    if ($matches.Count -eq 1) {
        return $matches[0]
    }

    return $null
}

function Get-Dimensions($file) {

    $path = $file.FullName

    $result = & py -c @"
from PIL import Image
img=Image.open(r'''$path''')
print(img.width)
print(img.height)
"@

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return @{
        Width  = [int]$result[0]
        Height = [int]$result[1]
    }
}

$results = foreach ($m in $Manifest) {

    $inputW = [int]$m.Width
    $inputH = [int]$m.Height

    $expectedW = $inputW * 4
    $expectedH = $inputH * 4

    $sharp = Find-BestOutput $SharperFiles $m.OriginalRelativePath
    $srx4  = Find-BestOutput $SRx4Files $m.OriginalRelativePath

    $sd = if ($sharp) { Get-Dimensions $sharp }
    $rd = if ($srx4)  { Get-Dimensions $srx4 }

    [PSCustomObject]@{
        RelativePath       = $m.OriginalRelativePath

        SharperFound       = [bool]$sharp
        SharperWidth       = if ($sd) { $sd.Width } else { $null }
        SharperHeight      = if ($sd) { $sd.Height } else { $null }
        SharperCorrect4x   = (
            $sd -and
            $sd.Width -eq $expectedW -and
            $sd.Height -eq $expectedH
        )

        SRx4Found          = [bool]$srx4
        SRx4Width          = if ($rd) { $rd.Width } else { $null }
        SRx4Height         = if ($rd) { $rd.Height } else { $null }
        SRx4Correct4x      = (
            $rd -and
            $rd.Width -eq $expectedW -and
            $rd.Height -eq $expectedH
        )

        SharperOutput      = if ($sharp) { $sharp.FullName } else { '' }
        SRx4Output         = if ($srx4) { $srx4.FullName } else { '' }
    }
}

$results | Export-Csv "$Root\benchmark_output_qa_v3.csv" -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "============================================"
Write-Host "HAT BENCHMARK OUTPUT QA v3"
Write-Host "============================================"
Write-Host ""

Write-Host ("Benchmark entries:       {0}" -f $results.Count)
Write-Host ("Sharper outputs found:  {0}" -f (@($results | Where-Object SharperFound).Count))
Write-Host ("SRx4 outputs found:     {0}" -f (@($results | Where-Object SRx4Found).Count))
Write-Host ("Sharper correct 4x:     {0}" -f (@($results | Where-Object SharperCorrect4x).Count))
Write-Host ("SRx4 correct 4x:        {0}" -f (@($results | Where-Object SRx4Correct4x).Count))

$problems = @(
    $results | Where-Object {
        -not $_.SharperCorrect4x -or -not $_.SRx4Correct4x
    }
)

Write-Host ""

if ($problems.Count -eq 0) {

    Write-Host "ALL 115 HAT OUTPUTS PASSED 4x DIMENSION QA."

} else {

    Write-Host "PROBLEMS FOUND: $($problems.Count)"
    $problems | Format-Table -AutoSize
}

Write-Host ""
Write-Host "QA report:"
Write-Host "$Root\benchmark_output_qa_v3.csv"