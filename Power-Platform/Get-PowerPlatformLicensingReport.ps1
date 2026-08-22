function Get-PowerPlatformLicensingReport {
    <#
    .SYNOPSIS
        Retrieves Copilot credit usage and Power Platform billing configuration.
    .DESCRIPTION
        Uses the documented Power Platform Licensing API (2024-10-01) to retrieve:
          - Tenant Copilot credit capacity and month-to-date consumption
          - Copilot credit allocations and enforcement rules by environment
          - Billing policies and their linked environments

        The MCSMessages currency type represents Copilot Studio messages/Copilot Credits.

        Required delegated permission: Licensing.Allocations.Read and
        Licensing.BillingPolicies.Read. For service principal authentication, assign an
        appropriate Power Platform RBAC role to the service principal.

        API reference: https://learn.microsoft.com/rest/api/power-platform/
    .PARAMETER AccessToken
        An access token for https://api.powerplatform.com. This is useful with:
        (Get-AzAccessToken -ResourceUrl 'https://api.powerplatform.com').Token
    .PARAMETER TenantId
        The Microsoft Entra tenant ID or verified tenant domain.
    .PARAMETER ClientId
        The application (client) ID used for client credential authentication.
    .PARAMETER ClientSecret
        The application client secret.
    .PARAMETER OutputPath
        CSV output path. Defaults to C:\temp\PowerPlatformLicensingReport.csv.
    .PARAMETER PassThru
        Returns the structured report object instead of the CSV file information.
    .EXAMPLE
        $token = (Get-AzAccessToken -ResourceUrl 'https://api.powerplatform.com').Token
        Get-PowerPlatformLicensingReport -AccessToken $token
    .EXAMPLE
        Get-PowerPlatformLicensingReport -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret
    #>
    [CmdletBinding(DefaultParameterSetName = 'AccessToken')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'AccessToken')]
        [string]$AccessToken,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$ClientSecret,

        [string]$OutputPath = 'C:\temp\PowerPlatformLicensingReport.csv',

        [switch]$PassThru
    )

    $apiVersion = '2024-10-01'
    $baseUri = 'https://api.powerplatform.com/licensing'

    if ($PSCmdlet.ParameterSetName -eq 'ClientCredential') {
        $tokenResponse = Invoke-RestMethod `
            -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{
                client_id     = $ClientId
                client_secret = $ClientSecret
                grant_type    = 'client_credentials'
                scope         = 'https://api.powerplatform.com/.default'
            }
        $AccessToken = $tokenResponse.access_token
    }

    $headers = @{ Authorization = "Bearer $AccessToken" }

    function Invoke-PowerPlatformGet {
        param ([Parameter(Mandatory = $true)][string]$Uri)

        try {
            Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers -ContentType 'application/json'
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $detail = $_.ErrorDetails.Message
            if (-not $detail) {
                $detail = $_.Exception.Message
            }
            throw "Power Platform API request failed ($statusCode): $Uri`n$detail"
        }
    }

    $currencyReportsUri = "$baseUri/tenantCapacity/currencyReports?includeAllocations=true&includeConsumptions=true&api-version=$apiVersion"
    $currencyReportsResponse = Invoke-PowerPlatformGet -Uri $currencyReportsUri
    $currencyReports = @($currencyReportsResponse)
    $copilotCredits = @($currencyReports | Where-Object { $_.currencyType -eq 'MCSMessages' })

    $allocationsUri = "$baseUri/allocationsByEnvironment?api-version=$apiVersion"
    $allocationsResponse = Invoke-PowerPlatformGet -Uri $allocationsUri
    $allAllocations = @($allocationsResponse)
    $copilotAllocations = foreach ($environment in $allAllocations) {
        foreach ($allocation in @($environment.currencyAllocations)) {
            if ($allocation.currencyType -eq 'MCSMessages') {
                [pscustomobject]@{
                    EnvironmentId   = $environment.environmentId
                    Allocated       = $allocation.allocated
                    AutoAllocated   = $allocation.autoAllocated
                    EnforcementRules = $allocation.enforcementRules
                }
            }
        }
    }

    $billingPolicies = @()
    $nextLink = "$baseUri/billingPolicies?api-version=$apiVersion"
    while ($nextLink) {
        $response = Invoke-PowerPlatformGet -Uri $nextLink
        foreach ($policy in @($response.value)) {
            $environmentLinks = @()
            $environmentNextLink = "$baseUri/billingPolicies/$($policy.id)/environments?api-version=$apiVersion"
            while ($environmentNextLink) {
                $environmentResponse = Invoke-PowerPlatformGet -Uri $environmentNextLink
                $environmentLinks += @($environmentResponse.value)
                $environmentNextLink = $environmentResponse.'@odata.nextLink'
            }

            $billingPolicies += [pscustomobject]@{
                Id                 = $policy.id
                Name               = $policy.name
                Status             = $policy.status
                Location           = $policy.location
                BillingInstrument  = $policy.billingInstrument
                LinkedEnvironments = @($environmentLinks | ForEach-Object { $_.environmentId })
                CreatedOn          = $policy.createdOn
                LastModifiedOn     = $policy.lastModifiedOn
            }
        }
        $nextLink = $response.'@odata.nextLink'
    }

    $report = [pscustomobject]@{
        RetrievedOnUtc              = [datetime]::UtcNow
        CopilotCredits              = $copilotCredits
        CopilotAllocations          = @($copilotAllocations)
        BillingPolicies             = $billingPolicies
        AllTenantCurrencyReports    = $currencyReports
        AllEnvironmentAllocations   = $allAllocations
    }

    $csvRows = @(
        foreach ($credit in $copilotCredits) {
            [pscustomobject]@{
                RecordType          = 'CopilotCredit'
                RetrievedOnUtc       = $report.RetrievedOnUtc.ToString('o')
                CurrencyType         = $credit.currencyType
                Purchased            = $credit.purchased
                Allocated            = $credit.allocated
                Consumed             = $credit.consumed.unitsConsumed
                LastUpdated          = $credit.consumed.lastUpdatedDay
                EnvironmentId        = $null
                AutoAllocated        = $null
                EnforcementRules     = $null
                BillingPolicyId      = $null
                BillingPolicyName    = $null
                Status               = $null
                Location             = $null
                SubscriptionId       = $null
                ResourceGroup        = $null
                BillingInstrumentId  = $null
                LinkedEnvironments   = $null
                CreatedOn            = $null
                LastModifiedOn       = $null
            }
        }

        foreach ($allocation in @($copilotAllocations)) {
            $rules = @($allocation.EnforcementRules | ForEach-Object { "$($_.ruleType)=$($_.enabled)" }) -join ';'
            [pscustomobject]@{
                RecordType          = 'CopilotAllocation'
                RetrievedOnUtc       = $report.RetrievedOnUtc.ToString('o')
                CurrencyType         = 'MCSMessages'
                Purchased            = $null
                Allocated            = $allocation.Allocated
                Consumed             = $null
                LastUpdated          = $null
                EnvironmentId        = $allocation.EnvironmentId
                AutoAllocated        = $allocation.AutoAllocated
                EnforcementRules     = $rules
                BillingPolicyId      = $null
                BillingPolicyName    = $null
                Status               = $null
                Location             = $null
                SubscriptionId       = $null
                ResourceGroup        = $null
                BillingInstrumentId  = $null
                LinkedEnvironments   = $null
                CreatedOn            = $null
                LastModifiedOn       = $null
            }
        }

        foreach ($policy in $billingPolicies) {
            [pscustomobject]@{
                RecordType          = 'BillingPolicy'
                RetrievedOnUtc       = $report.RetrievedOnUtc.ToString('o')
                CurrencyType         = $null
                Purchased            = $null
                Allocated            = $null
                Consumed             = $null
                LastUpdated          = $null
                EnvironmentId        = $null
                AutoAllocated        = $null
                EnforcementRules     = $null
                BillingPolicyId      = $policy.Id
                BillingPolicyName    = $policy.Name
                Status               = $policy.Status
                Location             = $policy.Location
                SubscriptionId       = $policy.BillingInstrument.subscriptionId
                ResourceGroup        = $policy.BillingInstrument.resourceGroup
                BillingInstrumentId  = $policy.BillingInstrument.id
                LinkedEnvironments   = @($policy.LinkedEnvironments) -join ';'
                CreatedOn            = $policy.CreatedOn
                LastModifiedOn       = $policy.LastModifiedOn
            }
        }
    )

    $outputDirectory = Split-Path -Path $OutputPath -Parent
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    $csvRows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

    if ($PassThru) {
        return $report
    }

    Get-Item -Path $OutputPath
}