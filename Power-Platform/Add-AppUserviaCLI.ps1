<#
.SYNOPSIS
    Adds an app user to Power Platform environment(s) using the Power Platform CLI.

.DESCRIPTION
    This script assigns an application user to one or all Power Platform environments
    with a specified security role. Requires the Power Platform CLI (pac) to be installed.

.PARAMETER AppId
    The Application (Client) ID of the Entra app registration to add as an app user.

.PARAMETER OrgUrl
    The URL of a specific Power Platform environment. Required if -AllEnvironments is not specified.

.PARAMETER Role
    The security role to assign to the app user.
    Default: "System Administrator"

.PARAMETER AllEnvironments
    Switch to process all environments in the tenant. Requires authenticated pac session.

.PARAMETER SkipAuth
    Skip the pac auth create step. Use if already authenticated.

.EXAMPLE
    .\Add-AppUserviaCLI.ps1 -AppId "12345678-1234-1234-1234-123456789012" -OrgUrl "https://org.crm.dynamics.com"
    Adds the app user to a specific environment with System Administrator role.

.EXAMPLE
    .\Add-AppUserviaCLI.ps1 -AppId "12345678-1234-1234-1234-123456789012" -AllEnvironments
    Adds the app user to all environments in the tenant.

.EXAMPLE
    .\Add-AppUserviaCLI.ps1 -AppId "12345678-1234-1234-1234-123456789012" -OrgUrl "https://org.crm.dynamics.com" -Role "Basic User" -SkipAuth
    Adds the app user with a custom role, skipping authentication.

.NOTES
    Requires Power Platform CLI (pac) to be installed.
    Install: winget install Microsoft.PowerPlatformCLI
#>

[CmdletBinding(DefaultParameterSetName = 'SingleEnvironment')]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory = $true, ParameterSetName = 'SingleEnvironment')]
    [ValidateNotNullOrEmpty()]
    [string]$OrgUrl,

    [Parameter(Mandatory = $false)]
    [string]$Role = "System Administrator",

    [Parameter(Mandatory = $true, ParameterSetName = 'AllEnvironments')]
    [switch]$AllEnvironments,

    [Parameter(Mandatory = $false)]
    [switch]$SkipAuth
)

# Check if pac CLI is available
if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    Write-Error "Power Platform CLI (pac) is not installed. Install it using: winget install Microsoft.PowerPlatformCLI"
    exit 1
}

# Authenticate if not skipped
if (-not $SkipAuth) {
    Write-Host "Authenticating with Power Platform..." -ForegroundColor Cyan
    pac auth create
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Authentication failed."
        exit 1
    }
}

# Function to add app user to an environment
function Add-AppUserToEnvironment {
    param (
        [string]$EnvironmentUrl,
        [string]$ApplicationId,
        [string]$SecurityRole
    )

    Write-Host "Adding app user to environment: $EnvironmentUrl" -ForegroundColor Cyan
    Write-Host "  App ID: $ApplicationId" -ForegroundColor Gray
    Write-Host "  Role: $SecurityRole" -ForegroundColor Gray

    $result = pac admin assign-user -u $ApplicationId -au -env $EnvironmentUrl -r $SecurityRole 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Successfully added app user to $EnvironmentUrl" -ForegroundColor Green
        return $true
    } else {
        Write-Warning "Failed to add app user to $EnvironmentUrl"
        Write-Host "  Error: $result" -ForegroundColor Red
        return $false
    }
}

# Process environments
if ($AllEnvironments) {
    Write-Host "`nRetrieving all environments for the tenant..." -ForegroundColor Cyan
    
    # Get list of all environments
    $envListOutput = pac admin list --json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to retrieve environment list. Error: $envListOutput"
        exit 1
    }

    try {
        $environments = $envListOutput | ConvertFrom-Json
        
        if ($environments.Count -eq 0) {
            Write-Warning "No environments found in the tenant."
            exit 0
        }

        Write-Host "Found $($environments.Count) environment(s)" -ForegroundColor Green
        Write-Host ""

        $successCount = 0
        $failCount = 0

        foreach ($env in $environments) {
            $envUrl = $env.EnvironmentUrl
            if ([string]::IsNullOrEmpty($envUrl)) {
                $envUrl = $env.OrganizationUrl
            }

            if ([string]::IsNullOrEmpty($envUrl)) {
                Write-Warning "Skipping environment '$($env.DisplayName)' - no URL found"
                $failCount++
                continue
            }

            if (Add-AppUserToEnvironment -EnvironmentUrl $envUrl -ApplicationId $AppId -SecurityRole $Role) {
                $successCount++
            } else {
                $failCount++
            }
            Write-Host ""
        }

        Write-Host "=" * 60 -ForegroundColor Cyan
        Write-Host "Summary:" -ForegroundColor Cyan
        Write-Host "  Total Environments: $($environments.Count)" -ForegroundColor White
        Write-Host "  Successful: $successCount" -ForegroundColor Green
        Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "White" })
        Write-Host "=" * 60 -ForegroundColor Cyan

    } catch {
        Write-Error "Failed to parse environment list: $_"
        exit 1
    }

} else {
    # Process single environment
    Add-AppUserToEnvironment -EnvironmentUrl $OrgUrl -ApplicationId $AppId -SecurityRole $Role
}
