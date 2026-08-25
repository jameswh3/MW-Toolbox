#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Export-InventoryCsv {
	param (
		[object[]]$Rows,
		[string[]]$Columns,
		[string]$Path
	)

	if ($Rows.Count -gt 0) {
		$Rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
		return
	}

	$emptyRow = [ordered]@{}
	foreach ($column in $Columns) {
		$emptyRow[$column] = $null
	}
	([pscustomobject]$emptyRow | ConvertTo-Csv -NoTypeInformation)[0] |
		Set-Content -LiteralPath $Path -Encoding UTF8
}

function Export-PowerPlatformFlowAndConnectorInventory {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$EnvironmentName,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory,

		[ValidateNotNullOrEmpty()]
		[string[]]$FlowName
	)

	$environment = Get-AdminPowerAppEnvironment -EnvironmentName $EnvironmentName -ErrorAction Stop
	if ($null -eq $environment) {
		throw "Environment '$EnvironmentName' was not found."
	}
	$environmentDisplayName = $environment.DisplayName
	$invalidFileNameCharacters = [System.IO.Path]::GetInvalidFileNameChars()
	$invalidCharacterPattern = '[{0}]' -f [regex]::Escape((-join $invalidFileNameCharacters))
	$environmentFolderName = ($environmentDisplayName -replace $invalidCharacterPattern, '_').Trim().TrimEnd('.')
	if ([string]::IsNullOrWhiteSpace($environmentFolderName)) {
		$environmentFolderName = $EnvironmentName
	}
	$environmentOutputDirectory = Join-Path $OutputDirectory $environmentFolderName
	if (-not (Test-Path -LiteralPath $environmentOutputDirectory)) {
		$null = New-Item -Path $environmentOutputDirectory -ItemType Directory -Force
	}

	$flowPath = Join-Path $environmentOutputDirectory 'flows.csv'
	$connectorPath = Join-Path $environmentOutputDirectory 'custom-connectors.csv'
	$referencePath = Join-Path $environmentOutputDirectory 'connection-references.csv'
	$issuePath = Join-Path $environmentOutputDirectory 'issues.csv'

	$connections = @(Get-AdminPowerAppConnection -EnvironmentName $EnvironmentName -ErrorAction Stop)
	$connectionsByName = @{}
	$connectionRoleAssignmentsByName = @{}
	foreach ($connection in $connections) {
		$connectionsByName[$connection.ConnectionName] = $connection
		$connectionRoleAssignmentsByName[$connection.ConnectionName] = @(
			Get-AdminPowerAppConnectionRoleAssignment `
				-EnvironmentName $EnvironmentName `
				-ConnectorName $connection.ConnectorName `
				-ConnectionName $connection.ConnectionName `
				-ErrorAction Stop
		)
	}

	$flows = if ($FlowName) {
		@(foreach ($currentFlowName in $FlowName) {
			$flow = Get-AdminFlow `
				-EnvironmentName $EnvironmentName `
				-FlowName $currentFlowName `
				-ErrorAction Stop
			if ($null -eq $flow) {
				throw "Flow '$currentFlowName' was not found in environment '$EnvironmentName'."
			}
			$flow
		})
	}
	else {
		@(Get-AdminFlow -EnvironmentName $EnvironmentName -ErrorAction Stop)
	}

	$flowDetailsByName = @{}
	foreach ($flow in $flows) {
		$flowDetailsByName[$flow.FlowName] = Get-AdminFlow `
			-EnvironmentName $EnvironmentName `
			-FlowName $flow.FlowName `
			-ErrorAction Stop
	}

	$customConnectors = @(Get-AdminPowerAppConnector -EnvironmentName $EnvironmentName -ErrorAction Stop)
	$customConnectorsByName = @{}
	$connectorRoleAssignmentsByName = @{}
	foreach ($connector in $customConnectors) {
		$customConnectorsByName[$connector.ConnectorName] = $connector
		$connectorRoleAssignmentsByName[$connector.ConnectorName] = @(
			Get-AdminPowerAppConnectorRoleAssignment `
				-EnvironmentName $EnvironmentName `
				-ConnectorName $connector.ConnectorName `
				-ErrorAction Stop
		)
	}

	$issues = @()
	$connectorRows = @(
		foreach ($connector in $customConnectors) {
			$assignments = @($connectorRoleAssignmentsByName[$connector.ConnectorName])
			$oauthSettings = $connector.Internal.connectionParameters.token.oAuthSettings

			[pscustomobject]@{
				EnvironmentName             = $EnvironmentName
				ConnectorName               = $connector.ConnectorName
				DisplayName                 = $connector.DisplayName
				Description                 = $connector.Internal.description
				AlmMode                     = $connector.Internal.almMode
				Tier                        = $connector.Internal.tier
				BackendServiceUrl           = $connector.Internal.backendService.serviceUrl
				OAuthIdentityProvider       = $oauthSettings.identityProvider
				OAuthClientId               = $oauthSettings.clientId
				OAuthResourceId             = $oauthSettings.properties.AzureActiveDirectoryResourceId
				OAuthScopes                 = @($oauthSettings.scopes) -join '; '
				OAuthRedirectMode           = $oauthSettings.redirectMode
				CreatedTime                 = $connector.CreatedTime
				LastModifiedTime            = $connector.LastModifiedTime
				CreatedByObjectId           = $connector.CreatedBy.id
				CreatedByDisplayName        = $connector.CreatedBy.displayName
				CreatedByEmail              = $connector.CreatedBy.email
				ExplicitRoleAssignmentCount = $assignments.Count
				AssignedRoles               = @($assignments.RoleType | Sort-Object -Unique) -join '; '
				AssignedPrincipalObjectIds  = @($assignments.PrincipalObjectId | Sort-Object -Unique) -join '; '
				AssignedPrincipalTypes      = @($assignments.PrincipalType | Sort-Object -Unique) -join '; '
			}
		}
	)

	$flowRows = @()
	$referenceRows = @()
	foreach ($flow in $flows) {
		$flowDetail = $flowDetailsByName[$flow.FlowName]
		$properties = $flowDetail.Internal.properties
		$flowRoles = @(
			Get-AdminFlowOwnerRole `
				-EnvironmentName $EnvironmentName `
				-FlowName $flow.FlowName `
				-ErrorAction Stop
		)
		$references = $properties.connectionReferences
		$referenceCount = if ($null -eq $references) { 0 } else { @($references.PSObject.Properties).Count }

		$flowRows += [pscustomobject]@{
			EnvironmentName           = $EnvironmentName
			FlowName                  = $flow.FlowName
			DisplayName               = $flow.DisplayName
			Enabled                   = $flow.Enabled
			State                     = $properties.state
			SuspensionReason          = $properties.flowSuspensionReason
			IsManaged                 = $properties.isManaged
			ComponentState            = $properties.componentState
			CreatedTime               = $flow.CreatedTime
			LastModifiedTime          = $flow.LastModifiedTime
			CreatorObjectId           = $properties.creator.objectId
			OwningUserObjectId        = $properties.owningUser.azureActiveDirectoryObjectId
			WorkflowEntityId          = $flow.WorkflowEntityId
			ConnectionReferenceCount  = $referenceCount
			RoleAssignmentCount       = $flowRoles.Count
			AssignedRoles             = @($flowRoles.RoleType | Sort-Object -Unique) -join '; '
			AssignedPrincipalObjectIds = @($flowRoles.PrincipalObjectId | Sort-Object -Unique) -join '; '
		}

		if (-not $flow.Enabled -or $properties.state -ne 'Started') {
			$issues += [pscustomobject]@{
				Severity = 'Error'
				EnvironmentName = $EnvironmentName
				FlowName = $flow.FlowName
				FlowDisplayName = $flow.DisplayName
				ReferenceKey = $null
				ConnectorName = $null
				Issue = 'Flow is not enabled or started.'
			}
		}

		if ($properties.flowSuspensionReason -and $properties.flowSuspensionReason -ne 'None') {
			$issues += [pscustomobject]@{
				Severity = 'Error'
				EnvironmentName = $EnvironmentName
				FlowName = $flow.FlowName
				FlowDisplayName = $flow.DisplayName
				ReferenceKey = $null
				ConnectorName = $null
				Issue = "Flow suspension reason: $($properties.flowSuspensionReason)"
			}
		}

		if ($null -eq $references) {
			continue
		}

		foreach ($referenceProperty in $references.PSObject.Properties) {
			$reference = $referenceProperty.Value
			$connectorName = ($reference.id -split '/')[-1]
			$isCustomConnector = $customConnectorsByName.ContainsKey($connectorName)
			$customConnector = if ($isCustomConnector) { $customConnectorsByName[$connectorName] } else { $null }
			$connectorAssignments = if ($isCustomConnector) { @($connectorRoleAssignmentsByName[$connectorName]) } else { @() }
			$connectionFound = -not [string]::IsNullOrWhiteSpace($reference.connectionName) -and
				$connectionsByName.ContainsKey($reference.connectionName)
			$connection = if ($connectionFound) { $connectionsByName[$reference.connectionName] } else { $null }
			$connectionAssignments = if ($connectionFound) {
				@($connectionRoleAssignmentsByName[$reference.connectionName])
			}
			else {
				@()
			}
			$connectionStatus = @($connection.Statuses | ForEach-Object { $_.status }) -join '; '

			$referenceRows += [pscustomobject]@{
				EnvironmentName               = $EnvironmentName
				ResourceType                  = 'Flow'
				ResourceName                  = $flow.FlowName
				ResourceDisplayName           = $flow.DisplayName
				FlowName                     = $flow.FlowName
				FlowDisplayName              = $flow.DisplayName
				ReferenceKey                 = $referenceProperty.Name
				RuntimeSource                = $reference.source
				ConnectionName               = $reference.connectionName
				ConnectionFound              = $connectionFound
				ConnectionStatus             = $connectionStatus
				ConnectionOwnerObjectId       = $connection.CreatedBy.id
				ConnectionRoleAssignmentCount = $connectionAssignments.Count
				ConnectionAssignedRoles       = @($connectionAssignments.RoleType | Sort-Object -Unique) -join '; '
				ConnectionAssignedPrincipalObjectIds = @($connectionAssignments.PrincipalObjectId | Sort-Object -Unique) -join '; '
				ConnectionAssignedPrincipalTypes = @($connectionAssignments.PrincipalType | Sort-Object -Unique) -join '; '
				ConnectorName                = $connectorName
				ConnectorDisplayName         = $reference.displayName
				ConnectorId                  = $reference.id
				ConnectorTier                = $reference.tier
				IsCustomConnector            = $isCustomConnector
				CustomConnectorFound         = $null -ne $customConnector
				ConnectorRoleAssignmentCount = $connectorAssignments.Count
			}

			if ($reference.connectionName -and -not $connectionFound) {
				$issues += [pscustomobject]@{
					Severity = 'Error'
					EnvironmentName = $EnvironmentName
					FlowName = $flow.FlowName
					FlowDisplayName = $flow.DisplayName
					ReferenceKey = $referenceProperty.Name
					ConnectorName = $connectorName
					Issue = "Referenced connection '$($reference.connectionName)' was not found."
				}
			}

			if ($connectionFound -and $connectionStatus -notmatch 'Connected') {
				$issues += [pscustomobject]@{
					Severity = 'Error'
					EnvironmentName = $EnvironmentName
					FlowName = $flow.FlowName
					FlowDisplayName = $flow.DisplayName
					ReferenceKey = $referenceProperty.Name
					ConnectorName = $connectorName
					Issue = "Referenced connection is not Connected. Status: $connectionStatus"
				}
			}

			if ($reference.source -eq 'Invoker' -and $isCustomConnector -and $connectorAssignments.Count -eq 0) {
				$issues += [pscustomobject]@{
					Severity = 'Warning'
					EnvironmentName = $EnvironmentName
					FlowName = $flow.FlowName
					FlowDisplayName = $flow.DisplayName
					ReferenceKey = $referenceProperty.Name
					ConnectorName = $connectorName
					Issue = 'Invoker reference uses a custom connector with no explicit role assignments; only the connector owner has implicit access.'
				}
			}
		}
	}

	$apps = @(Get-AdminPowerApp -EnvironmentName $EnvironmentName -ErrorAction Stop)
	foreach ($app in $apps) {
		foreach ($referenceContainer in @($app.Internal.properties.connectionReferences)) {
			foreach ($referenceProperty in $referenceContainer.PSObject.Properties) {
				$reference = $referenceProperty.Value
				$connectorId = if ($reference.id) { $reference.id } else { $reference.api.id }
				$connectorName = ($connectorId -split '/')[-1]
				$connectionName = if ($reference.connectionName) {
					$reference.connectionName
				}
				else {
					$reference.connection.name
				}
				$isCustomConnector = $customConnectorsByName.ContainsKey($connectorName)
				$connectorAssignments = if ($isCustomConnector) {
					@($connectorRoleAssignmentsByName[$connectorName])
				}
				else {
					@()
				}
				$connectionFound = -not [string]::IsNullOrWhiteSpace($connectionName) -and
					$connectionsByName.ContainsKey($connectionName)
				$connection = if ($connectionFound) { $connectionsByName[$connectionName] } else { $null }
				$connectionAssignments = if ($connectionFound) {
					@($connectionRoleAssignmentsByName[$connectionName])
				}
				else {
					@()
				}
				$connectionStatus = @($connection.Statuses | ForEach-Object { $_.status }) -join '; '

				$referenceRows += [pscustomobject]@{
					EnvironmentName               = $EnvironmentName
					ResourceType                  = 'PowerApp'
					ResourceName                  = $app.AppName
					ResourceDisplayName           = $app.DisplayName
					FlowName                     = $null
					FlowDisplayName              = $null
					ReferenceKey                 = $referenceProperty.Name
					RuntimeSource                = $reference.source
					ConnectionName               = $connectionName
					ConnectionFound              = $connectionFound
					ConnectionStatus             = $connectionStatus
					ConnectionOwnerObjectId       = $connection.CreatedBy.id
					ConnectionRoleAssignmentCount = $connectionAssignments.Count
					ConnectionAssignedRoles       = @($connectionAssignments.RoleType | Sort-Object -Unique) -join '; '
					ConnectionAssignedPrincipalObjectIds = @($connectionAssignments.PrincipalObjectId | Sort-Object -Unique) -join '; '
					ConnectionAssignedPrincipalTypes = @($connectionAssignments.PrincipalType | Sort-Object -Unique) -join '; '
					ConnectorName                = $connectorName
					ConnectorDisplayName         = $reference.displayName
					ConnectorId                  = $connectorId
					ConnectorTier                = $reference.tier
					IsCustomConnector            = $isCustomConnector
					CustomConnectorFound         = $isCustomConnector
					ConnectorRoleAssignmentCount = $connectorAssignments.Count
				}

				if ($connectionName -and -not $connectionFound) {
					$issues += [pscustomobject]@{
						Severity = 'Error'
						EnvironmentName = $EnvironmentName
						FlowName = $null
						FlowDisplayName = $null
						ReferenceKey = $referenceProperty.Name
						ConnectorName = $connectorName
						Issue = "Power App '$($app.DisplayName)' references missing connection '$connectionName'."
					}
				}

				if ($connectionFound -and $connectionStatus -notmatch 'Connected') {
					$issues += [pscustomobject]@{
						Severity = 'Error'
						EnvironmentName = $EnvironmentName
						FlowName = $null
						FlowDisplayName = $null
						ReferenceKey = $referenceProperty.Name
						ConnectorName = $connectorName
						Issue = "Power App '$($app.DisplayName)' connection is not Connected. Status: $connectionStatus"
					}
				}
			}
		}
	}

	Export-InventoryCsv -Rows $flowRows -Columns @(
		'EnvironmentName', 'FlowName', 'DisplayName', 'Enabled', 'State', 'SuspensionReason',
		'IsManaged', 'ComponentState', 'CreatedTime', 'LastModifiedTime', 'CreatorObjectId',
		'OwningUserObjectId', 'WorkflowEntityId',
		'ConnectionReferenceCount', 'RoleAssignmentCount', 'AssignedRoles', 'AssignedPrincipalObjectIds'
	) -Path $flowPath
	Export-InventoryCsv -Rows $connectorRows -Columns @(
		'EnvironmentName', 'ConnectorName', 'DisplayName', 'Description', 'AlmMode', 'Tier',
		'BackendServiceUrl', 'OAuthIdentityProvider', 'OAuthClientId', 'OAuthResourceId',
		'OAuthScopes', 'OAuthRedirectMode', 'CreatedTime', 'LastModifiedTime', 'CreatedByObjectId',
		'CreatedByDisplayName', 'CreatedByEmail', 'ExplicitRoleAssignmentCount', 'AssignedRoles',
		'AssignedPrincipalObjectIds', 'AssignedPrincipalTypes'
	) -Path $connectorPath
	Export-InventoryCsv -Rows $referenceRows -Columns @(
		'EnvironmentName', 'ResourceType', 'ResourceName', 'ResourceDisplayName',
		'FlowName', 'FlowDisplayName', 'ReferenceKey', 'RuntimeSource',
		'ConnectionName', 'ConnectionFound', 'ConnectionStatus', 'ConnectionOwnerObjectId',
		'ConnectionRoleAssignmentCount', 'ConnectionAssignedRoles',
		'ConnectionAssignedPrincipalObjectIds', 'ConnectionAssignedPrincipalTypes',
		'ConnectorName', 'ConnectorDisplayName', 'ConnectorId', 'ConnectorTier',
		'IsCustomConnector', 'CustomConnectorFound', 'ConnectorRoleAssignmentCount'
	) -Path $referencePath
	Export-InventoryCsv -Rows $issues -Columns @(
		'Severity', 'EnvironmentName', 'FlowName', 'FlowDisplayName', 'ReferenceKey',
		'ConnectorName', 'Issue'
	) -Path $issuePath

	[pscustomobject]@{
		EnvironmentName          = $EnvironmentName
		EnvironmentDisplayName   = $environmentDisplayName
		OutputDirectory          = $environmentOutputDirectory
		FlowCount                = $flowRows.Count
		PowerAppCount            = $apps.Count
		CustomConnectorCount     = $connectorRows.Count
		ConnectionReferenceCount = $referenceRows.Count
		IssueCount               = $issues.Count
		FlowReport               = $flowPath
		ConnectorReport          = $connectorPath
		ConnectionReferenceReport = $referencePath
		IssueReport              = $issuePath
	}
}