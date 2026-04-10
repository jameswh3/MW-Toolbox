function Get-AzureAgentInventory {
    <#
    .SYNOPSIS
        Retrieves an inventory of agent-related resources from Azure using the Resource Graph REST API.

    .DESCRIPTION
        This function queries the Azure Resource Graph REST API endpoint to discover and inventory
        agent-related resources across your Azure subscriptions. It searches for Bot Service bots,
        Cognitive Services / Azure AI accounts, Health Bots, and Machine Learning workspaces.

        Results can be filtered by resource type and exported to CSV.

        Requires Azure CLI (az) to be installed and authenticated.

    .PARAMETER SubscriptionId
        One or more Azure subscription IDs to query. If not specified, uses the current Azure CLI context.

    .PARAMETER ResourceType
        Filter results to specific agent resource types. Valid values:
        - All (default)
        - BotService
        - CognitiveServices
        - HealthBot
        - MachineLearning

    .PARAMETER OutputPath
        Path to export results as CSV. If not specified, results are returned to the pipeline.

    .EXAMPLE
        Get-AzureAgentInventory
        Queries the current subscription for all agent-related resources.

    .EXAMPLE
        Get-AzureAgentInventory -SubscriptionId "12345678-1234-1234-1234-123456789012"
        Queries a specific subscription.

    .EXAMPLE
        Get-AzureAgentInventory -ResourceType BotService -OutputPath "c:\temp\bot-inventory.csv"
        Queries for Bot Service resources only and exports to CSV.

    .EXAMPLE
        Get-AzureAgentInventory -SubscriptionId @("sub-id-1", "sub-id-2") -ResourceType CognitiveServices
        Queries multiple subscriptions for Cognitive Services resources.

    .NOTES
        Author: James Hammonds
        Requires: Azure CLI (az) authenticated via 'az login'
        API Reference: https://learn.microsoft.com/en-us/rest/api/azureresourcegraph/resourcegraph/resources/resources
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$SubscriptionId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('All', 'BotService', 'CognitiveServices', 'HealthBot', 'MachineLearning')]
        [string]$ResourceType = 'All',

        [Parameter(Mandatory = $false)]
        [string]$OutputPath
    )

    # Verify Azure CLI is available
    try {
        $null = az version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Azure CLI (az) is not installed or not in PATH. Install from https://aka.ms/installazurecli"
            return
        }
    }
    catch {
        Write-Error "Azure CLI (az) is not installed or not in PATH. Install from https://aka.ms/installazurecli"
        return
    }

    # Verify logged in
    $account = az account show 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Not logged in to Azure CLI. Running 'az login'..." -ForegroundColor Yellow
        az login
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to authenticate with Azure CLI."
            return
        }
    }

    # Get subscription ID(s) if not provided
    if (-not $SubscriptionId) {
        $currentSub = az account show --query id --output tsv
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to retrieve current subscription ID."
            return
        }
        $SubscriptionId = @($currentSub)
        Write-Host "Using current subscription: $currentSub" -ForegroundColor Cyan
    }

    # Validate subscription IDs are GUIDs; resolve names to GUIDs if needed
    $guidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    $resolvedSubs = @()
    foreach ($sub in $SubscriptionId) {
        if ($sub -match $guidPattern) {
            $resolvedSubs += $sub
        } else {
            Write-Host "Resolving subscription name '$sub' to GUID..." -ForegroundColor Yellow
            $subId = az account list --query "[?name=='$sub'].id" --output tsv 2>&1
            if ($LASTEXITCODE -ne 0 -or -not $subId) {
                Write-Warning "Could not resolve subscription name '$sub'. Using current context instead."
                $subId = az account show --query id --output tsv
            }
            $resolvedSubs += $subId
            Write-Host "Resolved to: $subId" -ForegroundColor Green
        }
    }
    $SubscriptionId = $resolvedSubs

    # Build resource type filter based on selection
    $typeFilters = switch ($ResourceType) {
        'BotService'        { @("'microsoft.botservice/botservices'") }
        'CognitiveServices' { @("'microsoft.cognitiveservices/accounts'") }
        'HealthBot'         { @("'microsoft.healthbot/healthbots'") }
        'MachineLearning'   { @("'microsoft.machinelearningservices/workspaces'") }
        'All' {
            @(
                "'microsoft.botservice/botservices'",
                "'microsoft.cognitiveservices/accounts'",
                "'microsoft.healthbot/healthbots'",
                "'microsoft.machinelearningservices/workspaces'"
            )
        }
    }

    $typeFilterClause = $typeFilters -join ', '

    # Build the Resource Graph query
    $query = @"
Resources
| where type in~ ($typeFilterClause)
| project
    name,
    type,
    resourceGroup,
    location,
    subscriptionId,
    kind,
    sku = tostring(sku.name),
    provisioningState = tostring(properties.provisioningState),
    tags,
    id
| order by type asc, name asc
"@

    Write-Host "`nQuerying Azure Resource Graph for agent resources..." -ForegroundColor Cyan
    Write-Host "Resource types: $ResourceType" -ForegroundColor Cyan
    Write-Host "Subscriptions: $($SubscriptionId -join ', ')" -ForegroundColor Cyan

    # Build the request body
    $requestBody = @{
        subscriptions = $SubscriptionId
        query         = $query
        options       = @{
            resultFormat = 'objectArray'
        }
    } | ConvertTo-Json -Depth 5 -Compress

    # Write request body to a temp file (az rest requires a file for --body)
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        $requestBody | Out-File -FilePath $tempFile -Encoding utf8 -Force

        # Call the Resource Graph REST API
        $apiUri = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01"
        $response = az rest --method post --uri $apiUri --body `@$tempFile 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Resource Graph query failed: $response"
            return
        }

        $result = $response | ConvertFrom-Json

        if (-not $result.data -or $result.data.Count -eq 0) {
            Write-Host "`nNo agent resources found." -ForegroundColor Yellow
            return
        }

        $resources = $result.data
        $totalCount = $result.totalRecords

        Write-Host "`nFound $totalCount agent resource(s):" -ForegroundColor Green

        # Display summary by type
        $typeSummary = $resources | Group-Object -Property type | Sort-Object Name
        Write-Host "`n--- Summary by Resource Type ---" -ForegroundColor Yellow
        foreach ($group in $typeSummary) {
            Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor White
        }
        Write-Host ""

        # Format and display results
        $formattedResults = $resources | Select-Object `
            name,
            type,
            resourceGroup,
            location,
            kind,
            sku,
            provisioningState,
            subscriptionId,
            @{Name = 'tags'; Expression = {
                if ($_.tags -and $_.tags.PSObject.Properties.Count -gt 0) {
                    ($_.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; '
                } else {
                    ''
                }
            }},
            id

        $formattedResults | Format-Table -Property name, type, resourceGroup, location, kind, sku, provisioningState -AutoSize

        # Export to CSV if path specified
        if ($OutputPath) {
            $outputDir = Split-Path -Path $OutputPath -Parent
            if ($outputDir -and -not (Test-Path $outputDir)) {
                New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            }
            $formattedResults | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            Write-Host "Results exported to: $OutputPath" -ForegroundColor Green
        }

        return $formattedResults
    }
    finally {
        # Clean up temp file
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
    }
}
