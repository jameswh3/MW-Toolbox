function Set-CopilotAgentConsumptionLimit {
    <#
    .SYNOPSIS
        Sets the monthly Copilot Credit limit for an individual Copilot Studio agent.
    .DESCRIPTION
        Uses the documented Power Platform Licensing API to create or update the
        MCSMessages resource threshold for a Copilot Studio agent. The command can
        enable notifications, enforce a hard stop at the limit, or explicitly
        disable the agent.
    .PARAMETER AccessToken
        An access token for https://api.powerplatform.com.
    .PARAMETER TenantId
        The Microsoft Entra tenant ID or verified tenant domain.
    .PARAMETER ClientId
        The application (client) ID used for client credential authentication.
    .PARAMETER ClientSecret
        The application client secret.
    .PARAMETER EnvironmentId
        The Power Platform environment ID containing the agent.
    .PARAMETER AgentId
        The Copilot Studio agent resource ID.
    .PARAMETER MonthlyLimit
        The maximum number of Copilot Credits the agent can consume each month.
    .PARAMETER NotificationsEnabled
        Whether administrators are notified as consumption approaches the limit.
    .PARAMETER NotificationThreshold
        The percentage of the monthly limit that triggers a notification.
    .PARAMETER HardStopEnabled
        Whether the agent is automatically stopped when it reaches the limit.
    .PARAMETER AgentDisabled
        Whether the agent should be explicitly disabled immediately.
    .EXAMPLE
        $token = (Get-AzAccessToken -ResourceUrl 'https://api.powerplatform.com').Token
        Set-CopilotAgentConsumptionLimit -AccessToken $token `
            -EnvironmentId $environmentId -AgentId $agentId -MonthlyLimit 25000 `
            -HardStopEnabled $true
    .EXAMPLE
        Set-CopilotAgentConsumptionLimit -AccessToken $token `
            -EnvironmentId $environmentId -AgentId $agentId -MonthlyLimit 10000 `
            -WhatIf
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
        [Alias('ResourceId')]
        [guid]$AgentId,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 2147483647)]
        [int]$MonthlyLimit,

        [bool]$NotificationsEnabled = $true,

        [ValidateRange(1, 100)]
        [int]$NotificationThreshold = 80,

        [bool]$HardStopEnabled = $false,

        [bool]$AgentDisabled = $false
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
    $baseUri = 'https://api.powerplatform.com/licensing'
    $entitlementId = 'MCSMessages'
    $headers = @{ Authorization = "Bearer $AccessToken" }

    function Invoke-PowerPlatformRequest {
        param (
            [Parameter(Mandatory = $true)][ValidateSet('Get', 'Put')][string]$Method,
            [Parameter(Mandatory = $true)][string]$Uri,
            [string]$Body
        )

        try {
            $parameters = @{
                Method      = $Method
                Uri         = $Uri
                Headers     = $headers
                ContentType = 'application/json'
            }
            if ($Body) {
                $parameters.Body = $Body
            }
            Invoke-RestMethod @parameters -WhatIf:$false
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $detail = $_.ErrorDetails.Message
            if (-not $detail) {
                $detail = $_.Exception.Message
            }
            throw "Power Platform API request failed ($statusCode): $Method $Uri`n$detail"
        }
    }

    $thresholdsUri = "$baseUri/entitlements/$entitlementId/resourceThresholds?api-version=$apiVersion"
    $thresholds = @(Invoke-PowerPlatformRequest -Method Get -Uri $thresholdsUri)
    $currentThreshold = $thresholds | Where-Object {
        $_.environmentId -eq $EnvironmentId.ToString() -and $_.resourceId -eq $AgentId.ToString()
    } | Select-Object -First 1

    $request = [ordered]@{
        stopResource          = $AgentDisabled
        limit                 = $MonthlyLimit
        stopIfOverCapacity    = $HardStopEnabled
        notifyIfOverCapacity  = $NotificationsEnabled
        notificationThreshold = $NotificationThreshold
    }
    $target = "agent $AgentId in environment $EnvironmentId"
    $action = "Set monthly Copilot Credit limit to $MonthlyLimit"

    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        return [pscustomobject]@{
            EnvironmentId                  = $EnvironmentId
            AgentId                        = $AgentId
            PreviousMonthlyLimit            = $currentThreshold.limit
            PreviousNotificationsEnabled    = $currentThreshold.notifyIfOverCapacity
            PreviousNotificationThreshold   = $currentThreshold.notificationThreshold
            PreviousHardStopEnabled         = $currentThreshold.stopIfOverCapacity
            PreviousAgentDisabled           = $currentThreshold.stopResource
            RequestedMonthlyLimit            = $MonthlyLimit
            RequestedNotificationsEnabled    = $NotificationsEnabled
            RequestedNotificationThreshold   = $NotificationThreshold
            RequestedHardStopEnabled         = $HardStopEnabled
            RequestedAgentDisabled           = $AgentDisabled
            Applied                          = $false
        }
    }

    $environmentPath = [uri]::EscapeDataString($EnvironmentId.ToString())
    $resourcePath = [uri]::EscapeDataString($AgentId.ToString())
    $thresholdUri = "$baseUri/environments/$environmentPath/entitlements/$entitlementId/resources/$resourcePath/threshold?api-version=$apiVersion"
    $updatedThreshold = Invoke-PowerPlatformRequest `
        -Method Put `
        -Uri $thresholdUri `
        -Body ($request | ConvertTo-Json -Depth 5)

    [pscustomobject]@{
        EnvironmentId                  = $updatedThreshold.environmentId
        AgentId                        = $updatedThreshold.resourceId
        PreviousMonthlyLimit            = $currentThreshold.limit
        PreviousNotificationsEnabled    = $currentThreshold.notifyIfOverCapacity
        PreviousNotificationThreshold   = $currentThreshold.notificationThreshold
        PreviousHardStopEnabled         = $currentThreshold.stopIfOverCapacity
        PreviousAgentDisabled           = $currentThreshold.stopResource
        MonthlyLimit                    = $updatedThreshold.limit
        NotificationsEnabled            = $updatedThreshold.notifyIfOverCapacity
        NotificationThreshold           = $updatedThreshold.notificationThreshold
        HardStopEnabled                 = $updatedThreshold.stopIfOverCapacity
        AgentDisabled                   = $updatedThreshold.stopResource
        CurrentConsumption              = $updatedThreshold.resourceConsumption
        CreatedOn                       = $updatedThreshold.createdOn
        Applied                         = $true
    }
}