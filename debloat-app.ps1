#Requires -Version 5.1

<#
.SYNOPSIS
    Remove the preinstalled "junk" apps that ship with a fresh Windows 11.

.DESCRIPTION
    Removes (per-user and, when elevated, the provisioned copy so new accounts
    stay clean) a curated list of built-in bloat: Bing apps, news/weather,
    Office hub, Solitaire, Clipchamp, Xbox, promoted third-party stubs, etc.

    Busybox apps that are actually useful (Store, Terminal, Calculator,
    Notepad, Paint, Photos, Camera, Snipping Tool, Clock, Sticky Notes) are
    protected and are never touched.

    Nothing is removed by default that you cannot get back from the Store.

.PARAMETER DryRun
    Show what would be removed, change nothing.

.PARAMETER IncludeXbox
    Also remove the Xbox / Gaming app packages.

.PARAMETER IncludePhoneLink
    Also remove Phone Link (Your Phone / Cross Device).

.PARAMETER RemoveOneDrive
    Uninstall OneDrive (needs admin). Local OneDrive files are left untouched.

.PARAMETER DisableCopilot
    Hide Copilot (policy + taskbar button).

.PARAMETER DisableWidgets
    Hide the Widgets button in the taskbar.

.PARAMETER DisableBingSearch
    Disable web/Bing suggestions in Start menu search and hide the Chat icon.

.PARAMETER CreateRestorePoint
    Create a System Restore point before doing anything.

.PARAMETER All
    Shortcut for -IncludeXbox -IncludePhoneLink -DisableCopilot -DisableWidgets
    -DisableBingSearch (OneDrive is NOT included on purpose).

.EXAMPLE
    .\debloat-app.ps1 -DryRun

.EXAMPLE
    .\debloat-app.ps1
    # remove the default bloat only

.EXAMPLE
    .\debloat-app.ps1 -All -RemoveOneDrive -CreateRestorePoint
#>

[CmdletBinding()]
param(
    [switch] $DryRun,
    [switch] $IncludeXbox,
    [switch] $IncludePhoneLink,
    [switch] $RemoveOneDrive,
    [switch] $DisableCopilot,
    [switch] $DisableWidgets,
    [switch] $DisableBingSearch,
    [switch] $CreateRestorePoint,
    [switch] $All
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($All) {
    $IncludeXbox = $true
    $IncludePhoneLink = $true
    $DisableCopilot = $true
    $DisableWidgets = $true
    $DisableBingSearch = $true
}

# --------------------------------------------------------- PowerShell 7 shim

# Get-AppxPackage / Remove-AppxPackage / Get-AppxProvisionedPackage only work
# in Windows PowerShell 5.1; PowerShell 7 cannot load the Appx module. Relaunch
# there so `pwsh .\debloat-app.ps1` behaves exactly like from powershell.exe.
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Host "    [info]    PowerShell $($PSVersionTable.PSVersion) cannot use the Appx cmdlets, relaunching in Windows PowerShell 5.1 ..." -ForegroundColor Yellow

    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        throw 'Cannot detect the script path; run debloat-app.ps1 with -File (not dot-sourced).'
    }

    $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath)
    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $childArgs += "-$key" }
        }
        else {
            $childArgs += "-$key"
            $childArgs += [string]$value
        }
    }

    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @childArgs
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------- app lists

# Safe-to-remove bloat that a normal user never asks for.
$JunkApps = @(
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.BingFinance'
    'Microsoft.BingSports'
    'Microsoft.BingTravel'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'                 # Tips
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MixedReality.Portal'
    'Microsoft.ZuneMusic'                  # legacy Media Player
    'Microsoft.ZuneVideo'                  # Movies & TV
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.People'
    'Microsoft.SkypeApp'
    'Microsoft.Teams'
    'MSTeams'                              # Teams consumer
    'Clipchamp.Clipchamp'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.Todos'
    'Microsoft.Copilot'
    'Microsoft.OutlookForWindows'          # new Outlook
    'Microsoft.WindowsCommunicationsApps'  # Mail & Calendar
    'Microsoft.549981C3F5F10'              # Cortana
    'Microsoft.Windows.DevHome'
    'Microsoft.MicrosoftJournal'
    'Microsoft.Print3D'
    'Microsoft.OneConnect'
    'Microsoft.NetworkSpeedTest'
    'SpotifyAB.SpotifyMusic'
    'Disney.37853FC22B2CE'
    'BytedancePte.Ltd.TikTok'
)

