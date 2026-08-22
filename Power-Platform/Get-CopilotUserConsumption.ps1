function Get-CopilotUserConsumption {
    <#
    .SYNOPSIS
        Exports user-level Copilot Credit consumption to CSV.
    .DESCRIPTION
        Uses the documented Power Platform Licensing API to retrieve user-level
        consumption for the MCSMessages entitlement. The report can optionally be
        scoped to one agent by specifying its resource ID.
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
    .PARAMETER ResourceId
        Optional agent resource ID. When supplied, only users of that agent are returned.
    .PARAMETER StartDate
        First date included in the report. Defaults to the first day of this month.
    .PARAMETER EndDate
        Last date included in the report. Defaults to today.
    .PARAMETER PageSize
        Number of records requested per page.
    .PARAMETER OutputPath
        CSV output path. Defaults to C:\temp\CopilotUserConsumption.csv.
    .PARAMETER PassThru
        Returns the report rows after writing the CSV.
    .EXAMPLE
        $token = (Get-AzAccessToken -ResourceUrl 'https://api.powerplatform.com').Token
        Get-CopilotUserConsumption -AccessToken $token
    .EXAMPLE
        Get-CopilotUserConsumption -AccessToken $token -ResourceId $agentId
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

        [string]$ResourceId,

        [datetime]$StartDate = (Get-Date -Day 1),

        [datetime]$EndDate = (Get-Date),

        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000,

        [string]$OutputPath = 'C:\temp\CopilotUserConsumption.csv',

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

    $escapedEntitlementId = [uri]::EscapeDataString($EntitlementId)
    if ($ResourceId) {
        $relativePath = "entitlements/$escapedEntitlementId/resources/$([uri]::EscapeDataString($ResourceId))/users"
    }
    else {
        $relativePath = "entitlements/$escapedEntitlementId/users"
    }

    $query = "fromDate=$($StartDate.ToString('yyyy-MM-dd'))&toDate=$($EndDate.ToString('yyyy-MM-dd'))&pageSize=$PageSize&api-version=$apiVersion"
    $nextUri = "$baseUri/${relativePath}?$query"
    $users = [System.Collections.Generic.List[object]]::new()
    $requestedUris = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    while ($nextUri) {
        if (-not $requestedUris.Add($nextUri)) {
            throw "Power Platform API returned a repeated pagination URL: $nextUri"
        }

        $response = Invoke-PowerPlatformGet -Uri $nextUri
        if ($null -ne $response.users) {
            foreach ($user in @($response.users)) {
                $users.Add($user)
            }
        }

        $nestedContinuationToken = $null
        foreach ($item in @($response.value)) {
            if ($null -ne $item.users) {
                foreach ($user in @($item.users)) {
                    $users.Add($user)
                }
            }
            elseif ($null -ne $item.userId) {
                $users.Add($item)
            }

            if (-not $nestedContinuationToken) {
                $nestedContinuationToken = $item.continuationToken
                if (-not $nestedContinuationToken) {
                    $nestedContinuationToken = $item.continuationtoken
                }
            }
        }

        $nextUri = $response.'@odata.nextLink'
        if (-not $nextUri) {
            $continuationToken = $response.continuationToken
            if (-not $continuationToken) {
                $continuationToken = $response.continuationtoken
            }
            if (-not $continuationToken) {
                $continuationToken = $nestedContinuationToken
            }
            if ($continuationToken) {
                $nextUri = "$baseUri/${relativePath}?$query&continuationToken=$([uri]::EscapeDataString([string]$continuationToken))"
            }
        }
    }

    $retrievedOnUtc = [datetime]::UtcNow.ToString('o')
    $rows = @(
        foreach ($user in $users) {
            [pscustomobject]@{
                RetrievedOnUtc      = $retrievedOnUtc
                EntitlementId       = $EntitlementId
                ResourceId          = $ResourceId
                TenantId            = $user.tenantId
                EnvironmentId       = $user.environmentId
                UserId              = $user.userId
                Consumed            = $user.consumed
                NonBillableQuantity = $user.metadata.NonBillableQuantity
                ResourceCount       = $user.metadata.Resources
                Unit                = $user.unit
                AsOfDate            = $user.asOfDate
                LastRefreshedDate    = $user.lastRefreshedDate
                MetadataJson        = $user.metadata | ConvertTo-Json -Depth 20 -Compress
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