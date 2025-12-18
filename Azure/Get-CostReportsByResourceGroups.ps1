function Get-AzureCostReportsByResourceGroups {
    <#
    .SYNOPSIS
        Get cost reports for Azure resource groups for a specified date range.

    .DESCRIPTION
        This function retrieves cost data for selected Azure resource groups using Azure Cost Management API.
        Allows selection of resource groups and provides detailed cost breakdown by resource type.

    .PARAMETER StartDate
        The start date for the cost report. Default is 7 days ago.

    .PARAMETER EndDate
        The end date for the cost report. Default is today.

    .PARAMETER SubscriptionId
        The Azure subscription ID. If not specified, uses the current context.

    .EXAMPLE
        Get-AzureCostReportsByResourceGroups
        Gets cost reports for the last 7 days with resource group selection prompt.

    .EXAMPLE
        Get-AzureCostReportsByResourceGroups -StartDate "2025-12-01" -EndDate "2025-12-17"
        Gets cost reports for the specified date range.

    .NOTES
        Author: James Hammonds
        Requires: Az.ResourceGraph, Az.Accounts, Az.CostManagement modules
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [DateTime]$StartDate = (Get-Date).AddDays(-7),
        
        [Parameter(Mandatory = $false)]
        [DateTime]$EndDate = (Get-Date),
        
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionId
    )

    # Ensure required modules are installed
    $requiredModules = @('Az.Accounts', 'Az.ResourceGraph', 'Az.CostManagement')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "Installing module: $module" -ForegroundColor Yellow
            Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
        }
        Import-Module $module -ErrorAction Stop
    }

    # Connect to Azure if not already connected
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Host "Connecting to Azure..." -ForegroundColor Cyan
            Connect-AzAccount
            $context = Get-AzContext
        }
        Write-Host "Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
        Write-Host "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Azure: $_"
        return
    }

    # Use provided subscription or current context
    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }
    else {
        $SubscriptionId = (Get-AzContext).Subscription.Id
    }

    # Validate date range
    if ($EndDate -lt $StartDate) {
        Write-Error "End date must be after start date."
        return
    }

    Write-Host "`nDate Range: $($StartDate.ToString('yyyy-MM-dd')) to $($EndDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan

    # Get all resource groups
    Write-Host "`nRetrieving resource groups..." -ForegroundColor Cyan
    $resourceGroups = Get-AzResourceGroup | Select-Object ResourceGroupName, Location | Sort-Object ResourceGroupName

    if ($resourceGroups.Count -eq 0) {
        Write-Error "No resource groups found in subscription."
        return
    }

    # Display resource groups for selection
    Write-Host "`nAvailable Resource Groups:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $resourceGroups.Count; $i++) {
        Write-Host "  [$($i + 1)] $($resourceGroups[$i].ResourceGroupName) - $($resourceGroups[$i].Location)"
    }
    Write-Host "  [A] All Resource Groups" -ForegroundColor Green
    Write-Host "  [Q] Quit" -ForegroundColor Red

    # Get user selection
    $selection = Read-Host "`nSelect resource group(s) (comma-separated numbers, 'A' for all, or 'Q' to quit)"

    if ($selection -eq 'Q') {
        Write-Host "Exiting..." -ForegroundColor Yellow
        return
    }

    # Process selection
    $selectedGroups = @()
    if ($selection -eq 'A') {
        $selectedGroups = $resourceGroups
        Write-Host "`nSelected all $($selectedGroups.Count) resource groups." -ForegroundColor Green
    }
    else {
        $indices = $selection -split ',' | ForEach-Object { $_.Trim() }
        foreach ($index in $indices) {
            if ($index -match '^\d+$' -and [int]$index -ge 1 -and [int]$index -le $resourceGroups.Count) {
                $selectedGroups += $resourceGroups[[int]$index - 1]
            }
            else {
                Write-Warning "Invalid selection: $index"
            }
        }
        
        if ($selectedGroups.Count -eq 0) {
            Write-Error "No valid resource groups selected."
            return
        }
        
        Write-Host "`nSelected $($selectedGroups.Count) resource group(s):" -ForegroundColor Green
        $selectedGroups | ForEach-Object { Write-Host "  - $($_.ResourceGroupName)" }
    }

    # Prepare results
    $allResults = @()

    # Get costs for each selected resource group
    foreach ($rg in $selectedGroups) {
        Write-Host "`nRetrieving cost data for: $($rg.ResourceGroupName)..." -ForegroundColor Cyan
        
        try {
            # Build the scope
            $scope = "/subscriptions/$SubscriptionId/resourceGroups/$($rg.ResourceGroupName)"
        
            # Query cost data using Azure Cost Management
            $costQuery = @{
                type      = "ActualCost"
                timeframe = "Custom"
                timePeriod = @{
                    from = $StartDate.ToString("yyyy-MM-ddT00:00:00Z")
                    to   = $EndDate.ToString("yyyy-MM-ddT23:59:59Z")
                }
                dataset   = @{
                    granularity = "Daily"
                    aggregation = @{
                        totalCost = @{
                            name     = "Cost"
                            function = "Sum"
                        }
                    }
                    grouping    = @(
                        @{
                            type = "Dimension"
                            name = "ResourceType"
                        },
                        @{
                            type = "Dimension"
                            name = "ResourceId"
                        }
                    )
                }
            }
            
            # Execute query
            $results = Invoke-AzRestMethod -Path "$scope/providers/Microsoft.CostManagement/query?api-version=2023-03-01" `
                -Method POST `
                -Payload ($costQuery | ConvertTo-Json -Depth 10)
            
            if ($results.StatusCode -eq 200) {
                $costData = ($results.Content | ConvertFrom-Json)
                
                if ($costData.properties.rows.Count -gt 0) {
                    $totalCost = 0
                    $resourceCosts = @()
                    
                    foreach ($row in $costData.properties.rows) {
                        $cost = [math]::Round($row[0], 2)
                        $currency = $row[1]
                        $resourceType = $row[2]
                        $resourceId = $row[3]
                        $resourceName = if ($resourceId) { ($resourceId -split '/')[-1] } else { "N/A" }
                        
                        $totalCost += $cost
                        
                        $resourceCosts += [PSCustomObject]@{
                            ResourceGroup = $rg.ResourceGroupName
                            ResourceType  = $resourceType
                            ResourceName  = $resourceName
                            ResourceId    = $resourceId
                            Cost          = $cost
                            Currency      = $currency
                        }
                    }
                    
                    Write-Host "  Total Cost: $([math]::Round($totalCost, 2)) $($costData.properties.rows[0][1])" -ForegroundColor Green
                    
                    $allResults += $resourceCosts
                }
                else {
                    Write-Host "  No cost data found for this resource group in the specified date range." -ForegroundColor Yellow
                }
            }
            else {
                Write-Warning "Failed to retrieve cost data for $($rg.ResourceGroupName). Status: $($results.StatusCode)"
            }
        }
        catch {
            Write-Warning "Error retrieving cost data for $($rg.ResourceGroupName): $_"
        }
    }

    # Display summary
    if ($allResults.Count -gt 0) {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "COST SUMMARY" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        
        # Group by resource group
        $groupedByRG = $allResults | Group-Object ResourceGroup
        foreach ($group in $groupedByRG | Sort-Object Name) {
            $rgTotal = ($group.Group | Measure-Object -Property Cost -Sum).Sum
            Write-Host "`nResource Group: $($group.Name)" -ForegroundColor Yellow
            Write-Host "  Total Cost: $([math]::Round($rgTotal, 2)) $($group.Group[0].Currency)" -ForegroundColor Green
            
            # Top 5 most expensive resources
            $topResources = $group.Group | Sort-Object Cost -Descending | Select-Object -First 5
            Write-Host "  Top Resources by Cost:" -ForegroundColor Cyan
            foreach ($resource in $topResources) {
                Write-Host "    - $($resource.ResourceType): $($resource.ResourceName) - $($resource.Cost) $($resource.Currency)"
            }
        }
        
        # Grand total
        $grandTotal = ($allResults | Measure-Object -Property Cost -Sum).Sum
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "GRAND TOTAL: $([math]::Round($grandTotal, 2)) $($allResults[0].Currency)" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        
        # Export option
        $export = Read-Host "`nExport detailed results to CSV? (Y/N)"
        if ($export -eq 'Y') {
            $exportPath = Join-Path $PSScriptRoot "CostReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $allResults | Export-Csv -Path $exportPath -NoTypeInformation
            Write-Host "Results exported to: $exportPath" -ForegroundColor Green
        }
    }
    else {
        Write-Host "`nNo cost data found for the selected resource groups in the specified date range." -ForegroundColor Yellow
    }

    Write-Host "`nFunction completed." -ForegroundColor Green
}
