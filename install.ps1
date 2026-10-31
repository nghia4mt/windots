#Requires -Version 5.1

<#
.SYNOPSIS
    One-shot bootstrap for a fresh Windows install.

.DESCRIPTION
    Idempotent: it can be run again at any time without breaking anything.

    Steps
      1. Install Scoop (per-user, no admin rights needed).
      2. Add the buckets required by the app list.
      3. Install the apps listed in $Apps (Sublime Text 4, Node.js, VS Code,
         Python, ...) and OpenCode V2 (desktop app + `opencode` CLI shim).
      4. Restore the PowerShell profiles/config stored in .\config.

    Run it from a NORMAL (non elevated) PowerShell window:
        powershell -ExecutionPolicy Bypass -File .\install.ps1

.PARAMETER SkipScoop
    Do not install/verify Scoop.

.PARAMETER SkipApps
    Do not install the apps from $Apps, nor OpenCode V2.

.PARAMETER SkipConfig
    Do not restore the PowerShell configuration from .\config.

.PARAMETER SymlinkConfig
    Create symbolic links instead of copying the profiles. Requires Developer
    Mode or an elevated shell; falls back to copying if linking fails.

.PARAMETER Apps
    Replace the default app list, e.g. -Apps main/git,extras/firefox
    (format: '<bucket>/<app>').

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -SkipApps -SkipScoop
    # only restore the PowerShell configuration
#>

[CmdletBinding()]
param(
    [switch] $SkipScoop,
    [switch] $SkipApps,
    [switch] $SkipConfig,
    [switch] $SymlinkConfig,
    [string[]] $Apps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------- settings

$ScriptRoot  = $PSScriptRoot
$ConfigRoot  = Join-Path $ScriptRoot 'config'
$ScoopRoot   = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }
$ScoopShims  = Join-Path $ScoopRoot 'shims'
$ScoopScript = Join-Path $ScoopShims 'scoop.ps1'

# OpenCode V2 desktop (per-user install) and the CLI it bundles.
$OpenCodeDir = Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop'
$OpenCodeCli = Join-Path $OpenCodeDir 'resources\opencode-cli.exe'
$OpenCodeUrl = 'https://opencode.ai/update/api/latest/desktop/opencode/opencode-desktop-win-{0}.exe'

# Buckets that must exist before installing $Apps.
$Buckets = @('extras', 'nerd-fonts')

# Format: '<bucket>/<app>'. Comment an entry out if you do not want it.
$DefaultApps = @(
    # base tooling used by Scoop itself and by this script
    'main/git'
    'main/7zip'
    'main/aria2'
    'main/dark'
    'main/lessmsi'
    'main/innounp'

    # requested apps
    'extras/sublime-text'       # Sublime Text 4
    'main/nodejs-lts'           # Node.js LTS (npm included)
    'extras/vscode'             # Visual Studio Code
    'extras/googlechrome'       # Google Chrome (stable)
    'main/python'               # Python
    # OpenCode V2 is installed from opencode.ai (Install-OpenCode below):
    # the Scoop `opencode-desktop` manifest is still V1 and Windows package
    # managers are not supported by OpenCode V2.

    # quality of life
    'main/scoop-search'         # fast `scoop search`
    'extras/scoop-completion'   # tab completion for scoop
    'nerd-fonts/JetBrainsMono-NF'
)

# -Apps on the command line replaces the default list. Accepts both
# -Apps main/git,extras/firefox and the single-string form used by -File.
if (-not $Apps -or $Apps.Count -eq 0) {
    $Apps = $DefaultApps
}
else {
    $Apps = $Apps | ForEach-Object { $_ -split ',' } | Where-Object { $_ }
}

# ---------------------------------------------------------------- helpers

function Write-Step {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "    $Message" -ForegroundColor Gray
}

function Write-Ok {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "    [ok]   $Message" -ForegroundColor Green
}

