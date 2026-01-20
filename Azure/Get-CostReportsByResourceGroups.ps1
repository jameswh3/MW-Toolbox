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

    .PARAMETER OutputDirectory
        The directory where the CSV export file will be saved. Default is c:\temp.

    .EXAMPLE
        Get-AzureCostReportsByResourceGroups
        Gets cost reports for the last 7 days with resource group selection prompt.

    .EXAMPLE
        Get-AzureCostReportsByResourceGroups -StartDate "2025-12-01" -EndDate "2025-12-17"
        Gets cost reports for the specified date range.

    .EXAMPLE
        Get-AzureCostReportsByResourceGroups -OutputDirectory "c:\reports"
        Exports results to c:\reports directory.

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
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory = "c:\temp"
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

    # Query costs for all selected resource groups at once using subscription scope
    Write-Host "`nRetrieving cost data for $($selectedGroups.Count) resource group(s)..." -ForegroundColor Cyan
    Write-Host "This may take a moment..." -ForegroundColor Yellow
    
    try {
        # Build the subscription scope for efficient querying
        $scope = "/subscriptions/$SubscriptionId"
        
        # Query cost data using Azure Cost Management at subscription level
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
                        name = "ResourceGroupName"
                    },
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
        
        # Execute single query for all resource groups
        $results = Invoke-AzRestMethod -Path "$scope/providers/Microsoft.CostManagement/query?api-version=2023-03-01" `
            -Method POST `
            -Payload ($costQuery | ConvertTo-Json -Depth 10)
        
        if ($results.StatusCode -eq 200) {
            $costData = ($results.Content | ConvertFrom-Json)
            
            Write-Host "API returned $($costData.properties.rows.Count) rows" -ForegroundColor Gray
            
            if ($costData.properties.rows.Count -gt 0) {
                Write-Host "Processing cost data..." -ForegroundColor Cyan
                
                # Map column names to indices from the API response
                $columns = $costData.properties.columns
                $columnMap = @{}
                for ($i = 0; $i -lt $columns.Count; $i++) {
                    $columnMap[$columns[$i].name] = $i
                }
                
                # Debug: Show column structure
                Write-Host "API Response Columns: $($columns.name -join ', ')" -ForegroundColor Gray
                
                # Create a hashtable of selected resource group names for quick lookup
                $selectedRGNames = @{}
                foreach ($rg in $selectedGroups) {
                    $selectedRGNames[$rg.ResourceGroupName.ToLower()] = $true
                }
                
                Write-Host "Selected resource groups for filtering: $($selectedRGNames.Keys -join ', ')" -ForegroundColor Gray
                
                # Track progress
                $processedCount = 0
                $totalRows = $costData.properties.rows.Count
                $matchedRows = 0
                
                # Sample first row for debugging
                if ($totalRows -gt 0) {
                    $sampleRow = $costData.properties.rows[0]
                    Write-Host "Sample row data:" -ForegroundColor Gray
                    for ($i = 0; $i -lt $columns.Count; $i++) {
                        Write-Host "  $($columns[$i].name): $($sampleRow[$i])" -ForegroundColor Gray
                    }
                }
                
                foreach ($row in $costData.properties.rows) {
                    $cost = [math]::Round($row[$columnMap['Cost']], 2)
                    $currency = $row[$columnMap['Currency']]
                    $usageDate = if ($columnMap.ContainsKey('UsageDate')) { $row[$columnMap['UsageDate']] } else { "N/A" }
                    $resourceGroup = $row[$columnMap['ResourceGroupName']]
                    $resourceType = $row[$columnMap['ResourceType']]
                    $resourceId = $row[$columnMap['ResourceId']]
                    $resourceName = if ($resourceId) { ($resourceId -split '/')[-1] } else { "N/A" }
                    
                    # Only include costs for selected resource groups
                    if ($selectedRGNames.ContainsKey($resourceGroup.ToLower())) {
                        $matchedRows++
                        $allResults += [PSCustomObject]@{
                            Date          = $usageDate
                            ResourceGroup = $resourceGroup
                            ResourceType  = $resourceType
                            ResourceName  = $resourceName
                            ResourceId    = $resourceId
                            Cost          = $cost
                            Currency      = $currency
                        }
                    }
                    
                    # Show progress every 100 rows
                    $processedCount++
                    if ($processedCount % 100 -eq 0) {
                        Write-Progress -Activity "Processing cost data" -Status "$processedCount of $totalRows rows processed" -PercentComplete (($processedCount / $totalRows) * 100)
                    }
                }
                
                Write-Progress -Activity "Processing cost data" -Completed
                Write-Host "Matched $matchedRows rows out of $totalRows total rows" -ForegroundColor Gray
                Write-Host "Successfully retrieved cost data for $($allResults.Count) resources." -ForegroundColor Green
            }
            else {
                Write-Host "No cost data found for the selected resource groups in the specified date range." -ForegroundColor Yellow
            }
        }
        else {
            Write-Warning "Failed to retrieve cost data. Status: $($results.StatusCode)"
            if ($results.Content) {
                Write-Warning "Error details: $($results.Content)"
            }
        }
    }
    catch {
        Write-Error "Error retrieving cost data: $_"
        Write-Error $_.ScriptStackTrace
    }

    # Display summary
    if ($allResults.Count -gt 0) {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "AGGREGATED COST SUMMARY" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        
        # Grand total first
        $grandTotal = ($allResults | Measure-Object -Property Cost -Sum).Sum
        $currency = $allResults[0].Currency
        $dateRange = ($allResults.Date | Select-Object -Unique | Sort-Object)
        $firstDate = $dateRange | Select-Object -First 1
        $lastDate = $dateRange | Select-Object -Last 1
        
        Write-Host "`nGRAND TOTAL: $([math]::Round($grandTotal, 2)) $currency" -ForegroundColor Green -BackgroundColor DarkGray
        Write-Host "Date Range: $firstDate to $lastDate" -ForegroundColor Cyan
        Write-Host "Total Resources: $($allResults.Count)" -ForegroundColor Cyan
        Write-Host "Resource Groups: $($selectedGroups.Count)" -ForegroundColor Cyan
        Write-Host "Days with Charges: $($dateRange.Count)" -ForegroundColor Cyan
        
        # Group by resource group
        Write-Host "`n----------------------------------------" -ForegroundColor Cyan
        Write-Host "BREAKDOWN BY RESOURCE GROUP" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor Cyan
        
        $groupedByRG = $allResults | Group-Object ResourceGroup
        foreach ($group in $groupedByRG | Sort-Object { ($_.Group | Measure-Object -Property Cost -Sum).Sum } -Descending) {
            $rgTotal = ($group.Group | Measure-Object -Property Cost -Sum).Sum
            $rgPercentage = ($rgTotal / $grandTotal) * 100
            
            Write-Host "`nResource Group: $($group.Name)" -ForegroundColor Yellow
            Write-Host "  Total Cost: $([math]::Round($rgTotal, 2)) $currency ($([math]::Round($rgPercentage, 1))% of total)" -ForegroundColor Green
            Write-Host "  Resource Count: $($group.Group.Count)" -ForegroundColor Cyan
            
            # Top 5 most expensive resources
            $topResources = $group.Group | Sort-Object Cost -Descending | Select-Object -First 5
            Write-Host "  Top Resources by Cost:" -ForegroundColor Cyan
            foreach ($resource in $topResources) {
                $resPercentage = ($resource.Cost / $rgTotal) * 100
                Write-Host "    - $($resource.ResourceType): $($resource.ResourceName)" -ForegroundColor White
                Write-Host "      Cost: $($resource.Cost) $currency ($([math]::Round($resPercentage, 1))% of RG)" -ForegroundColor Gray
            }
        }
        
        # Aggregated breakdown by resource type across all selected resource groups
        Write-Host "`n----------------------------------------" -ForegroundColor Cyan
        Write-Host "AGGREGATED BREAKDOWN BY RESOURCE TYPE" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor Cyan
        
        $groupedByType = $allResults | Group-Object ResourceType | 
            Sort-Object { ($_.Group | Measure-Object -Property Cost -Sum).Sum } -Descending | 
            Select-Object -First 10
        
        foreach ($typeGroup in $groupedByType) {
            $typeTotal = ($typeGroup.Group | Measure-Object -Property Cost -Sum).Sum
            $typePercentage = ($typeTotal / $grandTotal) * 100
            $typeCount = $typeGroup.Group.Count
            
            Write-Host "`n$($typeGroup.Name)" -ForegroundColor Yellow
            Write-Host "  Total Cost: $([math]::Round($typeTotal, 2)) $currency ($([math]::Round($typePercentage, 1))% of total)" -ForegroundColor Green
            Write-Host "  Resource Count: $typeCount across $($typeGroup.Group.ResourceGroup | Select-Object -Unique | Measure-Object).Count resource group(s)" -ForegroundColor Cyan
        }
        
        # Daily cost breakdown
        Write-Host "`n----------------------------------------" -ForegroundColor Cyan
        Write-Host "DAILY COST BREAKDOWN" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor Cyan
        
        $groupedByDate = $allResults | Group-Object Date | Sort-Object Name
        foreach ($dateGroup in $groupedByDate) {
            $dailyTotal = ($dateGroup.Group | Measure-Object -Property Cost -Sum).Sum
            $resourceCount = $dateGroup.Group.Count
            Write-Host "$($dateGroup.Name): $([math]::Round($dailyTotal, 2)) $currency ($resourceCount resources)" -ForegroundColor White
        }
        
        Write-Host "`n========================================" -ForegroundColor Cyan
        
        # Export option
        $export = Read-Host "`nExport detailed results to CSV? (Y/N)"
        if ($export -eq 'Y') {
            # Ensure output directory exists
            if (-not (Test-Path $OutputDirectory)) {
                New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
                Write-Host "Created output directory: $OutputDirectory" -ForegroundColor Cyan
            }
            
            $exportPath = Join-Path $OutputDirectory "CostReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $allResults | Export-Csv -Path $exportPath -NoTypeInformation
            Write-Host "Results exported to: $exportPath" -ForegroundColor Green
        }
    }
    else {
        Write-Host "`nNo cost data found for the selected resource groups in the specified date range." -ForegroundColor Yellow
    }

    Write-Host "`nFunction completed." -ForegroundColor Green
}
