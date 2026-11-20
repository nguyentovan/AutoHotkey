
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'CheckRelease.ps1')

function Assert-Equal($Expected, $Actual, $Case) {
    if ($Expected -cne $Actual) { throw "$Case expected '$Expected', got '$Actual'." }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('AHK releases ' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $root | Out-Null
try {
    $git = (Get-Command git.exe -CommandType Application | Select-Object -First 1).Source
    function FixtureGit {
        $output = & $git -C $root @args
        if ($LASTEXITCODE -ne 0) { throw "Fixture Git failed: $args" }
        $output
    }

    FixtureGit init --quiet
    FixtureGit config user.name 'Release Test'
    FixtureGit config user.email 'test@example.invalid'
    FixtureGit config commit.gpgsign false
    $scriptPath = Join-Path $root 'Main.ahk'
    Set-Content -LiteralPath $scriptPath -Value 'original'
    FixtureGit add -- Main.ahk
    FixtureGit commit --quiet -m 'Initial script'
    $base = FixtureGit rev-parse HEAD
    Set-Content -LiteralPath $scriptPath -Value 'release'
    FixtureGit commit --quiet -am 'Release script'
    $release = FixtureGit rev-parse HEAD
    FixtureGit switch --quiet -c installed $base
    Assert-Equal 'Ready' (Get-GitReleaseState $git $root $release) 'Clean ancestor'
    Assert-Equal 'Current' (Get-GitReleaseState $git $root $base) 'Current release'
    Set-Content -LiteralPath $scriptPath -Value 'local edit'
    Assert-Equal 'Dirty' (Get-GitReleaseState $git $root $release) 'Modified source'
    Assert-Equal $false (Merge-GitRelease $git $root 'installed' $base $release) 'Dirty merge refused'
    Assert-Equal 'local edit' (Get-Content -LiteralPath $scriptPath) 'Local change preserved'
    FixtureGit restore -- Main.ahk
    Assert-Equal $false (Merge-GitRelease $git $root 'other-branch' $base $release) 'Changed branch refused'
    Assert-Equal $true (Merge-GitRelease $git $root 'installed' $base $release) 'Fast-forward applied'
    Assert-Equal $release (FixtureGit rev-parse HEAD) 'Exact release commit'
    Assert-Equal 'Current' (Get-GitReleaseState $git $root $base) 'Ahead of release'

    FixtureGit switch --quiet -c divergent $base
    Set-Content -LiteralPath $scriptPath -Value 'divergent'
    FixtureGit commit --quiet -am 'Divergent local commit'
    Assert-Equal 'Diverged' (Get-GitReleaseState $git $root $release) 'Divergent branch'
    Assert-Equal $false (Merge-GitRelease $git $root 'divergent' (FixtureGit rev-parse HEAD) $release) 'Divergent merge refused'

    $hash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
    $manifest = "$hash  Main.ahk"
    Assert-Equal $true (Test-ReleaseHashes (ConvertFrom-ReleaseManifest $manifest) (Get-LocalReleaseHashes $root @('Main.ahk'))) 'Matching ZIP files'
    Assert-Equal $true (Test-ReleaseHashes (ConvertFrom-ReleaseManifest ($manifest + [Environment]::NewLine)) (Get-LocalReleaseHashes $root @('Main.ahk'))) 'Manifest with final newline'
    Set-Content -LiteralPath $scriptPath -Value 'edited after extracting'
    Assert-Equal $false (Test-ReleaseHashes (ConvertFrom-ReleaseManifest $manifest) (Get-LocalReleaseHashes $root @('Main.ahk'))) 'Changed ZIP files'
    Remove-Item -LiteralPath $scriptPath
    Assert-Equal $false (Test-ReleaseHashes (ConvertFrom-ReleaseManifest $manifest) (Get-LocalReleaseHashes $root @('Main.ahk'))) 'Missing ZIP file'
    try {
        ConvertFrom-ReleaseManifest "$hash  ../Main.ahk"
        throw 'UnexpectedManifestAcceptance'
    } catch {
        if ($_.Exception.Message -eq 'UnexpectedManifestAcceptance') { throw }
    }

    FixtureGit restore -- Main.ahk
    FixtureGit switch --quiet installed
    FixtureGit branch pre-release $release
    $packageFiles = @(Get-ReleasePackageFiles)
    foreach ($name in $packageFiles) {
        Set-Content -LiteralPath (Join-Path $root $name) -Value "release $name" -Encoding ascii
    }
    FixtureGit -c core.autocrlf=false add -- @packageFiles
    FixtureGit commit --quiet -m 'Package contents'
    FixtureGit tag -a v1.2.3 -m 'Test release'
    $sourceRoot = Split-Path $PSScriptRoot -Parent
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'CheckRelease.ps1'), (Join-Path $sourceRoot 'NewReleaseAssets.ps1') -Destination $root
    $output = Join-Path $root 'release assets'
    & (Join-Path $root 'NewReleaseAssets.ps1') -Tag v1.2.3 -OutputDirectory $output | Out-Null
    $archive = Join-Path $output 'AutoHotkey-update.zip'
    $manifest = Get-Content -LiteralPath (Join-Path $output 'SHA256SUMS') -Raw
    $expected = Get-PackageHashes $manifest

    $zipRoot = Join-Path $root 'installed from ZIP'
    $runtimePath = Join-Path $zipRoot 'runtime\AutoHotkey64.exe'
    New-Item -ItemType Directory -Path (Split-Path $runtimePath) | Out-Null
    Set-Content -LiteralPath $runtimePath -Value 'portable runtime'
    Set-Content -LiteralPath (Join-Path $zipRoot 'notes.txt') -Value 'user file'
    $readme = Join-Path $zipRoot 'README.md'
    $main = Join-Path $zipRoot 'Main.ahk'
    $lockedFile = Join-Path $zipRoot 'Zea.SqlFormat.exe'
    Set-Content -LiteralPath $main -Value 'existing script'
    Set-Content -LiteralPath $lockedFile -Value 'existing SQL binary'

    $local = Get-LocalReleaseHashes $zipRoot $packageFiles
    Set-Content -LiteralPath $main -Value 'edit after prompt'
    try {
        Install-ReleaseZip $zipRoot $archive $manifest $local
        throw 'UnexpectedInstallSuccess'
    } catch {
        if ($_.Exception.Message -notlike '*Local files changed*') { throw }
    }
    Assert-Equal 'edit after prompt' (Get-Content -LiteralPath $main) 'Concurrent user edit preserved'

    $local = Get-LocalReleaseHashes $zipRoot $packageFiles
    $lock = [IO.File]::Open($lockedFile, 'Open', 'Read', 'Read')
    try {
        try {
            Install-ReleaseZip $zipRoot $archive $manifest $local
            throw 'UnexpectedInstallSuccess'
        } catch {
            if ($_.Exception.Message -eq 'UnexpectedInstallSuccess' -or
                (Test-Path -LiteralPath (Join-Path $zipRoot '.ahk-release-update'))) { throw }
        }
    } finally {
        $lock.Dispose()
    }
    Assert-Equal 'edit after prompt' (Get-Content -LiteralPath $main) 'Rolled back replaced script'
    Assert-Equal $false (Test-Path -LiteralPath $readme) 'Rolled back newly installed file'
    Assert-Equal 'existing SQL binary' (Get-Content -LiteralPath $lockedFile) 'Locked binary preserved'

    $wrongHash = '0' * 64
    $badManifest = $manifest.Replace($expected['Zea.SqlFormat.exe'].ToLowerInvariant() + '  Zea.SqlFormat.exe', "$wrongHash  Zea.SqlFormat.exe")
    try {
        Install-ReleaseZip $zipRoot $archive $badManifest $local
        throw 'UnexpectedInstallSuccess'
    } catch {
        if ($_.Exception.Message -notlike '*SHA-256 mismatch*') { throw }
    }
    Assert-Equal 'edit after prompt' (Get-Content -LiteralPath $main) 'Invalid archive changed no local scripts'

    Install-ReleaseZip $zipRoot $archive $manifest $local
    Assert-Equal $true (Test-ReleaseHashes $expected (Get-LocalReleaseHashes $zipRoot $packageFiles)) 'Release hashes after applying ZIP'
    Assert-Equal 'release Main.ahk' (Get-Content -LiteralPath $main) 'Release taken from tag, not working copy'
    Assert-Equal 'portable runtime' (Get-Content -LiteralPath $runtimePath) 'Portable runtime untouched'
    Assert-Equal 'user file' (Get-Content -LiteralPath (Join-Path $zipRoot 'notes.txt')) 'Unmanaged file untouched'
    Assert-Equal $false (Test-Path -LiteralPath (Join-Path $zipRoot '.ahk-release-update')) 'Transaction cleaned'

    $script:updateArchive = $archive
    $script:updateManifest = $manifest
    $script:updateAnswer = 'n'
    $script:archiveRequests = 0
    function Invoke-RestMethod {
        [pscustomobject]@{
            tag_name = 'v1.2.3'
            assets = @([pscustomobject]@{ name = 'SHA256SUMS' }, [pscustomobject]@{ name = 'AutoHotkey-update.zip' })
        }
    }
    function Invoke-WebRequest {
        param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile, [int]$TimeoutSec, $ErrorAction)
        if ($Uri -eq 'https://github.com/nguyentovan/AutoHotkey/releases/download/v1.2.3/SHA256SUMS') {
            return [pscustomobject]@{ Content = [Text.Encoding]::ASCII.GetBytes($script:updateManifest) }
        }
        if ($Uri -ne 'https://github.com/nguyentovan/AutoHotkey/releases/download/v1.2.3/AutoHotkey-update.zip') {
            throw "Unexpected update download URL: $Uri"
        }
        $script:archiveRequests++
        Copy-Item -LiteralPath $script:updateArchive -Destination $OutFile
    }
    function Read-Host { $script:updateAnswer }

    Set-Content -LiteralPath $main -Value 'changed from last release'
    Assert-Equal 0 (Invoke-ReleaseCheck $zipRoot) 'Declined ZIP check exit'
    Assert-Equal 0 $script:archiveRequests 'ZIP downloaded only after consent'
    Assert-Equal 'changed from last release' (Get-Content -LiteralPath $main) 'Decline preserved edits'
    $script:updateAnswer = 'yes'
    Assert-Equal 0 (Invoke-ReleaseCheck $zipRoot) 'Accepted ZIP check exit'
    Assert-Equal 1 $script:archiveRequests 'Accepted ZIP downloaded once'
    Assert-Equal 'release Main.ahk' (Get-Content -LiteralPath $main) 'Accepted download installed'
    Assert-Equal 0 (Invoke-ReleaseCheck $zipRoot) 'Matching release check exit'
    Assert-Equal 1 $script:archiveRequests 'Current ZIP skipped download'

    $clone = Join-Path $root 'clone from Git'
    & $git clone --quiet --no-local --no-tags --single-branch --branch pre-release -- $root $clone
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the release checkout fixture.' }
    & $git -C $clone config "url.$root.insteadOf" 'https://github.com/nguyentovan/AutoHotkey.git'
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure the fixture release remote.' }
    $script:updateAnswer = 'n'
    Assert-Equal 0 (Invoke-ReleaseCheck $clone) 'Declined Git check exit'
    Assert-Equal $release (& $git -C $clone rev-parse HEAD) 'Declined Git update left HEAD alone'
    $script:updateAnswer = 'y'
    Assert-Equal 0 (Invoke-ReleaseCheck $clone) 'Accepted Git check exit'
    Assert-Equal (FixtureGit rev-parse 'refs/tags/v1.2.3^{commit}') (& $git -C $clone rev-parse HEAD) 'Fetched release tag and fast-forwarded'
    Assert-Equal 1 $script:archiveRequests 'Git update did not download ZIP asset'

    $transaction = Join-Path $zipRoot '.ahk-release-update'
    New-Item -ItemType Directory -Path $transaction | Out-Null
    Repair-ReleaseTransaction $zipRoot $transaction
    Assert-Equal $false (Test-Path -LiteralPath $transaction) 'Recovered empty interrupted transaction'
    Write-Output 'PASS: Git fast-forward, tagged ZIP packaging, download consent, SHA-256 validation and rollback.'
} finally {
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolved = (Resolve-Path -LiteralPath $root).Path
    if (!$resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notlike 'AHK releases *') { throw 'Unexpected fixture path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