function Write-Warn {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "    [warn] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "    [fail] $Message" -ForegroundColor Red
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-PathExists {
    param([Parameter(Mandatory)][string] $Path)
    return [bool](Test-Path -LiteralPath $Path)
}

function Test-FileEqual {
    param(
        [Parameter(Mandatory)][string] $First,
        [Parameter(Mandatory)][string] $Second
    )
    $a = Get-FileHash -LiteralPath $First -Algorithm SHA256
    $b = Get-FileHash -LiteralPath $Second -Algorithm SHA256
    return ($a.Hash -eq $b.Hash)
}

function Add-UserPath {
    param([Parameter(Mandatory)][string] $Path)

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if ($userPath) { $entries = $userPath -split ';' | Where-Object { $_ } }

    if ($entries -contains $Path) {
        Write-Ok "$Path already in user PATH"
        return
    }

    $newPath = (@($entries) + $Path) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    if (($env:PATH -split ';') -notcontains $Path) { $env:PATH = "$Path;$env:PATH" }
    Write-Ok "added $Path to user PATH"
}

# ---------------------------------------------------------------- scoop

function Test-ScoopInstalled {
    return (Test-PathExists $ScoopScript)
}

function Install-Scoop {
    if (Test-ScoopInstalled) {
        Write-Ok "Scoop already installed ($ScoopRoot)"
        return
    }

    if (Test-IsAdministrator) {
        throw 'Scoop must be installed from a NORMAL PowerShell window (not elevated). Open a new terminal without "Run as administrator" and try again.'
    }

    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        Write-Ok 'execution policy: RemoteSigned (CurrentUser)'
    }
    catch {
        Write-Warn "could not set execution policy: $($_.Exception.Message)"
    }

    Write-Info 'downloading and running https://get.scoop.sh ...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $installer = Invoke-RestMethod -Uri 'https://get.scoop.sh' -UseBasicParsing
    Invoke-Expression $installer

    if (-not (Test-ScoopInstalled)) {
        throw "Scoop installation failed: '$ScoopScript' was not created."
    }
    Write-Ok "Scoop installed ($ScoopRoot)"
}

function Add-ScoopBucket {
    param([Parameter(Mandatory)][string] $Bucket)

    $bucketDir = Join-Path $ScoopRoot "buckets\$Bucket"
    if (Test-PathExists $bucketDir) {
        Write-Ok "bucket '$Bucket' already present"
        return
    }

    Write-Info "adding bucket '$Bucket' ..."
    & $ScoopScript bucket add $Bucket
    if (-not (Test-PathExists $bucketDir)) {
        throw "could not add bucket '$Bucket'."
    }
    Write-Ok "bucket '$Bucket' added"
}

function Test-ScoopAppInstalled {
    param([Parameter(Mandatory)][string] $App)

    $name = ($App -split '/')[-1]
    return (Test-PathExists (Join-Path $ScoopRoot "apps\$name\current"))
}

function Install-ScoopApp {
    param([Parameter(Mandatory)][string] $App)

    $name = ($App -split '/')[-1]

    if (Test-ScoopAppInstalled $App) {
        Write-Ok "$name already installed"
        return
    }

    Write-Info "installing $App ..."
    & $ScoopScript install $App

    if (-not (Test-ScoopAppInstalled $App)) {
        Write-Fail "$name did not install correctly"
        return
    }
    Write-Ok "$name installed"
}

function Test-SystemChrome {
    # Chrome installed by Google's own installer (Program Files / LocalAppData)
    $candidates = @()
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe') }
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if ($programFilesX86) { $candidates += (Join-Path $programFilesX86 'Google\Chrome\Application\chrome.exe') }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe') }

    foreach ($candidate in $candidates) {
        if (Test-PathExists $candidate) { return $true }
    }
    return $false
}

function Install-AppList {
    $failures = @()

    # Scoop itself needs git (buckets) and 7zip (manifest extraction).
    foreach ($prerequisite in @('main/git', 'main/7zip')) {
        if (Test-ScoopAppInstalled $prerequisite) { continue }
        try { Install-ScoopApp $prerequisite }
        catch { Write-Fail "prerequisite $prerequisite`: $($_.Exception.Message)" }
    }

    foreach ($bucket in $Buckets) {
        try { Add-ScoopBucket $bucket }
        catch { $failures += $bucket; Write-Fail $_.Exception.Message }
    }

    foreach ($app in $Apps) {
        if ($app -like '*/googlechrome' -and -not (Test-ScoopAppInstalled $app) -and (Test-SystemChrome)) {
            Write-Ok 'Google Chrome already installed (system-wide), skipping the Scoop copy'
            continue
        }
        try { Install-ScoopApp $app }
        catch { $failures += $app; Write-Fail $_.Exception.Message }
    }

    if ($failures.Count -gt 0) {
        Write-Warn ('some items failed: ' + ($failures -join ', '))
        Write-Warn 're-run this script to retry them.'
    }
}