$XboxApps = @(
    'Microsoft.GamingApp'
    'Microsoft.XboxApp'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.Xbox.TCUI'
)

$PhoneLinkApps = @(
    'Microsoft.YourPhone'
    'MicrosoftWindows.CrossDevice'
)

# Never removed, even if a list above is edited by mistake.
$Protected = @(
    'Microsoft.WindowsStore'
    'Microsoft.StorePurchaseApp'
    'Microsoft.DesktopAppInstaller'
    'Microsoft.WindowsTerminal'
    'Microsoft.WindowsCalculator'
    'Microsoft.Paint'
    'Microsoft.ScreenSketch'
    'Microsoft.Windows.Photos'
    'Microsoft.WindowsCamera'
    'Microsoft.WindowsNotepad'
    'Microsoft.WindowsAlarms'
    'Microsoft.MicrosoftStickyNotes'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.SecHealthUI'
    'Microsoft.Windows.Search'
    'Microsoft.UI.Xaml*'
    'Microsoft.VCLibs*'
    'Microsoft.NET.Native*'
    'Microsoft.WindowsAppRuntime*'
    'Microsoft.Windows.ShellExperienceHost'
    'Microsoft.Windows.StartMenuExperienceHost'
    'Microsoft.AAD.BrokerPlugin'
    'Microsoft.AccountsControl'
    'Microsoft.LockApp'
    'MicrosoftWindows.Client*'
    'MicrosoftWindows.UndockedDevKit'
    'Microsoft.Win32WebViewHost'
)

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
    Write-Host "    [removed] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "    [warn]    $Message" -ForegroundColor Yellow
}

function Write-Skip {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "    [skip]    $Message" -ForegroundColor DarkGray
}

function Write-Plan {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "    [dry-run] $Message" -ForegroundColor Magenta
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Protected {
    param([Parameter(Mandatory)][string] $Name)
    foreach ($pattern in $Protected) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)] $Value,
        [ValidateSet('DWord', 'String')][string] $Type = 'DWord'
    )

    if ($DryRun) {
        Write-Plan "set $Path\$Name = $Value"
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-Info "set $Name = $Value"
}

# ---------------------------------------------------------------- state

$script:IsAdmin = Test-IsAdministrator
$script:UseAllUsers = $script:IsAdmin
$script:removed = 0
$script:provisionedRemoved = 0
$script:failed = 0
$script:Provisioned = @{}

# ---------------------------------------------------------------- actions

function Invoke-AppRemoval {
    param([string[]] $Names)

    foreach ($name in $Names) {
        if (Test-Protected $name) {
            Write-Skip "$name (protected)"
            continue
        }

        $found = $false

        # 1. package installed for the current user / all users
        $packages = @()
        try {
            if ($script:UseAllUsers) {
                $packages = @(Get-AppxPackage -Name $name -AllUsers -ErrorAction Stop)
            }
            else {
                $packages = @(Get-AppxPackage -Name $name -ErrorAction Stop)
            }
        }
        catch {
            $packages = @()
        }

        foreach ($package in $packages) {
            $found = $true
            if ($DryRun) {
                Write-Plan "would remove $($package.PackageFullName)"
                continue
            }
            try {
                if ($script:UseAllUsers) {
                    Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
                }
                else {
                    Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
                }
                Write-Ok "$($package.Name)"
                $script:removed++
            }
            catch {
                Write-Warn "cannot remove $($package.Name): $($_.Exception.Message)"
                $script:failed++
            }
        }

        # 2. provisioned copy -> new accounts stay clean (admin only)
        if ($script:UseAllUsers) {
            $provisioned = @()
            if ($script:Provisioned.ContainsKey($name)) {
                $provisioned = @($script:Provisioned[$name])
            }

            foreach ($package in $provisioned) {
                $found = $true
                if ($DryRun) {
                    Write-Plan "would remove provisioned $($package.DisplayName)"
                    continue
                }
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop | Out-Null
                    Write-Ok "$($package.DisplayName) (provisioned)"
                    $script:provisionedRemoved++
                }
                catch {
                    Write-Warn "cannot remove provisioned $($package.DisplayName): $($_.Exception.Message)"
                    $script:failed++
                }
            }
        }

        if (-not $found) { Write-Skip "$name (not installed)" }
    }
}

