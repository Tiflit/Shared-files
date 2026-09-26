$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
$GameRoot=Join-Path $Root 'Age of Mythology'
$Extractor=Join-Path $Root 'tools\TextureExtractor.exe'
$OutputRoot=Join-Path $Root 'extracted'
$Report=Join-Path $Root 'reports\ddt_extraction_report.csv'
if(-not(Test-Path $GameRoot -PathType Container)){throw 'Clean game directory not found under project root.'}
if(-not(Test-Path $Extractor -PathType Leaf)){throw 'TextureExtractor.exe not found under tools/.'}
New-Item -ItemType Directory -Force -Path $OutputRoot,(Split-Path $Report) | Out-Null
$rows=New-Object System.Collections.Generic.List[object]
foreach($f in @(Get-ChildItem $GameRoot -File -Recurse|Where-Object {$_.Extension -ieq '.ddt'}|Sort-Object FullName)){
 $rel=$f.FullName.Substring($GameRoot.Length).TrimStart('\\');$dir=Split-Path $rel -Parent;$dest=if($dir){Join-Path $OutputRoot $dir}else{$OutputRoot};New-Item -ItemType Directory -Force -Path $dest|Out-Null
 $base=[IO.Path]::GetFileNameWithoutExtension($f.Name);$tga=Join-Path $dest ($base+'.tga');$bti=Join-Path $dest ($base+'.bti');& $Extractor -i $f.FullName -o $tga|Out-Null;$code=$LASTEXITCODE
 $rows.Add([pscustomobject]@{RelativePath=$rel;ExitCode=$code})
}
$rows|Export-Csv $Report -NoTypeInformation -Encoding UTF8
if(@($rows|Where-Object {$_.ExitCode -ne 0}).Count){exit 1}
