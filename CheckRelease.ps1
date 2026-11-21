param([switch]$EnsureRuntime, [switch]$Gui)


function Show-ReleaseMessage($Message, $Buttons = 'OK', $Icon = 'Information') {
    Add-Type -AssemblyName System.Windows.Forms
    $defaultButton = if ($Buttons -eq 'YesNo') { 'Button2' } else { 'Button1' }
    return [Windows.Forms.MessageBox]::Show($Message, 'Cập nhật Zea.AutoHotkey', $Buttons, $Icon, $defaultButton)
}

function Confirm-ReleaseUpdate($Tag, $ConsolePrompt) {
    if ($Gui) {
        return (Show-ReleaseMessage "Đã có phiên bản $Tag. Bạn có muốn cập nhật không?" 'YesNo' 'Question') -eq 'Yes'
    }
    return (Read-Host $ConsolePrompt) -match '^(y|yes)$'
}

function Invoke-ReleaseOperation($Message, [scriptblock]$Action) {
    $status = [hashtable]::Synchronized(@{ Message = $Message; Done = $false })
    if (!$Gui) {
        & $Action $status
        return
    }

    $view = [powershell]::Create()
    $windowRunspace = [runspacefactory]::CreateRunspace()
    try {
        $windowRunspace.ApartmentState = 'STA'
        $windowRunspace.Open()
        $view.Runspace = $windowRunspace
        $null = $view.AddScript({
            param($status)
            $ErrorActionPreference = 'Stop'
            Add-Type -AssemblyName System.Windows.Forms
            [Windows.Forms.Application]::EnableVisualStyles()

            $window = New-Object Windows.Forms.Form
            $timer = New-Object Windows.Forms.Timer
            try {
                $window.Text = 'Cập nhật Zea.AutoHotkey'
                $window.StartPosition = 'CenterScreen'
                $window.FormBorderStyle = 'FixedDialog'
                $window.ControlBox = $false
                $window.AutoScaleMode = 'Dpi'
                $window.ClientSize = New-Object Drawing.Size(400, 86)

                $label = New-Object Windows.Forms.Label
                $label.SetBounds(16, 14, 368, 22)
                $label.Text = $status.Message
                $window.Controls.Add($label)

                $bar = New-Object Windows.Forms.ProgressBar
                $bar.SetBounds(16, 43, 368, 18)
                $bar.Style = 'Marquee'
                $bar.MarqueeAnimationSpeed = 30
                $window.Controls.Add($bar)

                $timer.Interval = 100
                $timer.Add_Tick({
                    if ($status.Done) { $window.Close() }
                    else { $label.Text = $status.Message }
                })
                if (!$status.Done) {
                    $timer.Start()
                    $null = $window.ShowDialog()
                }
            } finally {
                $timer.Dispose()
                $window.Dispose()
            }
        }).AddArgument($status)
        $pending = $view.BeginInvoke()
        try {
            & $Action $status
        } finally {
            $status.Done = $true
            try { $null = $view.EndInvoke($pending) }
            catch { Write-Warning "Update window: $($_.Exception.Message)" }
        }
    } finally {
        $view.Dispose()
        $windowRunspace.Dispose()
    }
}