function Get-WindowsArch {
    $arch = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($arch)) { $arch = $env:PROCESSOR_ARCHITECTURE }
    if ($arch -eq 'ARM64') { return 'arm64' }
    return 'x64'
}

function Get-OpenCodeVersion {
    if (-not (Test-PathExists $OpenCodeCli)) { return $null }

    try {
        $output = & $OpenCodeCli --version 2>$null
        if (-not $output) { return $null }
        return ($output | Select-Object -First 1).ToString().Trim()
    }
    catch {
        return $null
    }
}

function Test-OpenCodeV2Installed {
    $version = Get-OpenCodeVersion
    return [bool]($version -match '^(opencode\s+)?v?2\.')
}

function Install-OpenCode {
    $version = Get-OpenCodeVersion
    if (Test-OpenCodeV2Installed) {
        Write-Ok "OpenCode V2 already installed ($version)"
        return
    }

    # The old Scoop package is OpenCode V1 and lives next to the V2 install.
    # Remove it so the Start menu and PATH do not keep a stale copy.
    if (Test-ScoopAppInstalled 'extras/opencode-desktop') {
        Write-Info 'removing the old OpenCode V1 Scoop package ...'
        try {
            & $ScoopScript uninstall 'opencode-desktop'
            Write-Ok 'OpenCode V1 (Scoop) removed'
        }
        catch {
            Write-Warn "could not remove the V1 Scoop package: $($_.Exception.Message)"
        }
    }

    $arch = Get-WindowsArch
    $url = $OpenCodeUrl -f $arch
    $installer = Join-Path $env:TEMP "opencode-desktop-win-$arch.exe"

    try {
        Write-Info 'downloading OpenCode V2 desktop from opencode.ai ...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
        Write-Info 'installing OpenCode V2 (silent, per-user) ...'
        Start-Process -FilePath $installer -ArgumentList '/currentuser', '/S' -Wait
    }
    catch {
        Write-Fail "OpenCode V2: $($_.Exception.Message)"
        return
    }
    finally {
        if (Test-PathExists $installer) {
            Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
        }
    }

    # NSIS can return before the worker process has written the files.
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-OpenCodeV2Installed) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
    }

    if (Test-OpenCodeV2Installed) {
        Write-Ok "OpenCode V2 installed ($(Get-OpenCodeVersion))"
    }
    else {
        Write-Fail 'OpenCode V2 installer finished but the CLI was not found; re-run this script'
    }
}

function Set-OpenCodeCli {
    # The desktop bundle ships the CLI; expose it as `opencode` in PowerShell,
    # cmd.exe and Git Bash.
    if (-not (Test-PathExists $OpenCodeCli)) {
        Write-Warn 'opencode-cli.exe not found, skipping the CLI shim'
        return
    }

    $binDir = Join-Path $env:USERPROFILE '.local\bin'
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null

    $cmdContent = "@echo off`r`n`"$OpenCodeCli`" %*`r`n"
    [IO.File]::WriteAllText((Join-Path $binDir 'opencode.cmd'), $cmdContent, [Text.Encoding]::ASCII)

    $shCli = $OpenCodeCli -replace '\\', '/'
    $shContent = "#!/bin/sh`nexec `"$shCli`" `"`$@`"`n"
    [IO.File]::WriteAllText((Join-Path $binDir 'opencode'), $shContent, [Text.Encoding]::ASCII)

    Add-UserPath $binDir
    Write-Ok 'opencode CLI shim installed'
}

# ---------------------------------------------------------------- dotfiles

