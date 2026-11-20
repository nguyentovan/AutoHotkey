
param(
    [Parameter(Mandatory)][ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+$')][string]$Tag,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CheckRelease.ps1')

$git = (Get-Command git.exe -CommandType Application | Select-Object -First 1).Source
$commit = & $git -C $PSScriptRoot rev-parse --verify "refs/tags/$Tag^{commit}"
if ($LASTEXITCODE -ne 0) { throw "Tag $Tag must exist locally." }

$directory = New-Item -ItemType Directory -Path $OutputDirectory -Force
$zipPath = Join-Path $directory.FullName 'AutoHotkey-update.zip'
$manifestPath = Join-Path $directory.FullName 'SHA256SUMS'
if ((Test-Path -LiteralPath $zipPath) -or (Test-Path -LiteralPath $manifestPath)) {
    throw 'Use an output directory without existing release assets.'
}

$files = @(Get-ReleasePackageFiles)
try {
    & $git -C $PSScriptRoot archive --format=zip "--output=$zipPath" $commit -- @files
    if ($LASTEXITCODE -ne 0) { throw "Git could not archive $Tag." }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $lines = foreach ($name in $files) {
            $entry = $zip.GetEntry($name)
            if (!$entry) { throw "Missing release file: $name" }
            $stream = $entry.Open()
            try {
                $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
                "$hash  $name"
            } finally {
                $stream.Dispose()
            }
        }
    } finally {
        $sha.Dispose()
        $zip.Dispose()
    }
    Set-Content -LiteralPath $manifestPath -Value $lines -Encoding ascii
} catch {
    foreach ($path in @($zipPath, $manifestPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    throw
}
Get-Item -LiteralPath $zipPath, $manifestPath