function Initialize-AutoHotkeyRuntime($Root) {
    $runtime = Join-Path $Root 'runtime'
    $executable = Join-Path $runtime 'AutoHotkey64.exe'
    if (Test-Path -LiteralPath $executable -PathType Leaf) { return }

    $id = [guid]::NewGuid().ToString('N')
    $download = Join-Path ([IO.Path]::GetTempPath()) "AutoHotkey-$id.zip"
    $staged = Join-Path $runtime "AutoHotkey64-$id.tmp"
    $uri = 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.31/AutoHotkey_2.0.31.zip'
    $expectedHash = 'CA1A595ACA4528755D8D4CD7FED23D497A37BD9A0B6892072612D68DEE1BD00A'
    try {
        Write-Host 'Downloading AutoHotkey v2.0.31 portable from the official release...'
        Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $download -TimeoutSec 60 -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256 -ErrorAction Stop).Hash -ne $expectedHash) {
            throw 'AutoHotkey runtime ZIP SHA-256 mismatch.'
        }

        New-Item -ItemType Directory -Path $runtime -Force -ErrorAction Stop | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($download)
        try {
            $entry = $archive.GetEntry('AutoHotkey64.exe')
            if (!$entry) { throw 'The official ZIP is missing AutoHotkey64.exe.' }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $staged)
        } finally {
            $archive.Dispose()
        }

        try {
            [IO.File]::Move($staged, $executable)
        } catch [IO.IOException] {
            # Another launcher may have installed the runtime while this one downloaded it.
            if (!(Test-Path -LiteralPath $executable -PathType Leaf)) { throw }
        }
    } finally {
        foreach ($path in @($staged, $download)) {
            if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
        }
    }
}


function Get-ReleasePackageFiles {
    '.gitignore'
    'CheckRelease.ps1'
    'ExplorerTab.ahk'
    'Main.ahk'
    'README.md'
    'RunMainAhk.cmd'
    'SqlFormat.ahk'
    'SqlLogConvert.ahk'
    'Zea.SqlFormat.exe'
    'Zea.SqlLogConvert.exe'
}

function Get-GitReleaseState($Git, $Root, $ReleaseCommit) {
    & $Git -C $Root merge-base --is-ancestor $ReleaseCommit HEAD
    if ($LASTEXITCODE -eq 0) { return 'Current' }
    if ($LASTEXITCODE -ne 1) { return 'Unavailable' }

    & $Git -C $Root merge-base --is-ancestor HEAD $ReleaseCommit
    if ($LASTEXITCODE -eq 1) { return 'Diverged' }
    if ($LASTEXITCODE -ne 0) { return 'Unavailable' }

    $changes = & $Git -C $Root status --porcelain=v1 --untracked-files=no --ignore-submodules=none
    if ($LASTEXITCODE -ne 0) { return 'Unavailable' }
    if ($changes) { return 'Dirty' }
    return 'Ready'
}

function Merge-GitRelease($Git, $Root, $Branch, $Head, $ReleaseCommit) {
    if ((Get-GitReleaseState $Git $Root $ReleaseCommit) -ne 'Ready') { return $false }
    $currentBranch = & $Git -C $Root symbolic-ref --quiet --short HEAD
    if ($LASTEXITCODE -ne 0 -or $currentBranch -cne $Branch) { return $false }
    $currentHead = & $Git -C $Root rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $currentHead -cne $Head) { return $false }

    & $Git -C $Root -c submodule.recurse=false -c merge.autostash=false merge --ff-only --no-overwrite-ignore -- $ReleaseCommit | Out-Host
    return ($LASTEXITCODE -eq 0)
}

function ConvertFrom-ReleaseManifest([string]$Text) {
    $hashes = @{}
    foreach ($line in ($Text.TrimEnd([char]13, [char]10) -split '\r?\n')) {
        if ($line -notmatch '^([a-fA-F0-9]{64})  ([a-zA-Z0-9_.-]+)$') {
            throw 'Invalid SHA256SUMS entry.'
        }
        $hash, $name = $Matches[1], $Matches[2]
        if ($name -in @('.', '..', '.git') -or $hashes.ContainsKey($name)) {
            throw "Invalid or duplicate release file: $name"
        }
        $hashes[$name] = $hash
    }
    return $hashes
}

function Get-LocalReleaseHashes($Root, $Files) {
    $hashes = @{}
    foreach ($name in $Files) {
        $path = Join-Path $Root $name
        $file = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if (!$file) {
            $hashes[$name] = $null
            continue
        }
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Expected a regular release file: $name"
        }
        $hashes[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
    }
    return $hashes
}

function Test-ReleaseHashes($Expected, $Actual) {
    foreach ($name in $Expected.Keys) {
        if ($Expected[$name] -ne $Actual[$name]) { return $false }
    }
    return $true
}

