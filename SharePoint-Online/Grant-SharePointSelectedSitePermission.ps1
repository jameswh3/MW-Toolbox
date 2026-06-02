#Requires -Version 7.0

<#
.SYNOPSIS
    Grants Microsoft Graph Sites.Selected permission for a specific SharePoint site to an Entra app.

.DESCRIPTION
    This script resolves a SharePoint site ID using Microsoft Graph, then creates a site permission
    grant for the target application via:
      - GET  /v1.0/sites/{hostname}:/{sitePath}
      - POST /v1.0/sites/{siteId}/permissions

    It supports loading defaults from .env in the repo root:
      - SHAREPOINT_ONLINE_SELECTED_SITES_TARGET_SITE_URL
      - SHAREPOINT_ONLINE_SELECTED_SITES_CLIENT_ID
      - SHAREPOINT_ONLINE_SELECTED_SITES_APP_DISPLAY_NAME
      - SHAREPOINT_ONLINE_SELECTED_SITES_PERMISSION_ROLE

.PARAMETER SiteUrl
    Full SharePoint site URL, for example:
    https://absx28977729.sharepoint.com/sites/Leadership

.PARAMETER TargetAppId
    Application (client) ID of the app that has Sites.Selected application permission.

.PARAMETER TargetAppDisplayName
    Friendly display name stored with the permission grant.

.PARAMETER Role
    Permission role to grant on the site. Valid values: read, write.

.PARAMETER TenantId
    Optional tenant ID to constrain interactive sign-in.

.PARAMETER ForceNew
    Always create a new grant even when a matching grant already exists.

.PARAMETER UseDeviceCode
    Use device code login instead of browser login for Graph authentication.

.PARAMETER ResetAuthContext
    Disconnects any existing Graph context before connecting.
    Helpful in lab scenarios where cached auth context can cause confusing behavior.

.EXAMPLE
    .\SharePoint-Online\Grant-SharePointSelectedSitePermission.ps1 `
      -SiteUrl "https://absx28977729.sharepoint.com/sites/Leadership" `
      -TargetAppId "00000000-0000-0000-0000-000000000000" `
      -TargetAppDisplayName "SPO Transcript Reader" `
      -Role read
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $false)]
    [string]$TargetAppId,

    [Parameter(Mandatory = $false)]
    [string]$TargetAppDisplayName,

    [Parameter(Mandatory = $false)]
    [ValidateSet("read", "write")]
    [string]$Role = "read",

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [switch]$ForceNew,
    [switch]$UseDeviceCode,
    [switch]$ResetAuthContext
)

function Resolve-ScriptDefaultsFromEnv {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Bound
    )

    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $importDotEnvPath = Join-Path $repoRoot "Shared\Import-DotEnv.ps1"
    $dotEnvPath = Join-Path $repoRoot ".env"

    if ((Test-Path -Path $importDotEnvPath) -and (Test-Path -Path $dotEnvPath)) {
        . $importDotEnvPath
        Import-DotEnv -Path $dotEnvPath
    }

    if (-not $Bound.ContainsKey("SiteUrl") -and -not [string]::IsNullOrWhiteSpace($env:SHAREPOINT_ONLINE_SELECTED_SITES_TARGET_SITE_URL)) {
        $script:SiteUrl = $env:SHAREPOINT_ONLINE_SELECTED_SITES_TARGET_SITE_URL
    }
    if (-not $Bound.ContainsKey("SiteUrl") -and [string]::IsNullOrWhiteSpace($script:SiteUrl) -and -not [string]::IsNullOrWhiteSpace($env:SHAREPOINT_ONLINE_SITE)) {
        $script:SiteUrl = $env:SHAREPOINT_ONLINE_SITE
    }

    if (-not $Bound.ContainsKey("TargetAppId") -and -not [string]::IsNullOrWhiteSpace($env:SHAREPOINT_ONLINE_SELECTED_SITES_CLIENT_ID)) {
        $script:TargetAppId = $env:SHAREPOINT_ONLINE_SELECTED_SITES_CLIENT_ID
    }

    if (-not $Bound.ContainsKey("TargetAppDisplayName") -and -not [string]::IsNullOrWhiteSpace($env:SHAREPOINT_ONLINE_SELECTED_SITES_APP_DISPLAY_NAME)) {
        $script:TargetAppDisplayName = $env:SHAREPOINT_ONLINE_SELECTED_SITES_APP_DISPLAY_NAME
    }

    if (-not $Bound.ContainsKey("Role") -and -not [string]::IsNullOrWhiteSpace($env:SHAREPOINT_ONLINE_SELECTED_SITES_PERMISSION_ROLE)) {
        $script:Role = $env:SHAREPOINT_ONLINE_SELECTED_SITES_PERMISSION_ROLE
    }

    if (-not $Bound.ContainsKey("TenantId") -and -not [string]::IsNullOrWhiteSpace($env:SHAREPOINT_ONLINE_SELECTED_SITES_TENANT_ID)) {
        $script:TenantId = $env:SHAREPOINT_ONLINE_SELECTED_SITES_TENANT_ID
    }
    if (-not $Bound.ContainsKey("TenantId") -and [string]::IsNullOrWhiteSpace($script:TenantId) -and -not [string]::IsNullOrWhiteSpace($env:TENANT_ID)) {
        $script:TenantId = $env:TENANT_ID
    }
}

