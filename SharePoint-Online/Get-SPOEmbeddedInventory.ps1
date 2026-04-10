function Get-SPOEmbeddedInventory {
    <#
    .SYNOPSIS
        Inventories all SharePoint Embedded containers in the tenant.

    .DESCRIPTION
        Retrieves all SharePoint Embedded containers using Get-SPOContainer, then enriches
        each container with detailed properties and maps owning application IDs to friendly
        names. Known Microsoft application IDs (Loop, Designer, etc.) are automatically
        resolved. Application-level metadata is also retrieved via Get-SPOApplication.

        Requires the SharePoint Online Management Shell module and SharePoint Embedded Administrator
        or Global Administrator role.

        Reference: https://learn.microsoft.com/en-us/sharepoint/dev/embedded/administration/consuming-tenant-admin/ctapowershell

    .PARAMETER SPOAdminUrl
        The SharePoint Online admin center URL (e.g., https://contoso-admin.sharepoint.com).

    .PARAMETER OutputPath
        Optional. File path for CSV export of the container inventory.

    .EXAMPLE
        Get-SPOEmbeddedInventory -SPOAdminUrl "https://contoso-admin.sharepoint.com"

    .EXAMPLE
        Get-SPOEmbeddedInventory -SPOAdminUrl "https://contoso-admin.sharepoint.com" -OutputPath "c:\temp\spe-inventory.csv"

    .NOTES
        Requires: Microsoft.Online.SharePoint.PowerShell module
        Install via: Install-Module -Name Microsoft.Online.SharePoint.PowerShell
        Role required: SharePoint Embedded Administrator or Global Administrator
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$SPOAdminUrl,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath
    )

    # Known Microsoft application IDs mapped to friendly names
    # Source: https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spocontainer
    $knownApplications = @{
        "e8be65d6-d430-4289-a665-51bf2a194bda" = "Microsoft Declarative Agent"
        "5e2795e3-ce8c-4cfb-b302-35fe5cd01597" = "Microsoft Designer"
        "a187e399-0c36-4b98-8f04-1edc167a0996" = "Microsoft Loop"
        "155d75a8-799c-4ad4-ae3f-0084ccced5fa" = "Microsoft Outlook Newsletters"
        "7fc21101-d09b-4343-8eb3-21187e0431a4" = "Microsoft Teams Events Video on Demand"
    }

    # Import module (requires -UseWindowsPowerShell for PowerShell 7+)
    try {
        Import-Module -Name Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to import Microsoft.Online.SharePoint.PowerShell module. Install it with: Install-Module -Name Microsoft.Online.SharePoint.PowerShell"
        return
    }

    # Connect to SPO
    try {
        Write-Host "Connecting to SharePoint Online Admin Center..." -ForegroundColor Yellow
        Connect-SPOService -Url $SPOAdminUrl -ErrorAction Stop
        Write-Host "Connected successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to SharePoint Online: $_"
        return
    }

    # Get all containers in the tenant
    Write-Host "Retrieving all SharePoint Embedded containers..." -ForegroundColor Yellow
    try {
        $containers = Get-SPOContainer -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to retrieve containers: $_"
        return
    }

    if (-not $containers) {
        Write-Host "No SharePoint Embedded containers found in this tenant." -ForegroundColor Yellow
        return
    }

    Write-Host "Found $($containers.Count) container(s). Retrieving details..." -ForegroundColor Green

    # Cache application lookups to avoid repeated calls for the same app ID
    $appCache = @{}

    $allResults = @()
    $containerIndex = 0

    foreach ($container in $containers) {
        $containerIndex++
        Write-Host "  [$containerIndex/$($containers.Count)] Processing container: $($container.ContainerId)" -ForegroundColor Cyan

        # Get detailed container properties
        $detail = $null
        try {
            $detail = Get-SPOContainer -Identity $container.ContainerId -ErrorAction Stop
        }
        catch {
            Write-Host "    Could not retrieve details: $_" -ForegroundColor Red
        }

        # Resolve owning application info (use cache to avoid repeat lookups)
        $owningAppId = if ($detail) { $detail.OwningApplicationId } else { $container.OwningApplicationId }
        $appIdStr = if ($owningAppId) { $owningAppId.ToString() } else { $null }

        $appName = $null
        $friendlyName = $null
        $sharingCapability = $null
        $overrideTenantSharing = $null

        if ($appIdStr) {
            # Check known Microsoft apps
            if ($knownApplications.ContainsKey($appIdStr)) {
                $friendlyName = $knownApplications[$appIdStr]
            }

            # Look up application details (cached)
            if (-not $appCache.ContainsKey($appIdStr)) {
                try {
                    $appInfo = Get-SPOApplication -OwningApplicationId $appIdStr -ErrorAction Stop
                    $appCache[$appIdStr] = $appInfo
                }
                catch {
                    $appCache[$appIdStr] = $null
                }
            }

            $cachedApp = $appCache[$appIdStr]
            if ($cachedApp) {
                $appName = $cachedApp.OwningApplicationName
                $sharingCapability = $cachedApp.SharingCapability
                $overrideTenantSharing = $cachedApp.OverrideTenantSharingCapability
            }
        }

        $record = [PSCustomObject]@{
            ContainerId                     = $container.ContainerId
            ContainerName                   = if ($detail) { $detail.ContainerName } else { $container.ContainerName }
            ContainerSiteUrl                = if ($detail) { $detail.ContainerSiteUrl } else { $container.ContainerSiteUrl }
            StorageUsed                     = if ($detail) { $detail.StorageUsed } else { $null }
            OwnersCount                     = if ($detail -and $detail.Owners) { $detail.Owners.Count } else { $null }
            SensitivityLabel                = if ($detail) { $detail.SensitivityLabel } else { $null }
            CreatedDate                     = if ($detail) { $detail.CreatedOn } else { $null }
            Status                          = if ($detail) { $detail.Status } else { $null }
            OwningApplicationId             = $appIdStr
            OwningApplicationName           = $appName
            KnownFriendlyName               = $friendlyName
            SharingCapability               = $sharingCapability
            OverrideTenantSharingCapability  = $overrideTenantSharing
        }
        $allResults += $record
    }

    # Display summary
    Write-Host "`n================ Inventory Summary ================" -ForegroundColor Cyan
    Write-Host "Total Containers: $($allResults.Count)" -ForegroundColor White
    $uniqueApps = ($allResults | Select-Object -ExpandProperty OwningApplicationId -Unique | Where-Object { $_ }).Count
    Write-Host "Unique Applications: $uniqueApps" -ForegroundColor White
    Write-Host "===================================================" -ForegroundColor Cyan

    # Export to CSV if OutputPath specified
    if ($OutputPath) {
        try {
            $allResults | Export-Csv -Path $OutputPath -NoTypeInformation -ErrorAction Stop
            Write-Host "`nInventory exported to $OutputPath" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to export CSV: $_"
        }
    }

    # Return results to pipeline
    return $allResults
}