function Get-PackageHashes($Manifest) {
    $hashes = ConvertFrom-ReleaseManifest $Manifest
    $files = @(Get-ReleasePackageFiles)
    if ($hashes.Count -ne $files.Count -or @($files | Where-Object { !$hashes.ContainsKey($_) }).Count) {
        throw 'SHA256SUMS does not match the release file list.'
    }
    return $hashes
}

function Repair-ReleaseTransaction($Root, $Transaction) {
    $item = Get-Item -LiteralPath $Transaction -Force
    if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unexpected update directory: $Transaction"
    }
    $owner = Join-Path $Transaction 'owner'
    if (!(Get-ChildItem -LiteralPath $Transaction -Force | Select-Object -First 1)) {
        [IO.Directory]::Delete($Transaction)
        return
    }
    if (!(Test-Path -LiteralPath $owner -PathType Leaf) -or
        ((Get-Item -LiteralPath $owner -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        [IO.File]::ReadAllText($owner) -cne 'AutoHotkey release update') {
        throw "Unexpected update directory: $Transaction"
    }
    $files = @(Get-ReleasePackageFiles)
    $allowed = @('owner', 'pending', 'pending.tmp', 'complete')
    foreach ($name in $files) { $allowed += @($name, "$name.old", "$name.absent", "$name.discard") }
    foreach ($child in (Get-ChildItem -LiteralPath $Transaction -Force)) {
        if ($child.PSIsContainer -or ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $child.Name -notin $allowed) {
            throw "Unexpected item in update directory: $($child.FullName)"
        }
    }
    $pending = Join-Path $Transaction 'pending'
    $complete = Join-Path $Transaction 'complete'
    if ((Test-Path -LiteralPath $pending -PathType Leaf) -and !(Test-Path -LiteralPath $complete -PathType Leaf)) {
        $hashes = ConvertFrom-ReleaseManifest (Get-Content -LiteralPath $pending -Raw -ErrorAction Stop)
        foreach ($name in $files) {
            $oldFile = Join-Path $Transaction "$name.old"
            $newMarker = Join-Path $Transaction "$name.absent"
            if (!(Test-Path -LiteralPath $oldFile) -and !(Test-Path -LiteralPath $newMarker)) { continue }

            $destination = Join-Path $Root $name
            $existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
            if ($existing -and ($existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $hashes[$name])) {
                throw "Cannot restore $name because it changed during the update. Backups: $Transaction"
            }
            if (Test-Path -LiteralPath $oldFile) {
                if ($existing) {
                    [IO.File]::Replace($oldFile, $destination, (Join-Path $Transaction "$name.discard"))
                } else {
                    [IO.File]::Move($oldFile, $destination)
                }
            } elseif ($existing) {
                Remove-Item -LiteralPath $destination -Force -ErrorAction Stop
            }
        }
    }

    # Keep a completed update committed even if cleanup is interrupted.
    if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force -ErrorAction Stop }
    foreach ($child in (Get-ChildItem -LiteralPath $Transaction -Force)) {
        if ($child.Name -ne 'owner') { Remove-Item -LiteralPath $child.FullName -Force -ErrorAction Stop }
    }
    Remove-Item -LiteralPath $owner -Force -ErrorAction Stop
    Remove-Item -LiteralPath $Transaction -Force -ErrorAction Stop
}

