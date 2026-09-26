param([string]$Version = '0.1.0')
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+([.-][a-zA-Z0-9]+)*$') { throw 'Invalid package version' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot 'addons/game_extrakit'
$destination = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$zipPath = Join-Path $destination "game-extrakit-$Version.zip"
$stream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create)
$archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
$stamp = [DateTimeOffset]::new(2026, 9, 26, 0, 0, 0, [TimeSpan]::Zero)
try {
    foreach ($file in (Get-ChildItem -LiteralPath $source -File -Recurse | Sort-Object FullName)) {
        $entryName = $file.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
        $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $stamp
        $entryStream = $entry.Open()
        try {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $entryStream.Write($bytes, 0, $bytes.Length)
        } finally { $entryStream.Dispose() }
    }
} finally { $archive.Dispose(); $stream.Dispose() }
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText("$zipPath.sha256", "$hash  $([System.IO.Path]::GetFileName($zipPath))`n")
Write-Output $zipPath
Write-Output "SHA256 $hash"
