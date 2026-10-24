#Requires -Modules Microsoft.Graph.Authentication

function Get-CopilotInteractionAuditLogItems {
      [CmdletBinding()]
      param(
            [Parameter(Mandatory = $true)]
            [string]$StartDate,

            [Parameter(Mandatory = $true)]
            [string]$EndDate,

            [Parameter(Mandatory = $false)]
            [string]$UserPrincipalName,

            [Parameter(Mandatory = $false)]
            [string]$OutputFile = "c:\temp\copilotaudit.csv",

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
            $Operations = @('CopilotInteraction')
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
                  $copilotDatum= New-Object PSObject
                  $copilotDatum | Add-Member NoteProperty AgentName($auditData.AgentName)
                  $copilotDatum | Add-Member NoteProperty AgentId($auditData.AgentId)
                  $copilotDatum | Add-Member NoteProperty EventDate($copilotResult.CreationDate)
                  $copilotDatum | Add-Member NoteProperty AppIdentity($auditData.AppIdentity)
                  $copilotDatum | Add-Member NoteProperty EventId($copilotResult.Identity)
                  $copilotDatum | Add-Member NoteProperty Operation($auditData.Operation)
                  $copilotDatum | Add-Member NoteProperty RecordType($copilotResult.RecordType)
                  $copilotDatum | Add-Member NoteProperty UserKey($auditData.UserKey)
                  $copilotDatum | Add-Member NoteProperty UserType($auditData.UserType)
                  $copilotDatum | Add-Member NoteProperty ClientIP($auditData.ClientIP)
                  $copilotDatum | Add-Member NoteProperty Workload($auditData.Workload)
                  $copilotDatum | Add-Member NoteProperty UserId($auditData.UserId)
                  $copilotDatum | Add-Member NoteProperty AppHost($auditData.CopilotEventData.AppHost)
                  $aiSysPlugins=@()
                  foreach ($aisysplugin in $auditData.CopilotEventData.AISystemPlugin) {
                        $aiSysPlugins+=$aisysplugin.Id
                  }
                  $copilotDatum | Add-Member NoteProperty AIPlugins($aiSysPlugins -join ",")
                  $messageCount=0
                  foreach ($message in $auditData.CopilotEventData.Messages) {
                        $messageCount++
                  }
                  $copilotDatum | Add-Member NoteProperty MessageCount ($messageCount)
                  $accessedResourceActionCounts = @{}
                  #Get Accessed Resources; note that when resource is a website, the Type is not present
                  $accessedResources=@()
                  $resources = @($auditData.CopilotEventData.AccessedResources)
                  foreach ($accessedResource in $resources) {
                        $accessedResources+=($accessedResource.Type) ? $accessedResource.Type : $accessedResource.SiteUrl

                        $actionKey = ($accessedResource.Action) ? $accessedResource.Action : "No Action Defined"
                        if ($accessedResourceActionCounts.ContainsKey($actionKey)) {
                              $accessedResourceActionCounts[$actionKey]++
                        } else {
                              $accessedResourceActionCounts[$actionKey] = 1
                        }
                  }
                  if ($accessedResourceActionCounts.Count -gt 0) {
                        $accessedResourceActionsJson = ($accessedResourceActionCounts | ConvertTo-Json -Compress)
                  } else {
                        $accessedResourceActionsJson = "{}"
                  }
                  $copilotDatum | Add-Member NoteProperty AccessedResourceActionsJson($accessedResourceActionsJson)
                  # Create a hashtable to store the counts of each string
                  if ($accessedResources.Count -gt 0) {
                        $accessedResourcesCounts = @{}
                        # Iterate through the array and count occurrences of each string
                        foreach ($item in $accessedResources) {
                              #write-host "For $($copilotDatum.EventId), Item: $item"
                              $key=($item) ? $item : "No Type Defined"
                              if ($accessedResourcesCounts.ContainsKey($key)) {
                                    $accessedResourcesCounts[$key]++
                              } else {
                                    $accessedResourcesCounts[$key] = 1
                              }
                        }
                        $resourceCountStrings = @($accessedResourcesCounts.GetEnumerator() | ForEach-Object { "$($_.Key) ($($_.Value))" })
                        $accessedResourcesCountsString = [string]::Join(", ", $resourceCountStrings)
                        $copilotDatum | Add-Member NoteProperty AccessedResources($accessedResourcesCountsString)
                  } else {
                        $copilotDatum | Add-Member NoteProperty AccessedResources("")
                  }
                  $copilotData+=$copilotDatum
            }

      }
      END {
            if ($Append -and (Test-Path -Path $OutputFile) -and $copilotData.Count -gt 0) {
                  $existingData = Import-Csv -Path $OutputFile

                  if ($existingData.Count -gt 0) {
                        $requiredColumns = @(
                              "AccessedResourceActionsJson"
                        )
                        $existingColumns = @($existingData[0].PSObject.Properties.Name)
                        $missingColumns = @($requiredColumns | Where-Object { $_ -notin $existingColumns })

                        if ($missingColumns.Count -gt 0) {
                              Write-Host "Existing CSV is missing new columns ($($missingColumns -join ', ')). Rewriting file with upgraded schema..." -ForegroundColor Yellow
                              $columnNames = [System.Collections.Generic.List[string]]::new()
                              $deprecatedColumns = @(
                                    "AccessedResourceActions",
                                    "ComputerUseInvocationCount",
                                    "HasComputerUseInvocation"
                              )

                              foreach ($name in $existingColumns) {
                                    if (($name -notin $deprecatedColumns) -and (-not $columnNames.Contains($name))) {
                                          $null = $columnNames.Add($name)
                                    }
                              }
                              foreach ($name in $copilotData[0].PSObject.Properties.Name) {
                                    if (($name -notin $deprecatedColumns) -and (-not $columnNames.Contains($name))) {
                                          $null = $columnNames.Add($name)
                                    }
                              }

                              $combinedData = @($existingData) + @($copilotData)
                              $combinedData | Select-Object -Property $columnNames | Export-Csv -Path $OutputFile -NoTypeInformation
                        }
                        else {
                              $copilotData | Export-CSV -Path $OutputFile -NoTypeInformation -Append
                        }
                  }
                  else {
                        $copilotData | Export-CSV -Path $OutputFile -NoTypeInformation
                  }
            }
            elseif ($Append) {
                  $copilotData | Export-CSV -Path $OutputFile -NoTypeInformation -Append
            }
            else {
                  $copilotData | Export-CSV -Path $OutputFile -NoTypeInformation
            }
      }

}
