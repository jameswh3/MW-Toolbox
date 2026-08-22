function Get-CopilotAgentConsumption {
    <#
    .SYNOPSIS
        Exports agent-level Copilot Credit consumption to CSV.
    .DESCRIPTION
        Uses the documented Power Platform Licensing API to retrieve resource-level
        consumption for the MCSMessages entitlement. Each resource represents an agent.
    .PARAMETER AccessToken
        An access token for https://api.powerplatform.com.
    .PARAMETER TenantId
        The Microsoft Entra tenant ID or verified tenant domain.
    .PARAMETER ClientId
        The application (client) ID used for client credential authentication.
    .PARAMETER ClientSecret
        The application client secret.
    .PARAMETER EntitlementId
        The entitlement to report. MCSMessages represents Copilot Credits.
    .PARAMETER StartDate
        First date included in the report. Defaults to the first day of this month.
    .PARAMETER EndDate
        Last date included in the report. Defaults to today.
    .PARAMETER PageSize
        Number of records requested per page.
    .PARAMETER OutputPath
        CSV output path. Defaults to C:\temp\CopilotAgentConsumption.csv.
    .PARAMETER PassThru
        Returns the report rows after writing the CSV.
    .EXAMPLE
        $token = (Get-AzAccessToken -ResourceUrl 'https://api.powerplatform.com').Token
        Get-CopilotAgentConsumption -AccessToken $token
    #>
    [CmdletBinding(DefaultParameterSetName = 'AccessToken')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'AccessToken')]
        [object]$AccessToken,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$ClientSecret,

        [string]$EntitlementId = 'MCSMessages',

        [datetime]$StartDate = (Get-Date -Day 1),

        [datetime]$EndDate = (Get-Date),

        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000,

        [string]$OutputPath = 'C:\temp\CopilotAgentConsumption.csv',

        [switch]$PassThru
    )

    if ($StartDate.Date -gt $EndDate.Date) {
        throw 'StartDate cannot be later than EndDate.'
    }

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
    elseif ($AccessToken -is [securestring]) {
        $AccessToken = [System.Net.NetworkCredential]::new('', $AccessToken).Password
    }

    $apiVersion = '2024-10-01'
    $baseUri = 'https://api.powerplatform.com/licensing'
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

    $query = "fromDate=$($StartDate.ToString('yyyy-MM-dd'))&toDate=$($EndDate.ToString('yyyy-MM-dd'))&pageSize=$PageSize&api-version=$apiVersion"
    $nextUri = "$baseUri/entitlements/$([uri]::EscapeDataString($EntitlementId))/resources?$query"
    $resources = [System.Collections.Generic.List[object]]::new()
    $requestedUris = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    while ($nextUri) {
        if (-not $requestedUris.Add($nextUri)) {
            throw "Power Platform API returned a repeated pagination URL: $nextUri"
        }

        $response = Invoke-PowerPlatformGet -Uri $nextUri
        if ($null -ne $response.resources) {
            foreach ($resource in @($response.resources)) {
                $resources.Add($resource)
            }
        }
        else {
            foreach ($item in @($response.value)) {
                if ($null -ne $item.resources) {
                    foreach ($resource in @($item.resources)) {
                        $resources.Add($resource)
                    }
                }
                elseif ($null -ne $item.resourceId) {
                    $resources.Add($item)
                }
            }
        }

        $nextUri = $response.'@odata.nextLink'
        if (-not $nextUri) {
            $continuationToken = $response.continuationToken
            if (-not $continuationToken) {
                $continuationToken = $response.continuationtoken
            }
            if ($continuationToken) {
                $nextUri = "$baseUri/entitlements/$([uri]::EscapeDataString($EntitlementId))/resources?$query&continuationToken=$([uri]::EscapeDataString([string]$continuationToken))"
            }
        }
    }

    $retrievedOnUtc = [datetime]::UtcNow.ToString('o')
    $rows = @(
        foreach ($resource in $resources) {
            [pscustomobject]@{
                RetrievedOnUtc      = $retrievedOnUtc
                EntitlementId       = $EntitlementId
                EnvironmentId       = $resource.environmentId
                ResourceId          = $resource.resourceId
                ResourceName        = $resource.metadata.ResourceName
                Consumed            = $resource.consumed
                NonBillableQuantity = $resource.metadata.NonBillableQuantity
                Unit                = $resource.unit
                AsOfDate            = $resource.asOfDate
                LastRefreshedDate    = $resource.lastRefreshedDate
                MetadataJson        = $resource.metadata | ConvertTo-Json -Depth 20 -Compress
            }
        }
    )

    $outputDirectory = Split-Path -Path $OutputPath -Parent
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

    if ($PassThru) {
        return $rows
    }

    Get-Item -Path $OutputPath
}