#Requires -Version 7.0

<#
.SYNOPSIS
    One-shot bootstrap for a fresh Windows install.

.DESCRIPTION
    Idempotent: it can be run again at any time without breaking anything.

    Steps
      1. Repair the user environment (drop PATH entries and dev variables
         that point at a folder from an old machine/user).
      2. Install Scoop (per-user, no admin rights needed).
      3. Add the buckets required by the app list.
      4. Install the apps listed in $Apps (Sublime Text 4, Node.js, VS Code,
         Python, ...) and DeepSeek Harness (desktop app + `dsh` CLI shim).
      5. Restore the PowerShell 7 profile/config stored in .\config.

    Requires PowerShell 7 (tested with 7.6.9); Windows PowerShell 5.1 is no
    longer used.

    Run it from a NORMAL (non elevated) PowerShell 7 window:
        pwsh -File .\install.ps1

.PARAMETER SkipScoop
    Do not install/verify Scoop.

.PARAMETER SkipApps
    Do not install the apps from $Apps, nor DeepSeek Harness.

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

# DeepSeek Harness desktop (per-user install) and the CLI it bundles. The CLI
# path is kept relative to %LOCALAPPDATA% so the generated shims can stay pure
# ASCII (batch files are decoded with the console code page, which would mangle
# a literal path under a non-ASCII profile such as C:\Users\Nguyễn).
$DshDir     = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'
$DshExe     = Join-Path $DshDir 'DeepSeek Harness.exe'
$DshCliRel  = 'Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd'
$DshCli     = Join-Path $env:LOCALAPPDATA $DshCliRel
# electron-builder update feed: release version + installer URL + SHA-512.
$DshFeed = 'https://download.deepseek.com/dsh-desk/feeds/win-x64/nightly.yml'

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
    'extras/telegram'           # Telegram Desktop (portable, persists tdata)
    # DeepSeek Harness is a per-user Electron app, not a Scoop package; it is
    # installed from download.deepseek.com by Install-DeepSeekHarness below.

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

function Repair-UserPath {
    # A PATH copied from an old machine (or old Windows profile) keeps entries
    # such as C:\Users\<old-user>\scoop\shims. Windows reports "The system
    # cannot find the path specified." when something walks those directories,
    # so drop entries that no longer exist and collapse duplicates.
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ([string]::IsNullOrWhiteSpace($userPath)) { return }

    $kept = @()
    $removed = @()
    $seen = @{}

    foreach ($entry in ($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $trimmed = $entry.Trim()
        $key = $trimmed.TrimEnd('\').ToLowerInvariant()

        $missing = $false
        if ($trimmed -notmatch '%' -and $trimmed -notmatch '\*') {
            $expanded = [Environment]::ExpandEnvironmentVariables($trimmed)
            $missing = -not (Test-Path -LiteralPath $expanded)
        }

        if ($missing -or $seen.ContainsKey($key)) {
            $removed += $trimmed
            continue
        }

        $seen[$key] = $true
        $kept += $trimmed
    }

    if ($removed.Count -eq 0) {
        Write-Ok 'user PATH has no stale entries'
        return
    }

    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ([string]::IsNullOrWhiteSpace($machinePath)) {
        $env:PATH = ($kept -join ';')
    }
    else {
        $env:PATH = "$machinePath;" + ($kept -join ';')
    }

    foreach ($entry in $removed) { Write-Info "removed from PATH: $entry" }
    Write-Ok "user PATH cleaned ($($removed.Count) stale/duplicate entries removed)"
}

function Repair-UserEnvironment {
    # Dev tools often read JAVA_HOME / GHIDRA_INSTALL_DIR / ... and fail with
    # "The system cannot find the path specified." when they point at a folder
    # from an old machine. Only these well-known variables are checked.
    $names = @(
        'JAVA_HOME'
        'GHIDRA_INSTALL_DIR'
        'MAVEN_HOME'
        'M2_HOME'
        'GRADLE_HOME'
        'ANDROID_HOME'
        'ANDROID_SDK_ROOT'
        'NVM_HOME'
        'NVM_SYMLINK'
    )

    $removed = 0
    foreach ($name in $names) {
        $value = [Environment]::GetEnvironmentVariable($name, 'User')
        if ($null -eq $value) { continue }

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $expanded = [Environment]::ExpandEnvironmentVariables($value)
            if (Test-Path -LiteralPath $expanded) { continue }
        }

        [Environment]::SetEnvironmentVariable($name, $null, 'User')
        Remove-ItemProperty -Path 'HKCU:\Environment' -Name $name -ErrorAction SilentlyContinue
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        Write-Info "removed stale $name=$value"
        $removed++
    }

    if ($removed -eq 0) {
        Write-Ok 'user environment has no stale dev variables'
    }
    else {
        Write-Ok "removed $removed stale user environment variable(s)"
    }
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

function Get-DshInstalledVersion {
    if (-not (Test-PathExists $DshExe)) { return $null }

    $version = (Get-Item -LiteralPath $DshExe).VersionInfo.FileVersion
    if ([string]::IsNullOrWhiteSpace($version)) { return 'unknown' }
    return $version.Trim()
}

function ConvertFrom-DshFeed {
    # nightly.yml is electron-builder's generic update feed: the release
    # version, the installer URL and its SHA-512. Both keys use YAML's folded
    # ">-" style, so this parses the two values it needs instead of pulling in
    # a YAML dependency.
    param([Parameter(Mandatory)][string] $Content)

    $version = [regex]::Match($Content, '(?m)^version:\s*(\S+)').Groups[1].Value
    $url     = [regex]::Match($Content, 'https://download\.deepseek\.com/dsh-desk/bin/\S+\.exe').Value
    $sha512  = [regex]::Match($Content, 'sha512:\s*>-\s*([A-Za-z0-9+/=]{40,})').Groups[1].Value

    if (-not $version -or -not $url) {
        throw 'the update feed has no version/installer URL'
    }

    return [pscustomobject]@{
        Version = $version
        Url     = $url
        Sha512  = $sha512
    }
}

function Get-DshRelease {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri $DshFeed -UseBasicParsing
    return ConvertFrom-DshFeed -Content $response.Content
}

function Test-FileSha512 {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Sha512   # base64, as published in the feed
    )

    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA512).Hash
    return ([Convert]::ToBase64String([Convert]::FromHexString($hash)) -eq $Sha512)
}

