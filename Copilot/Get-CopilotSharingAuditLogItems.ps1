#Requires -Modules Microsoft.Graph.Authentication


function Get-CopilotSharingAuditLogItems {
      [CmdletBinding()]
      param(
            [Parameter(Mandatory = $false)]
            [string]$StartDate = (Get-Date).AddDays(-7).ToString("MM-dd-yyyy"),

            [Parameter(Mandatory = $false)]
            [string]$EndDate = (Get-Date).ToString("MM-dd-yyyy"),

            [Parameter(Mandatory = $false)]
            [string]$UserPrincipalName,

            [Parameter(Mandatory = $false)]
            [string]$OutputFile = "c:\temp\copilotshareaudit.csv",

            [Parameter(Mandatory = $false)]
            [switch]$Append,

                [ValidateRange(1, 86400)]
                [int]$TimeoutSeconds = 1800,

                [ValidateRange(1, 300)]
                [int]$PollIntervalSeconds = 10
      )
      PROCESS{
            $queryStart = [DateTimeOffset]$StartDate
            $queryEnd = [DateTimeOffset]$EndDate
            $RecordType = $null
            $Operations = @('BotUpdateOperation-BotShare')
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

            $copilotData=@()

            foreach ($copilotResult in $allResults) {
                  $auditData=ConvertFrom-JSON $copilotResult.AuditData
                  $copilotDatum = New-Object PSObject
                  $copilotDatum | Add-Member NoteProperty CreationTime($auditData.CreationTime)
                  $copilotDatum | Add-Member NoteProperty UserId($auditData.UserId)
                  $copilotDatum | Add-Member NoteProperty Operation($auditData.Operation)
                  $copilotDatum | Add-Member NoteProperty Workload($auditData.Workload)

                  # Extract bot update details from PropertyCollection
                  $botUpdateDetails = @()
                  if ($auditData.PropertyCollection) {
                        foreach ($property in $auditData.PropertyCollection) {
                              if ($property.Name -eq "powerplatform.analytics.resource.bot.update_details.change") {
                                    try {
                                          # Parse the JSON value if it's a string
                                          if ($property.Value -is [string]) {
                                                $changeDetails = ConvertFrom-Json $property.Value -ErrorAction SilentlyContinue
                                          } else {
                                                $changeDetails = $property.Value
                                          }

                                          # Create a structured object for the change details
                                          $changeInfo = [PSCustomObject]@{
                                                PropertyName = $property.Name
                                                ChangeDetails = $changeDetails
                                                RawValue = $property.Value
                                          }
                                          $botUpdateDetails += $changeInfo
                                    } catch {
                                          # If JSON parsing fails, capture the raw value
                                          $changeInfo = [PSCustomObject]@{
                                                PropertyName = $property.Name
                                                ChangeDetails = "Parse Error"
                                                RawValue = $property.Value
                                                Error = $_.Exception.Message
                                          }
                                          $botUpdateDetails += $changeInfo
                                    }
                              }
                        }
                  }
                  $copilotData+=$copilotDatum
            }
      }
      END {
            if ($Append) {
                  $copilotData | Export-CSV -path $OutputFile -NoTypeInformation -Append
            }
            else {
                  $copilotData | Export-CSV -path $OutputFile -NoTypeInformation
            }
      }

}