function Restore-PowerShellConfig {
    if (-not (Test-PathExists $ConfigRoot)) {
        Write-Warn "no config folder at $ConfigRoot, skipping"
        return
    }

    $documents = [Environment]::GetFolderPath('MyDocuments')
    if ([string]::IsNullOrWhiteSpace($documents)) {
        $documents = Join-Path $env:USERPROFILE 'Documents'
    }

    $targets = [ordered]@{
        'PowerShell'        = Join-Path $documents 'PowerShell'          # PowerShell 7
        'WindowsPowerShell' = Join-Path $documents 'WindowsPowerShell'   # Windows PowerShell 5.1
    }

    $restored = 0

    foreach ($name in $targets.Keys) {
        $source = Join-Path $ConfigRoot $name
        if (-not (Test-PathExists $source)) { continue }

        $target = $targets[$name]
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Write-Info "$name -> $target"

        $files = Get-ChildItem -LiteralPath $source -File -Recurse
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($source.Length).TrimStart('\')
            $destination = Join-Path $target $relative
            $destinationDir = Split-Path -Parent $destination
            if ($destinationDir) { New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null }

            if ($SymlinkConfig) {
                if (Test-PathExists $destination) { Remove-Item -LiteralPath $destination -Force }
                try {
                    New-Item -ItemType SymbolicLink -Path $destination -Target $file.FullName -Force | Out-Null
                    Write-Ok "linked $relative"
                    $restored++
                    continue
                }
                catch {
                    Write-Warn "cannot link $relative ($($_.Exception.Message)); copying instead"
                }
            }

            if ((Test-PathExists $destination) -and (Test-FileEqual $destination $file.FullName)) {
                Write-Ok "$relative up to date"
                continue
            }

            if (Test-PathExists $destination) {
                $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $backup = "$destination.bak.$stamp"
                Copy-Item -LiteralPath $destination -Destination $backup -Force
                Write-Warn "existing $relative saved as $(Split-Path -Leaf $backup)"
            }

            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
            Write-Ok "$relative restored"
            $restored++
        }
    }

    Write-Info "$restored file(s) restored"
}

# ---------------------------------------------------------------- summary

function Write-Summary {
    Write-Step 'Summary'

    $checks = [ordered]@{
        scoop    = @((Join-Path $ScoopShims 'scoop.cmd'))
        git      = @((Join-Path $ScoopShims 'git.exe'))
        node     = @((Join-Path $ScoopShims 'node.exe'), (Join-Path $ScoopRoot 'apps\nodejs-lts\current\node.exe'))
        npm      = @((Join-Path $ScoopShims 'npm.cmd'), (Join-Path $ScoopRoot 'apps\nodejs-lts\current\npm.cmd'))
        python   = @(
            (Join-Path $ScoopShims 'python.exe'),
            (Join-Path $ScoopRoot 'apps\python\current\python.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python*\python.exe')
        )
        code     = @((Join-Path $ScoopRoot 'apps\vscode\current\bin\code.cmd'))
        chrome   = @(
            (Join-Path $ScoopShims 'chrome.exe'),
            (Join-Path $ScoopRoot 'apps\googlechrome\current\chrome.exe'),
            (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe')
        )
        subl     = @((Join-Path $ScoopShims 'subl.exe'))
        opencode = @((Join-Path $env:USERPROFILE '.local\bin\opencode.cmd'))
    }

    foreach ($name in $checks.Keys) {
        $found = $false
        foreach ($path in $checks[$name]) {
            $exists = if ($path -match '\*') { [bool](Test-Path -Path $path) } else { Test-PathExists $path }
            if ($exists) { $found = $true; break }
        }
        if ($found) { Write-Ok $name } else { Write-Warn "$name not available yet" }
    }

    Write-Host ''
    Write-Host 'Done. Open a NEW terminal so the updated PATH is loaded.' -ForegroundColor Cyan
    if (-not $SkipConfig) {
        Write-Host 'PowerShell profiles were restored from the repo; restart the terminal to load them.' -ForegroundColor Cyan
    }
}

# ---------------------------------------------------------------- main

Write-Host 'Windots bootstrap' -ForegroundColor White
Write-Host "repo: $ScriptRoot"

if (-not $SkipScoop) {
    Install-Scoop
}

if (-not $SkipApps) {
    if (-not (Test-ScoopInstalled)) {
        Write-Warn 'Scoop is missing (-SkipScoop was used); skipping the app list.'
    }
    else {
        Write-Step 'Installing apps via Scoop'
        Install-AppList

        Write-Step 'Installing OpenCode V2'
        Install-OpenCode
        Set-OpenCodeCli
    }
}

if (-not $SkipConfig) {
    Write-Step 'Restoring PowerShell configuration'
    Restore-PowerShellConfig
}

Write-Summary