function Install-DeepSeekHarness {
    $installed = Get-DshInstalledVersion
    if ($installed) {
        # The desktop app updates itself (electron-updater), so an installed
        # copy is enough: re-downloading ~290 MB on every run is not.
        Write-Ok "DeepSeek Harness already installed ($installed)"
        return
    }

    if ((Get-WindowsArch) -ne 'x64') {
        # download.deepseek.com only publishes the win-x64 desktop build.
        Write-Warn 'no DeepSeek Harness desktop build for this architecture, skipping'
        return
    }

    try {
        Write-Info "resolving the latest DeepSeek Harness release from $DshFeed ..."
        $release = Get-DshRelease
    }
    catch {
        Write-Fail "could not read the DeepSeek Harness update feed: $($_.Exception.Message)"
        return
    }

    $installer = Join-Path $env:TEMP "deepseek-harness-$($release.Version)-win-x64.exe"

    try {
        Write-Info "downloading DeepSeek Harness $($release.Version) (~290 MB) ..."
        Invoke-WebRequest -Uri $release.Url -OutFile $installer -UseBasicParsing

        if ($release.Sha512) {
            if (-not (Test-FileSha512 -Path $installer -Sha512 $release.Sha512)) {
                throw 'SHA-512 mismatch, the download is corrupt'
            }
        }
        else {
            Write-Warn 'the update feed has no SHA-512 for this release, installing unverified'
        }

        Write-Info 'installing DeepSeek Harness (silent, per-user) ...'
        Start-Process -FilePath $installer -ArgumentList '/S' -Wait
    }
    catch {
        Write-Fail "DeepSeek Harness: $($_.Exception.Message)"
        return
    }
    finally {
        if (Test-PathExists $installer) {
            Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
        }
    }

    # NSIS can return before the worker process has written the files.
    $deadline = (Get-Date).AddSeconds(120)
    while (-not (Get-DshInstalledVersion) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
    }

    if (Get-DshInstalledVersion) {
        Write-Ok "DeepSeek Harness installed ($(Get-DshInstalledVersion))"
    }
    else {
        Write-Fail 'the installer finished but the app was not found; re-run this script'
    }
}

function Set-DshCli {
    # DeepSeek Harness ships its Node CLI (the agent + `dsh web`) inside the
    # desktop bundle; expose it as `dsh` in PowerShell, cmd.exe and Git Bash.
    param([string] $BinDir = (Join-Path $env:USERPROFILE '.local\bin'))

    if (-not (Test-PathExists $DshCli)) {
        Write-Warn 'the bundled DeepSeek Harness CLI was not found, skipping the dsh shim'
        return
    }

    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

    # Forward to the shim that ships with the app: it sets
    # ELECTRON_RUN_AS_NODE and runs the CLI on the bundled Node runtime. Both
    # wrappers expand %LOCALAPPDATA% at run time, so they contain ASCII only.
    $cmdContent = "@echo off`r`ncall `"%LOCALAPPDATA%\$DshCliRel`" %*`r`n"
    [IO.File]::WriteAllText((Join-Path $BinDir 'dsh.cmd'), $cmdContent, [Text.Encoding]::ASCII)

    $shRel = $DshCliRel -replace '\\', '/'
    $shContent = "#!/bin/sh`n# Git Bash wrapper: MSYS runs the .cmd shim through cmd.exe.`nexec `"`$LOCALAPPDATA/$shRel`" `"`$@`"`n"
    [IO.File]::WriteAllText((Join-Path $BinDir 'dsh'), $shContent, [Text.Encoding]::ASCII)

    Add-UserPath $BinDir
    Write-Ok 'dsh CLI shim installed'
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
        'PowerShell' = Join-Path $documents 'PowerShell'   # PowerShell 7 only
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
        dsh      = @((Join-Path $env:USERPROFILE '.local\bin\dsh.cmd'))
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

Write-Step 'Repairing the user environment'
Repair-UserPath
Repair-UserEnvironment

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

        Write-Step 'Installing DeepSeek Harness'
        Install-DeepSeekHarness
        Set-DshCli
    }
}

if (-not $SkipConfig) {
    Write-Step 'Restoring PowerShell configuration'
    Restore-PowerShellConfig
}

Write-Summary
