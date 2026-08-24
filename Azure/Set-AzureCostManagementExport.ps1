#Requires -Modules Az.Accounts, Az.Resources, Az.Storage

<#
.SYNOPSIS
    Configures a recurring subscription cost export to Azure Blob Storage.

.DESCRIPTION
    Creates or reuses a StorageV2 account and creates or updates a subscription-level
    Azure Cost Management export. The export contains actual costs as partitioned,
    compressed CSV files and overwrites the current reporting period on each run.

.PARAMETER SubscriptionId
    The subscription to report on. Defaults to the subscription in the current Az context.

.PARAMETER ResourceGroupName
    The existing resource group that will contain the storage account.

.PARAMETER Location
    The Azure region for a new storage account and the export managed identity.

.PARAMETER StorageAccountName
    The storage account to create or reuse. When omitted, a deterministic name is generated
    from the subscription ID.

.PARAMETER ContainerName
    The private blob container used by Cost Management. Cost Management creates it if needed.

.PARAMETER RootFolderPath
    The directory path under the container where exported files are stored.

.PARAMETER ExportName
    The name of the subscription-level Cost Management export.

.PARAMETER Recurrence
    Daily exports month-to-date costs. Monthly exports the previous month's costs.

.PARAMETER StartDate
    The UTC schedule start. It must be in the future. Defaults to midnight UTC tomorrow.

.PARAMETER EndDate
    The UTC schedule end. Defaults to ten years after StartDate.

.PARAMETER ProviderRegistrationTimeoutMinutes
    The maximum time to wait for Microsoft.CostManagementExports registration.

.PARAMETER ProviderRegistrationPollIntervalSeconds
    The interval between provider registration status checks.

.PARAMETER RunNow
    Queues the export after it is created or updated.

.EXAMPLE
    .\Set-AzureCostManagementExport.ps1 -ResourceGroupName rg-sharedservices -Location eastus -WhatIf

.EXAMPLE
    .\Set-AzureCostManagementExport.ps1 -SubscriptionId faf3e411-9c6e-4f10-b12b-a1f2f725ac39 `
        -ResourceGroupName rg-sharedservices -Location eastus -RunNow
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string]$SubscriptionId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = 'rg-sharedservices',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Location = 'eastus',

    [Parameter()]
    [string]$StorageAccountName,

    [Parameter()]
    [ValidatePattern('^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$')]
    [string]$ContainerName = 'cost-exports',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RootFolderPath = 'subscription-costs',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ExportName = 'subscription-actual-costs',

    [Parameter()]
    [ValidateSet('Daily', 'Monthly')]
    [string]$Recurrence = 'Daily',

    [Parameter()]
    [datetime]$StartDate = [datetime]::UtcNow.Date.AddDays(1),

    [Parameter()]
    [Nullable[datetime]]$EndDate,

    [Parameter()]
    [ValidateRange(1, 60)]
    [int]$ProviderRegistrationTimeoutMinutes = 10,

    [Parameter()]
    [ValidateRange(1, 60)]
    [int]$ProviderRegistrationPollIntervalSeconds = 15,

    [Parameter()]
    [switch]$RunNow
)

$ErrorActionPreference = 'Stop'
$costManagementApiVersion = '2025-03-01'

$context = Get-AzContext
if (-not $context) {
    throw 'No Azure context is available. Run Connect-AzAccount and select a subscription first.'
}

if (-not $SubscriptionId) {
    $SubscriptionId = $context.Subscription.Id
}

if ($context.Subscription.Id -ne $SubscriptionId) {
    $context = Set-AzContext -SubscriptionId $SubscriptionId
}

$resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $resourceGroup) {
    throw "Resource group '$ResourceGroupName' was not found in subscription '$SubscriptionId'."
}

if (-not $PSBoundParameters.ContainsKey('Location')) {
    $Location = $resourceGroup.Location
}

if (-not $StorageAccountName) {
    $subscriptionToken = $SubscriptionId.Replace('-', '').ToLowerInvariant()
    $StorageAccountName = "cmexp$($subscriptionToken.Substring(0, 19))"
}

if ($StorageAccountName -notmatch '^[a-z0-9]{3,24}$') {
    throw 'StorageAccountName must contain 3-24 lowercase letters or numbers.'
}

$scheduleStart = $StartDate.ToUniversalTime()
if ($scheduleStart -le [datetime]::UtcNow) {
    throw 'StartDate must be in the future.'
}

$scheduleEnd = if ($EndDate.HasValue) { $EndDate.Value.ToUniversalTime() } else { $scheduleStart.AddYears(10) }
if ($scheduleEnd -le $scheduleStart) {
    throw 'EndDate must be later than StartDate.'
}

$provider = Get-AzResourceProvider -ProviderNamespace Microsoft.CostManagementExports
if ($provider.RegistrationState -ne 'Registered') {
    if ($PSCmdlet.ShouldProcess('Microsoft.CostManagementExports', "Register provider in subscription '$SubscriptionId' and wait for completion")) {
        if ($provider.RegistrationState -ne 'Registering') {
            Register-AzResourceProvider -ProviderNamespace Microsoft.CostManagementExports | Out-Null
        }

        $registrationDeadline = [datetime]::UtcNow.AddMinutes($ProviderRegistrationTimeoutMinutes)
        while ($provider.RegistrationState -ne 'Registered') {
            if ([datetime]::UtcNow -ge $registrationDeadline) {
                throw "Microsoft.CostManagementExports registration did not complete within $ProviderRegistrationTimeoutMinutes minute(s). Current state: $($provider.RegistrationState)."
            }

            Write-Verbose "Microsoft.CostManagementExports registration state: $($provider.RegistrationState)."
            Start-Sleep -Seconds $ProviderRegistrationPollIntervalSeconds
            $provider = Get-AzResourceProvider -ProviderNamespace Microsoft.CostManagementExports
        }
    }
}

$storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (-not $storageAccount) {
    $availabilityPayload = @{ name = $StorageAccountName; type = 'Microsoft.Storage/storageAccounts' } | ConvertTo-Json
    $availabilityResponse = Invoke-AzRestMethod `
        -Path "/subscriptions/$SubscriptionId/providers/Microsoft.Storage/checkNameAvailability?api-version=2023-01-01" `
        -Method POST `
        -Payload $availabilityPayload `
        -WhatIf:$false
    $availability = $availabilityResponse.Content | ConvertFrom-Json

    if (-not $availability.nameAvailable) {
        throw "Storage account name '$StorageAccountName' is unavailable: $($availability.message)"
    }

    if ($PSCmdlet.ShouldProcess($StorageAccountName, "Create StorageV2 account in '$ResourceGroupName'")) {
        $storageAccount = New-AzStorageAccount `
            -ResourceGroupName $ResourceGroupName `
            -Name $StorageAccountName `
            -Location $Location `
            -SkuName Standard_LRS `
            -Kind StorageV2 `
            -AccessTier Hot `
            -EnableHttpsTrafficOnly $true `
            -MinimumTlsVersion TLS1_2 `
            -AllowBlobPublicAccess $false `
            -AllowCrossTenantReplication $false `
            -AllowedCopyScope All
    }
}

$storageResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
if ($storageAccount) {
    $storageResourceId = $storageAccount.Id
}

$escapedExportName = [uri]::EscapeDataString($ExportName)
$exportPath = "/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/exports/$escapedExportName"
$existingResponse = Invoke-AzRestMethod `
    -Path "${exportPath}?api-version=$costManagementApiVersion" `
    -Method GET `
    -WhatIf:$false
$existingExport = if ($existingResponse.StatusCode -eq 200) {
    $existingResponse.Content | ConvertFrom-Json
}
elseif ($existingResponse.StatusCode -ne 404) {
    throw "Unable to inspect export '$ExportName'. Azure returned HTTP $($existingResponse.StatusCode): $($existingResponse.Content)"
}

$timeframe = if ($Recurrence -eq 'Daily') { 'MonthToDate' } else { 'TheLastMonth' }
$exportBody = @{
    identity   = @{ type = 'SystemAssigned' }
    location   = $Location
    properties = @{
        format                 = 'Csv'
        compressionMode        = 'gzip'
        dataOverwriteBehavior  = 'OverwritePreviousReport'
        partitionData          = $true
        exportDescription      = 'Recurring subscription actual cost and usage export.'
        definition             = @{
            type      = 'ActualCost'
            timeframe = $timeframe
            dataSet   = @{ granularity = 'Daily' }
        }
        deliveryInfo          = @{
            destination = @{
                type           = 'AzureBlob'
                resourceId     = $storageResourceId
                container      = $ContainerName
                rootFolderPath = $RootFolderPath
            }
        }
        schedule              = @{
            status           = 'Active'
            recurrence       = $Recurrence
            recurrencePeriod = @{
                from = $scheduleStart.ToString('o')
                to   = $scheduleEnd.ToString('o')
            }
        }
    }
}

if ($existingExport) {
    $exportBody.eTag = $existingExport.eTag
}

$action = if ($existingExport) { 'Update' } else { 'Create' }
if ($PSCmdlet.ShouldProcess($ExportName, "$action Cost Management export for subscription '$SubscriptionId'")) {
    $exportResponse = Invoke-AzRestMethod `
        -Path "${exportPath}?api-version=$costManagementApiVersion" `
        -Method PUT `
        -Payload ($exportBody | ConvertTo-Json -Depth 10)

    if ($exportResponse.StatusCode -notin 200, 201) {
        throw "Failed to configure export '$ExportName'. Azure returned HTTP $($exportResponse.StatusCode): $($exportResponse.Content)"
    }

    $configuredExport = $exportResponse.Content | ConvertFrom-Json

    if ($RunNow -and $PSCmdlet.ShouldProcess($ExportName, 'Queue an immediate export run')) {
        $runResponse = Invoke-AzRestMethod `
            -Path "$exportPath/run?api-version=$costManagementApiVersion" `
            -Method POST
        if ($runResponse.StatusCode -ne 200) {
            throw "Export was configured, but RunNow failed with HTTP $($runResponse.StatusCode): $($runResponse.Content)"
        }
    }

    [PSCustomObject]@{
        SubscriptionId     = $SubscriptionId
        ResourceGroupName  = $ResourceGroupName
        StorageAccountName = $StorageAccountName
        ContainerName      = $ContainerName
        RootFolderPath     = $RootFolderPath
        ExportName         = $ExportName
        Recurrence         = $Recurrence
        Timeframe          = $timeframe
        ScheduleStatus     = $configuredExport.properties.schedule.status
        NextRunTime        = $configuredExport.properties.nextRunTimeEstimate
        RunQueued          = [bool]$RunNow
    }
}