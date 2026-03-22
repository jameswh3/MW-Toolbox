<#
.SYNOPSIS
    Inventories installed PowerShell modules and optionally updates them.

.DESCRIPTION
    This script retrieves all currently installed PowerShell modules, checks for
    available updates in the PowerShell Gallery, displays an inventory report,
    and optionally updates outdated modules.

.PARAMETER Scope
    The scope to use when updating modules. Valid values: CurrentUser, AllUsers.
    Defaults to CurrentUser.

.PARAMETER SkipPublisherCheck
    Bypass publisher validation checks during module updates.

.PARAMETER Force
    Suppresses confirmation prompts during updates.

.PARAMETER UpdateAll
    Automatically update all outdated modules without prompting.

.PARAMETER InventoryOnly
    Only display the inventory report without checking for or applying updates.

.PARAMETER ExcludeModules
    An array of module names to exclude from updates (inventory still includes them).

.EXAMPLE
    .\Update-InstalledModules.ps1
    Displays inventory and prompts before updating each outdated module.

.EXAMPLE
    .\Update-InstalledModules.ps1 -UpdateAll -Scope AllUsers
    Updates all outdated modules in the AllUsers scope without prompting.

.EXAMPLE
    .\Update-InstalledModules.ps1 -InventoryOnly
    Displays the full module inventory and update availability without making changes.

.EXAMPLE
    .\Update-InstalledModules.ps1 -ExcludeModules @('Az', 'AzureAD') -UpdateAll
    Updates all outdated modules except Az and AzureAD.

.NOTES
    Author: MW-Toolbox
    Requires: PowerShellGet v2.0 or later
    Run as Administrator when using -Scope AllUsers
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [switch]$SkipPublisherCheck,

    [switch]$Force,

    [switch]$UpdateAll,

    [switch]$InventoryOnly,

    [string[]]$ExcludeModules = @()
)

#region Helper Functions

function Write-SectionHeader {
    param ([string]$Title)
    $separator = '=' * 70
    Write-Host "`n$separator" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "$separator" -ForegroundColor Cyan
}

