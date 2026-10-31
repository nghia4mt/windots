#Requires -Version 5.1

<#
.SYNOPSIS
    Snapshot the current PowerShell configuration into .\config.

.DESCRIPTION
    Copies every file from
        %USERPROFILE%\Documents\PowerShell           (PowerShell 7)
        %USERPROFILE%\Documents\WindowsPowerShell    (Windows PowerShell 5.1)
    into the repository, so install.ps1 can put it back on a new machine.

    Files matching *.bak* / *.log / *.tmp are ignored.

.PARAMETER Destination
    Folder inside the repo that receives the snapshot. Default: .\config

.PARAMETER Mirror
    Also delete files in the destination that no longer exist in the source,
    keeping the repo an exact copy of the machine.

.EXAMPLE
    .\backup.ps1

.EXAMPLE
    .\backup.ps1 -Mirror
#>

[CmdletBinding()]
param(
    [string] $Destination,
    [switch] $Mirror
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path $PSScriptRoot 'config'
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

$documents = [Environment]::GetFolderPath('MyDocuments')
if ([string]::IsNullOrWhiteSpace($documents)) {
    $documents = Join-Path $env:USERPROFILE 'Documents'
}

$sources = [ordered]@{
    'PowerShell'        = Join-Path $documents 'PowerShell'
    'WindowsPowerShell' = Join-Path $documents 'WindowsPowerShell'
}

$skipPattern = '\.(bak|log|tmp)$|\.bak\.'

Write-Host 'Backing up PowerShell configuration' -ForegroundColor White
Write-Host "source: $documents"
Write-Host "target: $Destination"

$total = 0
$changed = 0

foreach ($name in $sources.Keys) {
    $source = $sources[$name]

    if (-not (Test-Path -LiteralPath $source)) {
        Write-Warn "$name not found, skipped"
        continue
    }

    $target = Join-Path $Destination $name
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Info "$name -> $target"

    $files = Get-ChildItem -LiteralPath $source -File -Recurse |
        Where-Object { $_.Name -notmatch $skipPattern }

    $seen = @()

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($source.Length).TrimStart('\')
        $seen += $relative

        $destPath = Join-Path $target $relative
        $destDir = Split-Path -Parent $destPath
        if ($destDir) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

        $total++

        if (Test-Path -LiteralPath $destPath) {
            $a = (Get-FileHash -LiteralPath $destPath -Algorithm SHA256).Hash
            $b = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            if ($a -eq $b) {
                Write-Ok "$relative unchanged"
                continue
            }
        }

        Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force
        Write-Ok "$relative updated"
        $changed++
    }

    if ($Mirror) {
        $stale = Get-ChildItem -LiteralPath $target -File -Recurse |
            ForEach-Object { $_.FullName.Substring($target.Length).TrimStart('\') } |
            Where-Object { $seen -notcontains $_ }

        foreach ($relative in $stale) {
            Remove-Item -LiteralPath (Join-Path $target $relative) -Force
            Write-Warn "$relative removed (not on this machine)"
            $changed++
        }
    }
}

Write-Host ''
Write-Host "$total file(s) checked, $changed change(s)." -ForegroundColor Cyan
if ($changed -gt 0) {
    Write-Host 'Commit/push the config folder so the snapshot follows you to the next machine.' -ForegroundColor Cyan
}
