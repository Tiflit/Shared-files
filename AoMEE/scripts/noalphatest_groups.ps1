$Project = "D:\AI_upscaling\AoMEE"

$Analysis = "$Project\reports\noalphatest_alpha_analysis.csv"

$OutTxt = "$Project\reports\noalphatest_groups.txt"

if (-not (Test-Path $Analysis)) {
    Write-Host "ERROR: File not found:"
    Write-Host $Analysis
    exit
}

$rows = Import-Csv -LiteralPath $Analysis

$out = @()

$out += "AoM:EE noalphatest Texture Groups"
$out += "================================="
$out += ""

$groups = @(
    "Binary_0-10%",
    "Binary_10-25%",
    "Binary_25-50%",
    "Binary_50-75%",
    "Binary_75-100%",
    "MultiValue"
)

foreach ($group in $groups) {

    $out += ""
    $out += "================================="
    $out += $group
    $out += "================================="
    $out += ""

    switch ($group) {

        "Binary_0-10%" {
            $subset = $rows | Where-Object {
                $_.AlphaType -eq "Binary" -and
                [double]$_.OpaqueCoveragePct -le 10
            }
        }

        "Binary_10-25%" {
            $subset = $rows | Where-Object {
                $_.AlphaType -eq "Binary" -and
                [double]$_.OpaqueCoveragePct -gt 10 -and
                [double]$_.OpaqueCoveragePct -le 25
            }
        }

        "Binary_25-50%" {
            $subset = $rows | Where-Object {
                $_.AlphaType -eq "Binary" -and
                [double]$_.OpaqueCoveragePct -gt 25 -and
                [double]$_.OpaqueCoveragePct -le 50
            }
        }

        "Binary_50-75%" {
            $subset = $rows | Where-Object {
                $_.AlphaType -eq "Binary" -and
                [double]$_.OpaqueCoveragePct -gt 50 -and
                [double]$_.OpaqueCoveragePct -le 75
            }
        }

        "Binary_75-100%" {
            $subset = $rows | Where-Object {
                $_.AlphaType -eq "Binary" -and
                [double]$_.OpaqueCoveragePct -gt 75
            }
        }

        "MultiValue" {
            $subset = $rows | Where-Object {
                $_.AlphaType -eq "MultiValue"
            }
        }
    }

    $subset |
        Sort-Object Category, Filename |
        ForEach-Object {
            $out += ("{0,-20} {1,6}x{2,-6} {3,7}%  {4}" -f `
                $_.Category,
                $_.Width,
                $_.Height,
                $_.OpaqueCoveragePct,
                $_.Filename)
        }

    $out += ""
    $out += "COUNT: $($subset.Count)"
}

$out | Set-Content -LiteralPath $OutTxt -Encoding UTF8

Write-Host ""
Write-Host "DONE"
Write-Host ""
Write-Host $OutTxt