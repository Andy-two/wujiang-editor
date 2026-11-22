$ErrorActionPreference = 'Stop'
$src = 'F:\dsh-output\wujiang_editor'
$zip = 'F:\Migrated\Desktop\wujiang_editor.zip'

if (Test-Path $zip) { Remove-Item $zip -Force }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fs = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
$count = 0
$skipped = 0
$prefix = 'wujiang_editor/'
try {
    $files = @(Get-ChildItem -Path $src -Recurse -File -Force)
    foreach ($f in $files) {
        $full = $f.FullName
        if (-not $full.StartsWith($src)) { $skipped++; continue }
        $rel = $full.Substring($src.Length).TrimStart('\','/')
        if ($rel -match '(^|[\\/])(\.git|\.godot)([\\/]|$)' -or $rel -match '\.uid$') {
            $skipped++
            continue
        }
        $rel = $rel.Replace([char]92, [char]47)   # '\' -> '/'
        $zipPath = $prefix + $rel
        if ([string]::IsNullOrEmpty($zipPath)) { $skipped++; continue }
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $fs, $full, $zipPath,
            [System.IO.Compression.CompressionLevel]::Optimal)
        $count++
    }
} finally {
    $fs.Dispose()
}

$item = Get-Item $zip
Write-Output ("ZIP created: " + $item.FullName)
Write-Output ("Size MB: " + [math]::Round($item.Length/1MB,1))
Write-Output ("Files: " + $count + " skipped: " + $skipped)