function Disable-OneDrive {
    $setupCandidates = @(
        (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
        (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
    )
    $setup = $setupCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if (-not $setup) {
        Write-Skip 'OneDrive is not installed'
        return
    }

    if ($DryRun) {
        Write-Plan "would uninstall OneDrive via $setup /uninstall"
        return
    }

    if (-not $script:IsAdmin) {
        Write-Warn 'uninstalling OneDrive needs admin, skipped'
        return
    }

    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait
    Write-Ok 'OneDrive uninstalled (your OneDrive folder is untouched)'
}

# ---------------------------------------------------------------- main

Write-Host 'Windows 11 debloat' -ForegroundColor White
if ($DryRun) {
    Write-Host 'mode: dry-run (nothing will be changed)' -ForegroundColor Magenta
}
elseif (-not $script:IsAdmin) {
    Write-Warn 'not elevated: per-user apps only, provisioned copies stay. Re-run as admin for a full cleanup.'
}

if ($script:IsAdmin) {
    # Read provisioned packages once (one roundtrip instead of one per app).
    try {
        foreach ($provisionedPackage in (Get-AppxProvisionedPackage -Online -ErrorAction Stop)) {
            $displayName = $provisionedPackage.DisplayName
            if ([string]::IsNullOrEmpty($displayName)) { continue }
            if (-not $script:Provisioned.ContainsKey($displayName)) {
                $script:Provisioned[$displayName] = @()
            }
            $script:Provisioned[$displayName] += $provisionedPackage
        }
    }
    catch {
        Write-Warn "cannot read provisioned packages: $($_.Exception.Message)"
        $script:UseAllUsers = $false
    }
}

if ($CreateRestorePoint -and -not $DryRun) {
    Write-Step 'Creating a restore point'
    try {
        Checkpoint-Computer -Description 'windots debloat' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Info 'restore point created'
    }
    catch {
        Write-Warn "could not create a restore point: $($_.Exception.Message)"
    }
}

Write-Step 'Removing built-in junk apps'
Invoke-AppRemoval $JunkApps

if ($IncludeXbox) {
    Write-Step 'Removing Xbox / gaming packages'
    Invoke-AppRemoval $XboxApps
}

if ($IncludePhoneLink) {
    Write-Step 'Removing Phone Link'
    Invoke-AppRemoval $PhoneLinkApps
}

if ($RemoveOneDrive) {
    Write-Step 'Uninstalling OneDrive'
    Disable-OneDrive
}

if ($DisableCopilot) {
    Write-Step 'Disabling Copilot'
    Set-RegistryValue 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0
}

if ($DisableWidgets) {
    Write-Step 'Hiding Widgets button'
    Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0
}

if ($DisableBingSearch) {
    Write-Step 'Disabling web/Bing search in Start menu'
    Set-RegistryValue 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0
}

Write-Step 'Summary'
if ($DryRun) {
    Write-Host '    dry-run finished, nothing was removed.' -ForegroundColor Cyan
}
else {
    Write-Host "    apps removed: $($script:removed), provisioned entries: $($script:provisionedRemoved)" -ForegroundColor Cyan
    if ($script:failed -gt 0) {
        Write-Host "    failures: $($script:failed) (usually apps that are in use; close them and re-run)" -ForegroundColor Yellow
    }
    Write-Host '    sign out / restart to finish applying.' -ForegroundColor Cyan
}
