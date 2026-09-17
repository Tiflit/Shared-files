$outputPath = Join-Path (Get-Location) "combined.txt"

$output = New-Object System.IO.StreamWriter(
    $outputPath,
    $false,
    [System.Text.Encoding]::UTF8
)

Get-ChildItem -Path . -Recurse -Filter *.txt -File |
    Where-Object { $_.FullName -ne $outputPath } |
    Sort-Object FullName |
    ForEach-Object {

        $output.WriteLine()
        $output.WriteLine("============================================================")
        $output.WriteLine($_.FullName)
        $output.WriteLine("============================================================")
        $output.WriteLine()

        foreach ($line in [System.IO.File]::ReadLines($_.FullName)) {
            $output.WriteLine($line)
        }
    }

$output.Close()
$output.Dispose()