function Assert-RequiredInputs {
    if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
        throw "SiteUrl is required. Provide -SiteUrl or set SHAREPOINT_ONLINE_SELECTED_SITES_TARGET_SITE_URL in .env."
    }

    if ([string]::IsNullOrWhiteSpace($TargetAppId)) {
        throw "TargetAppId is required. Provide -TargetAppId or set SHAREPOINT_ONLINE_SELECTED_SITES_CLIENT_ID in .env."
    }

    if ([string]::IsNullOrWhiteSpace($TargetAppDisplayName)) {
        $script:TargetAppDisplayName = "Sites.Selected App"
    }
}

function Connect-GraphForSitesPermission {
    $requiredScopes = @(
        "Sites.FullControl.All",
        "Application.Read.All"
    )

    try {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    }
    catch {
        throw "Microsoft.Graph.Authentication module is required. Install-Module Microsoft.Graph -Scope CurrentUser"
    }

    $connectArgs = @{
        Scopes    = $requiredScopes
        NoWelcome = $true
        ContextScope = "Process"
    }

    if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
        $connectArgs.TenantId = $TenantId
    }

    if ($UseDeviceCode) {
        $connectArgs.UseDeviceCode = $true
    }

    if ($ResetAuthContext) {
        Write-Host "Resetting existing Graph auth context..." -ForegroundColor Yellow
        if (Get-Command Get-MgContext -ErrorAction SilentlyContinue) {
            $existingContext = Get-MgContext
            if ($null -ne $existingContext) {
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }

    Write-Host "Connecting to Microsoft Graph as admin..." -ForegroundColor Yellow
    Connect-MgGraph @connectArgs | Out-Null
}

function Get-GraphSiteByUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputSiteUrl
    )

    $uri = [System.Uri]$InputSiteUrl
    $hostName = $uri.Host
    $pathPart = $uri.AbsolutePath.Trim('/')

    if ([string]::IsNullOrWhiteSpace($pathPart)) {
        throw "SiteUrl must include a site path, for example /sites/Leadership."
    }

    $requestUri = "https://graph.microsoft.com/v1.0/sites/$hostName`:/$pathPart"
    return Invoke-MgGraphRequest -Uri $requestUri -Method GET -OutputType PSObject
}

function Get-ExistingSitePermissionForApp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteId,

        [Parameter(Mandatory = $true)]
        [string]$AppId
    )

    $permissionsResponse = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/permissions" -Method GET -OutputType PSObject
    $permissions = @($permissionsResponse.value)

    foreach ($permission in $permissions) {
        $identitySets = @()

        if ($permission.grantedToIdentitiesV2) {
            $identitySets += @($permission.grantedToIdentitiesV2)
        }
        if ($permission.grantedToIdentities) {
            $identitySets += @($permission.grantedToIdentities)
        }

        foreach ($identitySet in $identitySets) {
            if ($identitySet.application -and $identitySet.application.id -eq $AppId) {
                return $permission
            }
        }
    }

    return $null
}

function New-GraphSitePermissionGrant {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteId,

        [Parameter(Mandatory = $true)]
        [string]$AppId,

        [Parameter(Mandatory = $true)]
        [string]$AppDisplayName,

        [Parameter(Mandatory = $true)]
        [string]$PermissionRole
    )

    $body = @{
        roles = @($PermissionRole)
        grantedToIdentities = @(
            @{
                application = @{
                    id          = $AppId
                    displayName = $AppDisplayName
                }
            }
        )
    } | ConvertTo-Json -Depth 8

    return Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/permissions" -Method POST -Body $body -ContentType "application/json" -OutputType PSObject
}

try {
    Resolve-ScriptDefaultsFromEnv -Bound $PSBoundParameters
    Assert-RequiredInputs
    Connect-GraphForSitesPermission

    Write-Host "Resolving site ID from URL: $SiteUrl" -ForegroundColor Yellow
    $site = Get-GraphSiteByUrl -InputSiteUrl $SiteUrl

    if (-not $site.id) {
        throw "Graph did not return a site id for $SiteUrl"
    }

    $siteId = $site.id
    Write-Host "Resolved site id: $siteId" -ForegroundColor Green

    $existingPermission = Get-ExistingSitePermissionForApp -SiteId $siteId -AppId $TargetAppId

    if ($existingPermission -and -not $ForceNew) {
        Write-Host "An existing permission grant for app $TargetAppId was found. Use -ForceNew to create another grant." -ForegroundColor Yellow

        [PSCustomObject]@{
            Action             = "ExistingPermissionFound"
            SiteUrl            = $SiteUrl
            SiteId             = $siteId
            PermissionId       = $existingPermission.id
            ExistingRoles      = ($existingPermission.roles -join ',')
            TargetAppId        = $TargetAppId
            TargetAppName      = $TargetAppDisplayName
            RequestedRole      = $Role
            CreatedNewGrant    = $false
            RetrievedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
        }
        return
    }

    Write-Host "Granting $Role permission on site to app $TargetAppId..." -ForegroundColor Yellow
    $grant = New-GraphSitePermissionGrant -SiteId $siteId -AppId $TargetAppId -AppDisplayName $TargetAppDisplayName -PermissionRole $Role

    Write-Host "Permission grant created. Permission ID: $($grant.id)" -ForegroundColor Green

    [PSCustomObject]@{
        Action             = "PermissionGranted"
        SiteUrl            = $SiteUrl
        SiteId             = $siteId
        PermissionId       = $grant.id
        GrantedRoles       = ($grant.roles -join ',')
        TargetAppId        = $TargetAppId
        TargetAppName      = $TargetAppDisplayName
        CreatedNewGrant    = $true
        RetrievedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
    }
}
catch {
    Write-Error "Failed to grant Sites.Selected permission. $($_.Exception.Message)"
    exit 1
}
finally {
    if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}
