
<#
.SYNOPSIS
    Changes the owner of a Power App in a Power Platform environment.

.DESCRIPTION
    This script connects to Power Apps administration and updates the owner of a specified
    Power App. Automatically installs required modules if not present.

.PARAMETER AppName
    The GUID of the Power App to update.

.PARAMETER EnvironmentName
    The GUID of the Power Platform environment where the app is located.

.PARAMETER AppOwner
    The GUID of the new owner (user) to assign to the Power App.

.EXAMPLE
    .\Set-NewPowerAppOwner.ps1 -AppName "cd304785-1a9b-44c3-91a8-c4174b59d835" `
        -EnvironmentName "de6b35af-dd3f-e14d-80ff-7a702c009100" `
        -AppOwner "7eda74de-bd8b-ef11-ac21-000d3a5a9ee8"

.NOTES
    Requires Power Apps administrative permissions.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppOwner
)

# Ensure NuGet provider is installed
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "Installing NuGet provider..." -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
}

# Check and install/update the Power Apps modules
$moduleName = "Microsoft.PowerApps.Administration.PowerShell"
$module = Get-InstalledModule -Name $moduleName -ErrorAction SilentlyContinue

if (-not $module) {
    Write-Host "Installing $moduleName module..." -ForegroundColor Yellow
    Install-Module -Name $moduleName -Force -AllowClobber -Scope CurrentUser
} else {
    Write-Host "Module $moduleName is already installed (Version: $($module.Version))" -ForegroundColor Green
}

# Import the module
Write-Host "Importing module..." -ForegroundColor Yellow
Import-Module $moduleName -Force

# Verify the module is loaded
if (Get-Command -Name Add-PowerAppsAccount -ErrorAction SilentlyContinue) {
    Write-Host "Module loaded successfully!" -ForegroundColor Green
} else {
    Write-Error "Failed to load Power Apps cmdlets. Please install manually: Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force"
    exit
}

# Connect to Power Apps
Write-Host "Connecting to Power Apps..." -ForegroundColor Yellow
try {
    Add-PowerAppsAccount -ErrorAction Stop
    Write-Host "Connected successfully!" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect: $_"
    exit
}

# Set the new Power App owner
Write-Host "Setting new Power App owner..." -ForegroundColor Yellow
Write-Host "  App Name: $AppName" -ForegroundColor Gray
Write-Host "  Environment: $EnvironmentName" -ForegroundColor Gray
Write-Host "  New Owner: $AppOwner" -ForegroundColor Gray

try {
    Set-AdminPowerAppOwner `
      -AppName $AppName `
      -EnvironmentName $EnvironmentName `
      -AppOwner $AppOwner `
      -ErrorAction Stop
    Write-Host "✓ Power App owner updated successfully!" -ForegroundColor Green
} catch {
    Write-Error "Failed to set owner: $_"
}