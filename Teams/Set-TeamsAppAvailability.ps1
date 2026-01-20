<#
.SYNOPSIS
    Blocks a Teams app, making it unavailable to all users.

.PARAMETER AppId
    The App ID of the Teams app to block.

.PARAMETER PolicyName
    The app permission policy name. Defaults to "Global".

.EXAMPLE
    .\Set-TeamsAppAvailability.ps1 -AppId "12345678-1234-1234-1234-123456789012"

.NOTES
    Requires MicrosoftTeams module and Teams Administrator permissions.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$AppId,

    [Parameter(Mandatory = $false)]
    [string]$PolicyName = "Global"
)

try {
    # Connect to Teams
    Write-Host "Connecting to Microsoft Teams..." -ForegroundColor Cyan
    Connect-MicrosoftTeams

    # Block the app
    Write-Host "Blocking Teams app: $AppId in policy: $PolicyName" -ForegroundColor Yellow
    
    Set-CsTeamsAppPermissionPolicy -Identity $PolicyName `
        -DefaultCatalogApps @{Add=@{Id=$AppId; AppState="Blocked"}}

    Write-Host "Successfully blocked the app." -ForegroundColor Green
}
catch {
    Write-Error "Failed: $_"
}
finally {
    Disconnect-MicrosoftTeams | Out-Null
}
