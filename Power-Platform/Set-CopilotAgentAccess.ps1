function Set-CopilotAgentAccess {
    <#
    .SYNOPSIS
        Grants or revokes supported Copilot Studio agent access from a CSV file.
    .DESCRIPTION
        Uses the documented Microsoft Dataverse GrantAccess, ModifyAccess, and
        RevokeAccess operations on Copilot Studio bot records. Chat and Coauthor
        access are supported. AnalyticsViewer and EvaluationViewer are reported as
        unsupported because Microsoft doesn't expose a public assignment API for them.

        CSV columns:
          EnvironmentUrl - Dataverse URL, for example https://contoso.crm.dynamics.com
          AgentId        - Copilot Studio bot ID
          PrincipalType  - User, Team, or Organization
          Principal      - User UPN/Entra object ID, team Entra object ID, or blank
          AccessRole     - Chat, Coauthor, AnalyticsViewer, or EvaluationViewer
          Action         - Grant or Revoke

        Coauthors must already have the Environment Maker security role in the
        environment. Revoke removes all direct sharing rights for that principal on
        the agent because Dataverse stores one combined access mask per share.
    .PARAMETER CsvPath
        Path to the access request CSV file.
    .PARAMETER TenantId
        Microsoft Entra tenant ID used for client credential authentication.
    .PARAMETER ClientId
        Application client ID used for client credential authentication.
    .PARAMETER ClientSecret
        Application client secret used for client credential authentication.
    .PARAMETER OutputPath
        Result CSV path. Defaults to C:\temp\CopilotAgentAccessResults.csv.
    .EXAMPLE
        Set-CopilotAgentAccess -CsvPath C:\temp\CopilotAgentAccess.csv -WhatIf
    .EXAMPLE
        Set-CopilotAgentAccess -CsvPath C:\temp\CopilotAgentAccess.csv
    .EXAMPLE
        Set-CopilotAgentAccess -CsvPath C:\temp\CopilotAgentAccess.csv `
            -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'AzContext')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$CsvPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$ClientSecret,

        [string]$OutputPath = 'C:\temp\CopilotAgentAccessResults.csv'
    )

    $requiredColumns = @('EnvironmentUrl', 'AgentId', 'PrincipalType', 'Principal', 'AccessRole', 'Action')
    $requests = @(Import-Csv -LiteralPath $CsvPath)
    if ($requests.Count -eq 0) {
        throw "The CSV file contains no access requests: $CsvPath"
    }

    $actualColumns = @($requests[0].PSObject.Properties.Name)
    $missingColumns = @($requiredColumns | Where-Object { $_ -notin $actualColumns })
    if ($missingColumns.Count -gt 0) {
        throw "The CSV file is missing required columns: $($missingColumns -join ', ')"
    }

    $tokenCache = @{}

    function Get-DataverseAccessToken {
        param ([Parameter(Mandatory = $true)][string]$EnvironmentUrl)

        if ($tokenCache.ContainsKey($EnvironmentUrl)) {
            return $tokenCache[$EnvironmentUrl]
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
                    scope         = "$EnvironmentUrl/.default"
                }
            $token = $tokenResponse.access_token
        }
        else {
            if (-not (Get-Command Get-AzAccessToken -ErrorAction SilentlyContinue)) {
                throw 'Get-AzAccessToken is unavailable. Install Az.Accounts or use client credential parameters.'
            }

            $tokenResponse = Get-AzAccessToken -ResourceUrl $EnvironmentUrl
            $token = if ($tokenResponse.Token -is [securestring]) {
                [System.Net.NetworkCredential]::new('', $tokenResponse.Token).Password
            }
            else {
                $tokenResponse.Token
            }
        }

        $tokenCache[$EnvironmentUrl] = $token
        return $token
    }

    function Invoke-DataverseRequest {
        param (
            [Parameter(Mandatory = $true)][string]$EnvironmentUrl,
            [Parameter(Mandatory = $true)][string]$Method,
            [Parameter(Mandatory = $true)][string]$RelativeUri,
            [object]$Body
        )

        $token = Get-DataverseAccessToken -EnvironmentUrl $EnvironmentUrl
        $parameters = @{
            Method      = $Method
            Uri         = "$EnvironmentUrl/api/data/v9.2/$RelativeUri"
            Headers     = @{
                Authorization    = "Bearer $token"
                Accept           = 'application/json'
                'OData-MaxVersion' = '4.0'
                'OData-Version'  = '4.0'
            }
            ContentType = 'application/json; charset=utf-8'
        }
        if ($null -ne $Body) {
            $parameters.Body = $Body | ConvertTo-Json -Depth 10 -Compress
        }

        try {
            Invoke-RestMethod @parameters
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $detail = $_.ErrorDetails.Message
            if (-not $detail) {
                $detail = $_.Exception.Message
            }
            throw "Dataverse request failed ($statusCode): $($parameters.Uri)`n$detail"
        }
    }

    function Get-SingleDataverseRow {
        param (
            [Parameter(Mandatory = $true)][string]$EnvironmentUrl,
            [Parameter(Mandatory = $true)][string]$RelativeUri,
            [Parameter(Mandatory = $true)][string]$Description
        )

        $response = Invoke-DataverseRequest -EnvironmentUrl $EnvironmentUrl -Method Get -RelativeUri $RelativeUri
        $matches = @($response.value)
        if ($matches.Count -eq 0) {
            throw "$Description wasn't found."
        }
        if ($matches.Count -gt 1) {
            throw "$Description matched more than one Dataverse row. Use an object ID instead."
        }
        return $matches[0]
    }

    function Resolve-Principal {
        param (
            [Parameter(Mandatory = $true)][string]$EnvironmentUrl,
            [Parameter(Mandatory = $true)][string]$PrincipalType,
            [AllowEmptyString()][string]$Principal
        )

        switch ($PrincipalType.ToLowerInvariant()) {
            'user' {
                if ([string]::IsNullOrWhiteSpace($Principal)) {
                    throw 'Principal is required when PrincipalType is User.'
                }

                $guid = [guid]::Empty
                if ([guid]::TryParse($Principal, [ref]$guid)) {
                    $relativeUri = "systemusers?`$select=systemuserid,fullname,internalemailaddress,azureactivedirectoryobjectid&`$filter=azureactivedirectoryobjectid eq $guid&`$top=2"
                }
                else {
                    $escapedPrincipal = $Principal.Replace("'", "''")
                    $relativeUri = "systemusers?`$select=systemuserid,fullname,internalemailaddress,azureactivedirectoryobjectid&`$filter=internalemailaddress eq '$escapedPrincipal'&`$top=2"
                }

                $row = Get-SingleDataverseRow -EnvironmentUrl $EnvironmentUrl -RelativeUri $relativeUri -Description "User '$Principal'"
                return [pscustomobject]@{
                    Type        = 'User'
                    ODataType   = 'Microsoft.Dynamics.CRM.systemuser'
                    Id          = $row.systemuserid
                    DisplayName = $row.fullname
                }
            }
            'team' {
                $guid = [guid]::Empty
                if (-not [guid]::TryParse($Principal, [ref]$guid)) {
                    throw 'Team Principal must be the Microsoft Entra security group object ID.'
                }

                $relativeUri = "teams?`$select=teamid,name,azureactivedirectoryobjectid&`$filter=azureactivedirectoryobjectid eq $guid&`$top=2"
                $row = Get-SingleDataverseRow -EnvironmentUrl $EnvironmentUrl -RelativeUri $relativeUri -Description "Entra-backed team '$Principal'"
                return [pscustomobject]@{
                    Type        = 'Team'
                    ODataType   = 'Microsoft.Dynamics.CRM.team'
                    Id          = $row.teamid
                    DisplayName = $row.name
                }
            }
            'organization' {
                $row = Get-SingleDataverseRow -EnvironmentUrl $EnvironmentUrl -RelativeUri 'organizations?$select=organizationid,friendlyname&$top=2' -Description 'Organization principal'
                return [pscustomobject]@{
                    Type        = 'Organization'
                    ODataType   = 'Microsoft.Dynamics.CRM.organization'
                    Id          = $row.organizationid
                    DisplayName = $row.friendlyname
                }
            }
            default {
                throw "Unsupported PrincipalType '$PrincipalType'. Use User, Team, or Organization."
            }
        }
    }

    function Get-DirectAgentShares {
        param (
            [Parameter(Mandatory = $true)][string]$EnvironmentUrl,
            [Parameter(Mandatory = $true)][guid]$AgentId
        )

        $targetJson = '{"@odata.id":"bots(' + $AgentId + ')"}'
        $encodedTarget = [uri]::EscapeDataString($targetJson)
        $response = Invoke-DataverseRequest `
            -EnvironmentUrl $EnvironmentUrl `
            -Method Get `
            -RelativeUri "RetrieveSharedPrincipalsAndAccess(Target=@target)?@target=$encodedTarget"
        return @($response.PrincipalAccesses)
    }

    $results = foreach ($request in $requests) {
        $environmentUrl = ([string]$request.EnvironmentUrl).Trim().TrimEnd('/')
        $agentIdText = ([string]$request.AgentId).Trim()
        $principalType = ([string]$request.PrincipalType).Trim()
        $principalValue = ([string]$request.Principal).Trim()
        $accessRole = ([string]$request.AccessRole).Trim()
        $action = ([string]$request.Action).Trim()
        $status = 'Failed'
        $message = $null
        $resolvedPrincipal = $null

        try {
            if ([string]::IsNullOrWhiteSpace($environmentUrl)) {
                throw 'EnvironmentUrl is required.'
            }

            $agentId = [guid]::Empty
            if (-not [guid]::TryParse($agentIdText, [ref]$agentId)) {
                throw "AgentId '$agentIdText' isn't a valid GUID."
            }

            if ($accessRole -in @('AnalyticsViewer', 'EvaluationViewer')) {
                $status = 'Unsupported'
                $message = "Microsoft doesn't expose a supported public API for the $accessRole Copilot Studio sharing role."
            }
            elseif ($accessRole -notin @('Chat', 'Coauthor')) {
                throw "Unsupported AccessRole '$accessRole'. Use Chat, Coauthor, AnalyticsViewer, or EvaluationViewer."
            }
            elseif ($action -notin @('Grant', 'Revoke')) {
                throw "Unsupported Action '$action'. Use Grant or Revoke."
            }
            else {
                $agent = Get-SingleDataverseRow `
                    -EnvironmentUrl $environmentUrl `
                    -RelativeUri "bots?`$select=botid,name&`$filter=botid eq $agentId&`$top=2" `
                    -Description "Agent '$agentId'"
                $resolvedPrincipal = Resolve-Principal `
                    -EnvironmentUrl $environmentUrl `
                    -PrincipalType $principalType `
                    -Principal $principalValue

                if ($accessRole -eq 'Coauthor' -and $resolvedPrincipal.Type -ne 'User') {
                    throw 'Coauthor access is supported only for individual users.'
                }

                $shares = Get-DirectAgentShares -EnvironmentUrl $environmentUrl -AgentId $agentId
                $existingShare = $shares | Where-Object {
                    ([string]$_.Principal.ownerid).Trim('{}') -eq ([string]$resolvedPrincipal.Id).Trim('{}')
                } | Select-Object -First 1

                $target = @{
                    '@odata.type' = 'Microsoft.Dynamics.CRM.bot'
                    botid         = $agentId
                }
                $principal = @{
                    '@odata.type' = $resolvedPrincipal.ODataType
                    ownerid       = $resolvedPrincipal.Id
                }
                $description = "$action $accessRole access to '$($agent.name)' for '$($resolvedPrincipal.DisplayName)'"

                if (-not $PSCmdlet.ShouldProcess($environmentUrl, $description)) {
                    $status = 'WhatIf'
                    $message = $description
                }
                elseif ($action -eq 'Revoke') {
                    if (-not $existingShare) {
                        $status = 'Skipped'
                        $message = 'The principal has no direct share on this agent.'
                    }
                    else {
                        Invoke-DataverseRequest `
                            -EnvironmentUrl $environmentUrl `
                            -Method Post `
                            -RelativeUri 'RevokeAccess' `
                            -Body @{ Target = $target; Revokee = $principal } | Out-Null
                        $status = 'Revoked'
                        $message = 'All direct sharing rights were removed for this principal on the agent.'
                    }
                }
                else {
                    $accessMask = if ($accessRole -eq 'Chat') {
                        'ReadAccess'
                    }
                    else {
                        'ReadAccess,WriteAccess,AppendAccess,AppendToAccess,CreateAccess,ShareAccess,AssignAccess'
                    }
                    $operation = if ($existingShare) { 'ModifyAccess' } else { 'GrantAccess' }
                    Invoke-DataverseRequest `
                        -EnvironmentUrl $environmentUrl `
                        -Method Post `
                        -RelativeUri $operation `
                        -Body @{
                            Target          = $target
                            PrincipalAccess = @{
                                Principal  = $principal
                                AccessMask = $accessMask
                            }
                        } | Out-Null
                    $status = if ($operation -eq 'ModifyAccess') { 'Updated' } else { 'Granted' }
                    $message = "Applied access mask: $accessMask"
                }
            }
        }
        catch {
            $message = $_.Exception.Message
        }

        [pscustomobject]@{
            ProcessedOnUtc       = [datetime]::UtcNow.ToString('o')
            EnvironmentUrl       = $environmentUrl
            AgentId              = $agentIdText
            PrincipalType        = $principalType
            Principal            = $principalValue
            PrincipalDisplayName = $resolvedPrincipal.DisplayName
            AccessRole           = $accessRole
            Action               = $action
            Status               = $status
            Message              = $message
        }
    }

    $outputDirectory = Split-Path -Path $OutputPath -Parent
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force -WhatIf:$false | Out-Null
    }
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -WhatIf:$false
    return $results
}