function Write-StatusMessage {
    param (
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    $colors = @{
        Info    = 'Gray'
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
    }
    Write-Host $Message -ForegroundColor $colors[$Level]
}

#endregion

#region Inventory

Write-SectionHeader "PowerShell Module Inventory & Update Tool"
Write-StatusMessage "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info
Write-StatusMessage "Scope  : $Scope" -Level Info

# Ensure PSGallery is available
$gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
if (-not $gallery) {
    Write-StatusMessage "PSGallery repository not found. Registering..." -Level Warning
    Register-PSRepository -Default
}

Write-SectionHeader "Gathering Installed Modules"
Write-StatusMessage "Querying installed modules (this may take a moment)..." -Level Info

$installedModules = Get-InstalledModule -ErrorAction SilentlyContinue |
    Sort-Object Name

if (-not $installedModules) {
    Write-StatusMessage "No modules installed via PSGallery/PowerShellGet were found." -Level Warning
    exit
}

Write-StatusMessage "Found $($installedModules.Count) installed module(s)." -Level Success

#endregion

#region Check for Updates

if (-not $InventoryOnly) {
    Write-SectionHeader "Checking for Available Updates"
    Write-StatusMessage "Querying PowerShell Gallery for latest versions..." -Level Info
}

$inventory = [System.Collections.Generic.List[PSCustomObject]]::new()
$counter   = 0

foreach ($module in $installedModules) {
    $counter++
    $percentComplete = [math]::Round(($counter / $installedModules.Count) * 100)

    Write-Progress -Activity "Checking modules" `
                   -Status "$counter of $($installedModules.Count) - $($module.Name)" `
                   -PercentComplete $percentComplete

    $entry = [PSCustomObject]@{
        Name             = $module.Name
        InstalledVersion = $module.Version
        LatestVersion    = $null
        UpdateAvailable  = $false
        Repository       = $module.Repository
        InstalledDate    = $module.InstalledDate
        Description      = $module.Description
        Excluded         = $module.Name -in $ExcludeModules
        UpdateStatus     = 'Current'
    }

    if (-not $InventoryOnly) {
        try {
            $latest = Find-Module -Name $module.Name -Repository PSGallery -ErrorAction Stop
            $entry.LatestVersion = $latest.Version

            if ($latest.Version -gt $module.Version) {
                $entry.UpdateAvailable = $true
                $entry.UpdateStatus    = if ($module.Name -in $ExcludeModules) { 'Excluded' } else { 'UpdateAvailable' }
            }
        }
        catch {
            $entry.LatestVersion = 'N/A'
            $entry.UpdateStatus  = 'NotInGallery'
        }
    }

    $inventory.Add($entry)
}

Write-Progress -Activity "Checking modules" -Completed

#endregion

#region Display Inventory Report

Write-SectionHeader "Installed Module Inventory"

$inventory | Format-Table -AutoSize -Property @(
    @{ Label = 'Module Name';       Expression = { $_.Name }; Width = 40 },
    @{ Label = 'Installed';         Expression = { $_.InstalledVersion }; Width = 15 },
    @{ Label = 'Latest';            Expression = { if ($_.LatestVersion) { $_.LatestVersion } else { '(not checked)' } }; Width = 15 },
    @{ Label = 'Update Available';  Expression = { if ($_.UpdateAvailable) { 'YES' } else { '' } }; Width = 16 },
    @{ Label = 'Status';            Expression = { $_.UpdateStatus }; Width = 16 },
    @{ Label = 'Repository';        Expression = { $_.Repository }; Width = 12 }
)

# Summary stats
$totalInstalled    = $inventory.Count
$updatesAvailable  = ($inventory | Where-Object UpdateStatus -eq 'UpdateAvailable').Count
$excluded          = ($inventory | Where-Object UpdateStatus -eq 'Excluded').Count
$notInGallery      = ($inventory | Where-Object UpdateStatus -eq 'NotInGallery').Count
$current           = ($inventory | Where-Object UpdateStatus -eq 'Current').Count

Write-SectionHeader "Summary"
Write-Host "  Total Installed   : " -NoNewline; Write-Host $totalInstalled   -ForegroundColor Cyan
Write-Host "  Current / Up-to-date: " -NoNewline; Write-Host $current         -ForegroundColor Green
Write-Host "  Updates Available : " -NoNewline; Write-Host $updatesAvailable  -ForegroundColor $(if ($updatesAvailable -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  Excluded          : " -NoNewline; Write-Host $excluded          -ForegroundColor Gray
Write-Host "  Not in Gallery    : " -NoNewline; Write-Host $notInGallery      -ForegroundColor Gray

if ($InventoryOnly) {
    Write-StatusMessage "`n-InventoryOnly specified. No updates will be applied." -Level Info
    exit
}

#endregion

#region Apply Updates

$modulesToUpdate = $inventory | Where-Object UpdateStatus -eq 'UpdateAvailable'

if ($modulesToUpdate.Count -eq 0) {
    Write-StatusMessage "`nAll modules are up to date. Nothing to update." -Level Success
    exit
}

Write-SectionHeader "Updating Modules"

$updateParams = @{
    Scope       = $Scope
    Force       = $true   # suppresses untrusted-repository confirmation
    ErrorAction = 'Continue'
}
if ($SkipPublisherCheck) { $updateParams['SkipPublisherCheck'] = $true }

$successCount      = 0
$failCount         = 0
$skippedCount      = 0
$updateAllRemaining = $UpdateAll  # set by -UpdateAll switch or A response

foreach ($mod in $modulesToUpdate) {
    $label = "$($mod.Name) [$($mod.InstalledVersion) → $($mod.LatestVersion)]"

    if (-not $updateAllRemaining) {
        $response = (Read-Host "`nUpdate $label ? [Y] Yes  [A] Yes to All  [N] No  [Q] Quit").Trim().ToUpper()
        switch ($response) {
            'Q' { Write-StatusMessage "Update process cancelled by user." -Level Warning; break }
            'A' { $updateAllRemaining = $true }   # fall through to update
            'Y' { }                                # fall through to update
            default {
                Write-StatusMessage "  Skipped: $($mod.Name)" -Level Info
                $skippedCount++
                continue
            }
        }
        # re-check in case Q was hit inside the switch (break only exits switch)
        if ($response -eq 'Q') { break }
    }

    if ($PSCmdlet.ShouldProcess($mod.Name, "Update-Module to $($mod.LatestVersion)")) {
        Write-StatusMessage "  Updating: $label" -Level Info
        try {
            Update-Module -Name $mod.Name @updateParams
            Write-StatusMessage "  Updated : $($mod.Name) to $($mod.LatestVersion)" -Level Success
            $successCount++
        }
        catch {
            Write-StatusMessage "  Failed  : $($mod.Name) — $($_.Exception.Message)" -Level Error
            $failCount++
        }
    }
}

#endregion

#region Final Report

Write-SectionHeader "Update Results"
Write-Host "  Successfully Updated : " -NoNewline; Write-Host $successCount -ForegroundColor Green
Write-Host "  Failed               : " -NoNewline; Write-Host $failCount    -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host "  Skipped              : " -NoNewline; Write-Host $skippedCount -ForegroundColor Gray
Write-StatusMessage "`nCompleted: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info

#endregion
