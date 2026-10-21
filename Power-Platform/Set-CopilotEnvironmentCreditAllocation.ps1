function Set-CopilotEnvironmentCreditAllocation {
    <#
    .SYNOPSIS
        Sets the Copilot Credit allocation and tenant-capacity overage behavior for an environment.
    .DESCRIPTION
        Uses the documented Power Platform Licensing API to allocate MCSMessages
        (Copilot Credits) to an environment. The command also controls the TenantPool
        enforcement rule, which maps to "Draw from the available capacity in my tenant"
        in the Power Platform admin center.
    .PARAMETER AccessToken
        An access token for https://api.powerplatform.com.
    .PARAMETER TenantId
        The Microsoft Entra tenant ID or verified tenant domain.
    .PARAMETER ClientId
        The application (client) ID used for client credential authentication.
    .PARAMETER ClientSecret
        The application client secret.
    .PARAMETER EnvironmentId
        The Power Platform environment ID.
    .PARAMETER CreditAllocation
        The number of Copilot Credits to allocate to the environment.
    .PARAMETER DrawFromTenantCapacity
        Whether the environment can consume unallocated tenant capacity after its
        allocated credits are exhausted. Defaults to false.
    .EXAMPLE
        $token = (Get-AzAccessToken -ResourceUrl 'https://api.powerplatform.com').Token
        Set-CopilotEnvironmentCreditAllocation -AccessToken $token `
            -EnvironmentId $environmentId -CreditAllocation 5000
    .EXAMPLE
        Set-CopilotEnvironmentCreditAllocation -AccessToken $token `
            -EnvironmentId $environmentId -CreditAllocation 5000 `
            -DrawFromTenantCapacity $false -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'AccessToken')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'AccessToken')]
        [object]$AccessToken,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$ClientSecret,

        [Parameter(Mandatory = $true)]
        [guid]$EnvironmentId,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 2147483647)]
        [int]$CreditAllocation,

        [bool]$DrawFromTenantCapacity = $false
    )

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
    $allocationUri = "https://api.powerplatform.com/licensing/allocationsV2?api-version=$apiVersion"
    $headers = @{ Authorization = "Bearer $AccessToken" }
    $request = @{
        scope                 = @{
            environmentId = $EnvironmentId.ToString()
        }
        allocatedEntitlements = @(
            @{
                entitlementId    = 'MCSMessages'
                allocation       = @{
                    quantity = $CreditAllocation
                }
                enforcementRules = @(
                    @{
                        ruleType = 'TenantPool'
                        enabled  = $DrawFromTenantCapacity
                    }
                )
            }
        )
    }

    $tenantCapacityBehavior = if ($DrawFromTenantCapacity) {
        'allow tenant capacity overage'
    }
    else {
        'disable tenant capacity overage'
    }
    $target = "environment $EnvironmentId"
    $action = "Allocate $CreditAllocation Copilot Credits and $tenantCapacityBehavior"

    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        return [pscustomobject]@{
            EnvironmentId          = $EnvironmentId
            CreditAllocation       = $CreditAllocation
            DrawFromTenantCapacity = $DrawFromTenantCapacity
            Applied                = $false
        }
    }

    try {
        $response = Invoke-RestMethod `
            -Method Put `
            -Uri $allocationUri `
            -Headers $headers `
            -ContentType 'application/json' `
            -Body ($request | ConvertTo-Json -Depth 10)
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $detail = $_.ErrorDetails.Message
        if (-not $detail) {
            $detail = $_.Exception.Message
        }
        throw "Power Platform API request failed ($statusCode): PUT $allocationUri`n$detail"
    }

    [pscustomobject]@{
        EnvironmentId          = $EnvironmentId
        CreditAllocation       = $CreditAllocation
        DrawFromTenantCapacity = $DrawFromTenantCapacity
        Applied                = $true
        Response               = $response
    }
}