function Install-ReleaseZip($Root, $ArchivePath, $Manifest, $ExpectedLocal) {
    $hashes = Get-PackageHashes $Manifest
    $files = @(Get-ReleasePackageFiles)
    $transaction = Join-Path $Root '.ahk-release-update'
    New-Item -ItemType Directory -Path $transaction -ErrorAction Stop | Out-Null
    [IO.File]::WriteAllText((Join-Path $transaction 'owner'), 'AutoHotkey release update')
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
        try {
            if ($archive.Entries.Count -ne $files.Count) { throw 'Unexpected ZIP file list.' }
            foreach ($name in $files) {
                $entry = $archive.GetEntry($name)
                if (!$entry) { throw "Missing ZIP file: $name" }
                $stagedFile = Join-Path $transaction $name
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $stagedFile)
                if ((Get-FileHash -LiteralPath $stagedFile -Algorithm SHA256).Hash -ne $hashes[$name]) {
                    throw "SHA-256 mismatch for $name."
                }
            }
        } finally {
            $archive.Dispose()
        }

        if (!(Test-ReleaseHashes $ExpectedLocal (Get-LocalReleaseHashes $Root $files))) {
            throw 'Local files changed after the update check.'
        }
        $journalDraft = Join-Path $transaction 'pending.tmp'
        [IO.File]::WriteAllText($journalDraft, $Manifest)
        [IO.File]::Move($journalDraft, (Join-Path $transaction 'pending'))
        foreach ($name in $files) {
            $stagedFile = Join-Path $transaction $name
            $destination = Join-Path $Root $name
            if (Test-Path -LiteralPath $destination -PathType Leaf) {
                [IO.File]::Replace($stagedFile, $destination, (Join-Path $transaction "$name.old"))
            } else {
                [IO.File]::WriteAllText((Join-Path $transaction "$name.absent"), '')
                [IO.File]::Move($stagedFile, $destination)
            }
        }
        [IO.File]::WriteAllText((Join-Path $transaction 'complete'), '')
    } finally {
        Repair-ReleaseTransaction $Root $transaction
    }
}

function Update-GitCheckout($Root, $Git, $Tag) {
    $gitRoot = & $Git -C $Root rev-parse --show-toplevel
    if ($LASTEXITCODE -ne 0 -or (Resolve-Path -LiteralPath $gitRoot).Path -ne $Root) { return }
    $branch = & $Git -C $Root symbolic-ref --quiet --short HEAD
    if ($LASTEXITCODE -ne 0) { return }
    $head = & $Git -C $Root rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { return }

    $tagRef = "refs/tags/$Tag"
    $env:GIT_TERMINAL_PROMPT = '0'
    & $Git -C $Root -c credential.helper= -c http.lowSpeedLimit=1 -c http.lowSpeedTime=5 fetch --quiet --no-tags --no-write-fetch-head -- 'https://github.com/nguyentovan/AutoHotkey.git' "$($tagRef):$tagRef"
    if ($LASTEXITCODE -ne 0) { return }
    $target = & $Git -C $Root rev-parse --verify "$tagRef^{commit}"
    if ($LASTEXITCODE -ne 0) { return }

    switch (Get-GitReleaseState $Git $Root $target) {
        'Dirty' {
            if ($Gui) {
                $null = Show-ReleaseMessage "Đã có phiên bản $Tag. Hãy commit hoặc stash các thay đổi cục bộ trước khi cập nhật." 'OK' 'Warning'
            } else {
                Write-Host "Release $Tag is available. Commit or stash your tracked changes before updating."
            }
        }
        'Diverged' {
            if ($Gui) {
                $null = Show-ReleaseMessage "Đã có phiên bản $Tag. Nhánh hiện tại đã phân kỳ và cần cập nhật thủ công bằng Git." 'OK' 'Warning'
            } else {
                Write-Host "Release $Tag and the current branch have diverged. Update the branch manually."
            }
        }
        'Ready' {
            if (!(Confirm-ReleaseUpdate $Tag "Update this checkout to release $Tag [y/N]")) { return }
            Invoke-ReleaseOperation "Đang cập nhật lên $Tag…" {
                if (!(Merge-GitRelease $Git $Root $branch $head $target)) {
                    throw 'Git could not apply the release as a clean fast-forward.'
                }
                Write-Host "Updated to $Tag."
            }
        }
    }
}

