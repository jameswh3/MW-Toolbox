#Requires -Modules Microsoft.Graph.Authentication


<#
.SYNOPSIS
    Retrieves audit log results from the Microsoft 365 Unified Audit Log.

.DESCRIPTION
    Searches the unified audit log for a specified date range and exports the results to a CSV file.
    Uses Microsoft Graph Purview audit queries, status polling, and paged retrieval.

.PARAMETER StartDate
    The start date for the audit log search. Defaults to 5 days ago.

.PARAMETER EndDate
    The end date for the audit log search. Defaults to tomorrow.

.PARAMETER UserPrincipalName
    The expected signed-in Microsoft Graph account. Not an audited-user filter.

.PARAMETER OutputPath
    The path where the CSV file will be saved. Defaults to c:\temp\audit.csv

.PARAMETER ExcludeBotIconUpdates
    Whether to exclude bot icon updates from the results. Defaults to $true.

.EXAMPLE
    Get-AuditLogResults -StartDate "2025-06-01" -EndDate "2025-06-24" -UserPrincipalName "admin@contoso.com"

.EXAMPLE
    Get-AuditLogResults -StartDate "2025-06-01" -EndDate "2025-06-24" -OutputPath "c:\reports\audit.csv"
#>
function Get-AuditLogResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$StartDate,

        [Parameter(Mandatory = $false)]
        [string]$EndDate,

        [Parameter(Mandatory = $false)]
        [string]$UserPrincipalName,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath = "c:\temp\audit.csv",

        [Parameter(Mandatory = $false)]
        [bool]$ExcludeBotIconUpdates = $true,

        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 1800,

        [ValidateRange(1, 300)]
        [int]$PollIntervalSeconds = 10
    )

    # Set default dates if not provided
    if (-not $StartDate) {
        $StartDate = (Get-Date).AddDays(-5).ToString("yyyy-MM-dd")
    }
    if (-not $EndDate) {
        $EndDate = (Get-Date).AddDays(1).ToString("yyyy-MM-dd")
    }

    Write-Host "Searching audit logs from $StartDate to $EndDate..." -ForegroundColor Cyan
    $queryStart = [DateTimeOffset]$StartDate
    $queryEnd = [DateTimeOffset]$EndDate
    $RecordType = $null
    $Operations = $null
    if ($queryStart -ge $queryEnd) {
            throw 'StartDate must be earlier than EndDate.'
        }

        $context = Get-MgContext
        if (-not $context) {
            Write-Host 'Connecting to Microsoft Graph for Purview audit search...'
            Connect-MgGraph -Scopes 'AuditLogsQuery.Read.All' -ContextScope Process -NoWelcome -ErrorAction Stop
            $context = Get-MgContext
        }
        if (-not $context) {
            throw 'Microsoft Graph authentication did not establish a context.'
        }
        if ($context.Environment -ne 'Global') {
            throw 'The Microsoft Graph Audit Search API currently supports only the Global cloud.'
        }
        if ($UserPrincipalName -and $context.AuthType -eq 'Delegated' -and $context.Account -ne $UserPrincipalName) {
            throw "Microsoft Graph is connected as '$($context.Account)', not '$UserPrincipalName'. Disconnect-MgGraph and connect with the intended account."
        }

        $body = @{
            displayName = "MW-Toolbox audit $([guid]::NewGuid())"
            filterStartDateTime = $queryStart.UtcDateTime.ToString('o')
            filterEndDateTime = $queryEnd.UtcDateTime.ToString('o')
        }
        if ($RecordType) {
            $body.recordTypeFilters = @($RecordType)
        }
        if ($Operations) {
            $body.operationFilters = @($Operations)
        }

        $queriesUri = 'https://graph.microsoft.com/v1.0/security/auditLog/queries'
        $query = Invoke-MgGraphRequest -Method POST -Uri $queriesUri `
            -Body ($body | ConvertTo-Json -Depth 10) -ContentType 'application/json' -OutputType PSObject -ErrorAction Stop
        if (-not $query.id) {
            throw 'Microsoft Graph did not return an audit query ID.'
        }

        $queryUri = "$queriesUri/$([uri]::EscapeDataString($query.id))"
        Write-Host "Submitted audit query $($query.id)."
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        while ($query.status -ne 'succeeded') {
            if ($query.status -notin @('notStarted', 'running')) {
                throw "Audit query $($query.id) ended with status '$($query.status)'. No results were exported."
            }
            if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                throw "Timed out waiting for audit query $($query.id). Inspect $queryUri before submitting another search."
            }
            Start-Sleep -Seconds ([Math]::Min($PollIntervalSeconds, [Math]::Max(1, [Math]::Ceiling($TimeoutSeconds - $timer.Elapsed.TotalSeconds))))
            $query = Invoke-MgGraphRequest -Method GET -Uri $queryUri -OutputType PSObject -ErrorAction Stop
        }

        if ($query.isRecordCountLimitExceeded -eq $true) {
            throw "Audit query $($query.id) exceeded its record limit ($($query.recordCountLimit)). Narrow the date range or filters and rerun; incomplete results were not exported."
        }

        # Buffer all pages so an API failure cannot produce a success-shaped partial export.
        $results = [System.Collections.Generic.List[object]]::new()
        $nextLink = "$queryUri/records"
        do {
            $page = Invoke-MgGraphRequest -Method GET -Uri $nextLink -OutputType PSObject -ErrorAction Stop
            if ($null -eq $page.value) {
                throw "Audit query $($query.id) returned a records page without a value collection."
            }
            foreach ($record in $page.value) {
                if ($null -eq $record.auditData) {
                    throw "Audit record $($record.id) is missing auditData."
                }
                $results.Add([pscustomobject]@{
                    CreationDate = $record.createdDateTime
                    Identity = $record.id
                    UserIds = $record.userPrincipalName
                    UserId = $record.userId
                    Operations = $record.operation
                    RecordType = $record.auditLogRecordType
                    AuditData = ConvertTo-Json -InputObject $record.auditData -Depth 100 -Compress
                })
            }
            $nextLink = $page.'@odata.nextLink'
        } while ($nextLink)
    $allResults = @($results)
    $allResults = @($allResults | Where-Object { -not $ExcludeBotIconUpdates -or $_.Operations -ne 'BotUpdateOperation-BotIconUpdate' })

    Write-Host "`nTotal results retrieved: $($allResults.Count)" -ForegroundColor Green

    # Export results
    if ($allResults.Count -gt 0) {
      if ($outputPath -ne "") {
        Write-Host "Exporting results to: $OutputPath" -ForegroundColor Cyan
        $allResults | Export-Csv -Path $OutputPath -NoTypeInformation
        Write-Host "Export complete!" -ForegroundColor Green
      } else {
            return $allResults
      }
    }
    else {
        Write-Host "No results found for the specified date range." -ForegroundColor Yellow
    }
}