function Update-ZipInstall($Root, $Release) {
    if ('SHA256SUMS' -notin $Release.assets.name -or 'AutoHotkey-update.zip' -notin $Release.assets.name) { return }
    $downloadBase = "https://github.com/nguyentovan/AutoHotkey/releases/download/$($Release.tag_name)"
    $manifest = (Invoke-WebRequest -UseBasicParsing -Uri "$downloadBase/SHA256SUMS" -TimeoutSec 5 -ErrorAction Stop).Content
    if ($manifest -is [byte[]]) { $manifest = [Text.Encoding]::UTF8.GetString($manifest) }
    $expected = Get-PackageHashes $manifest
    $local = Get-LocalReleaseHashes $Root $expected.Keys
    if (Test-ReleaseHashes $expected $local) { return }
    if (!(Confirm-ReleaseUpdate $Release.tag_name "Release $($Release.tag_name) differs from these files. Download and replace them [y/N]")) { return }

    Invoke-ReleaseOperation "Đang tải phiên bản $($Release.tag_name)…" {
        param($status)
        $download = Join-Path ([IO.Path]::GetTempPath()) ('ahk-release-' + [guid]::NewGuid() + '.zip')
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "$downloadBase/AutoHotkey-update.zip" -OutFile $download -TimeoutSec 120 -ErrorAction Stop
            $status.Message = 'Đang xác minh và cài đặt bản cập nhật…'
            Install-ReleaseZip $Root $download $manifest $local
            Write-Host "Updated to $($Release.tag_name)."
        } finally {
            if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force }
        }
    }
}

function Invoke-ReleaseCheck($Root) {
    # Serialize launcher updates for the same installation.
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $pathHash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Root.ToUpperInvariant())))
    } finally {
        $sha.Dispose()
    }
    $mutex = [Threading.Mutex]::new($false, "Local\AutoHotkey.Release.$pathHash")
    try {
        try { $null = $mutex.WaitOne() } catch [Threading.AbandonedMutexException] {}
        $transaction = Join-Path $Root '.ahk-release-update'
        try {
            if (Test-Path -LiteralPath $transaction) { Repair-ReleaseTransaction $Root $transaction }
            try {
                $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/nguyentovan/AutoHotkey/releases/latest' -Headers @{ Accept = 'application/vnd.github+json' } -TimeoutSec 5 -ErrorAction Stop
            } catch {
                return 0
            }
            if ($release.tag_name -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') { return 0 }

            if (Test-Path -LiteralPath (Join-Path $Root '.git')) {
                $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($git) { Update-GitCheckout $Root $git.Source $release.tag_name }
            } else {
                Update-ZipInstall $Root $release
            }
            return 0
        } catch {
            Write-Warning "Release update: $($_.Exception.Message)"
            $requiresRecovery = Test-Path -LiteralPath $transaction
            if ($Gui) {
                $message = if ($requiresRecovery) {
                    'Không thể khôi phục bản cài đặt. AutoHotkey sẽ chưa được mở.'
                } else {
                    'Không thể hoàn tất cập nhật. AutoHotkey sẽ mở phiên bản hiện tại.'
                }
                $null = Show-ReleaseMessage "$message $($_.Exception.Message)" 'OK' 'Warning'
            }
            if ($requiresRecovery) { return 2 }
            return 0
        } finally {
            $mutex.ReleaseMutex()
        }
    } finally {
        $mutex.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    if ($EnsureRuntime) {
        try {
            if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'runtime\AutoHotkey64.exe') -PathType Leaf)) {
                Invoke-ReleaseOperation 'Đang tải AutoHotkey portable…' {
                    Initialize-AutoHotkeyRuntime $PSScriptRoot
                }
            }
            exit 0
        } catch {
            Write-Warning "AutoHotkey runtime: $($_.Exception.Message)"
            if ($Gui) {
                $null = Show-ReleaseMessage "Không thể cài AutoHotkey portable. $($_.Exception.Message)" 'OK' 'Error'
            }
            exit 1
        }
    }
    exit (Invoke-ReleaseCheck $PSScriptRoot)
}
