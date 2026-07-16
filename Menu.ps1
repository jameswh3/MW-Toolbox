# Configuration Variables used by multiple scripts
$workingDirectory = (Get-Location).Path
$startDate = (Get-Date).AddDays(-10).ToString("yyyy-MM-dd")
$endDate = (Get-Date).AddDays(1).ToString("yyyy-MM-dd")
$outputDirectory = "c:\temp"

# Import the Import-DotEnv function
. (Join-Path $workingDirectory "scripts\bootstrap\Import-DotEnv.ps1")

# Load .env file if environment variables are not already set
if (-not $env:UPN) {
    Import-DotEnv
}

#multiple scripts
$tenantId = $env:TENANT_ID

#compliance scripts
$upn = $env:UPN
$copilotContentSearchMailbox = $env:COPILOT_CONTENT_SEARCH_MAILBOX
$copilotContentSearchUpn = $env:COPILOT_CONTENT_SEARCH_UPN
$copilotContentSearchQuery = $env:COPILOT_CONTENT_SEARCH_QUERY
$copilotContentSearchNamePrefix = $env:COPILOT_CONTENT_SEARCH_NAME_PREFIX
$copilotContentSearchOutputDirectory = $env:COPILOT_CONTENT_SEARCH_OUTPUT_DIRECTORY

#blob storage scripts
$storageAccountName = $env:STORAGE_ACCOUNT_NAME
$resourceGroupName = $env:RESOURCE_GROUP_NAME
$containerName = $env:CONTAINER_NAME

#Database Scripts
$SQLServerName = $env:SQL_SERVER_NAME
$SQLResourceGroupName = $env:SQL_RESOURCE_GROUP_NAME

#Fabric Scripts
$FabricResourceGroupName = $env:FABRIC_RESOURCE_GROUP_NAME
$fabricName = $env:FABRIC_NAME

#Power Platform Scripts (App Registration needs to be added as S2S User w/ sys admin for each environment in PPAC)
$PowerPlatClientId = $env:POWER_PLAT_CLIENT_ID
$PowerPlatClientSecret = $env:POWER_PLAT_CLIENT_SECRET
$PowerPlatTenantDomain = $env:POWER_PLAT_TENANT_DOMAIN

#Power Platform Transcript Script
$PowerPlatOrgUrl = $env:POWER_PLAT_ORG_URL

#Azure VM Scripts
$AzureSubscriptionId = $env:AZURE_SUBSCRIPTION_ID
$AzureVMResourceGroupName = $env:AZURE_VM_RESOURCE_GROUP_NAME

#Azure Key Vault Scripts
$KeyVaultName = $env:KEY_VAULT_NAME
$KeyValutResourceGroupName = $env:KEY_VAULT_RESOURCE_GROUP_NAME

#SharePoint Online Scripts
$SPOAdminUrl = $env:SHAREPOINT_ONLINE_ADMIN_URL

# PowerShell Menu Script Template with Categories

#Trim trailing backslash from working directory, if it exists
$workingDirectory = $workingDirectory.TrimEnd('\')

# Define menu items with categories
$menuCategories = [ordered]@{
    "Azure" = @(
        "Enable Public Network Access to Azure Key Vault",
        "Get Azure Agent Inventory",
        "Get SharePoint Embedded Inventory"
    )
    "Compliance" = @(
        "Download Copilot Audit Logs from M365 Tenant",
        "Download Full Audit Logs from M365 Tenant",
        "Apply Sensitivity Label to Folder",
        "Run Content Search for Admin Prompts and Responses"
    )
    "Compute" = @(
        "Start Azure VMs",
        "Stop Azure VMs",
        "Request JIT VM Access"
    )
    "Copilot" = @(
        "Get Billing Plans Via API",
        "Get Conversation Transcripts Via API",
        "Get Copilot Agents Via API",
        "Get Copilot Consumption Report",
        "Get Bot Components Via API"
    )
    "Database" = @(
        "Set Azure SQL Database Access"
    )
    "Fabric" = @(
        "Start Azure Fabric Capacity",
        "Stop Azure Fabric Capacity"
    )
    "Storage" = @(
        "Allow Azure Blob Storage Access",
        "Download Azure Blob Files"
    )
    "System" = @(
        "Sign Out of Azure",
        "Reload Environment Variables",
        "Exit"
    )
}

do {
    # Display menu

    Write-Host "================ Main Menu ================" -ForegroundColor Cyan

    $menuCounter = 1
    $menuLookup = @{}

    foreach ($category in $menuCategories.Keys) {
        Write-Host "`n[$category]" -ForegroundColor Yellow
        
        foreach ($item in $menuCategories[$category]) {
            $menuLookup[$menuCounter] = $item
            
            if ($item -eq "Exit") {
                Write-Host "$menuCounter. $item" -ForegroundColor Red
            } else {
                Write-Host "$menuCounter. $item" -ForegroundColor White
            }
            $menuCounter++
        }
    }

    Write-Host "`n==========================================" -ForegroundColor Cyan

    # Get user choice
    $choice = Read-Host "`nPlease select an option (1-$($menuCounter-1))"
    
    # Validate input
    if (-not $choice -or -not $menuLookup.ContainsKey([int]$choice)) {
        Write-Host "`nInvalid selection. Please choose 1-$($menuCounter-1)." -ForegroundColor Red
        Start-Sleep -Seconds 2
        continue
    }

    $selectedItem = $menuLookup[[int]$choice]
    write-host "Running $selectedItem..." -ForegroundColor Green
    # Switch statement for menu actions
    switch ($selectedItem) {
        "Download Copilot Audit Logs from M365 Tenant" { 
            
            . "$workingDirectory\Copilot\Get-CopilotInteractionAuditLogItems.ps1"
            if (-not ($upn)) {
                $upn = Read-Host "Enter your UPN"
            }
            
            Get-CopilotInteractionAuditLogItems -StartDate $startDate `
                    -EndDate $endDate `
                    -UserPrincipalName $upn `
                    -OutputFile "$outputDirectory\copilotauditlog.csv" `
                    -Append
        }
        "Download Full Audit Logs from M365 Tenant"{
            
            . "$workingDirectory\Compliance\Get-AuditLogResults.ps1"
            Get-AuditLogResults -StartDate $startDate `
                -EndDate $endDate `
                -UserPrincipalName $upn `
                -OutputPath "$outputDirectory\fullauditlog.csv"
        }
        "Apply Sensitivity Label to Folder" {
            $folderPath = Read-Host "Enter the folder path to label"
            if (-not (Test-Path -Path $folderPath -PathType Container)) {
                Write-Host "Folder does not exist: $folderPath" -ForegroundColor Red
            } else {
                . "$workingDirectory\Compliance\Set-PurviewSensitivityLabel.ps1"
                $labelId = $env:PURVIEW_LABEL_GUID
                if (-not $labelId) {
                    Write-Host "PURVIEW_LABEL_GUID is not set. Add it to .env and reload environment variables." -ForegroundColor Red
                    continue
                }
                Set-PurviewSensitivityLabel -FolderPath $folderPath `
                    -LabelId $labelId `
                    -JustificationMessage "Applied via menu automation"
            }
        }
        "Run Content Search for Admin Prompts and Responses" {
            # Ensure we're connected to Compliance Center
            try {
                $null = Get-ComplianceSearch -ErrorAction Stop | Select-Object -First 1
            }
            catch {
                Write-Host "Connecting to Compliance Center..." -ForegroundColor Yellow
                Connect-IPPSSession -UserPrincipalName $upn -EnableSearchOnlySession
            }

            . "$workingDirectory\Compliance\New-ContentSearch.ps1"

            if (-not $copilotContentSearchMailbox) {
                $copilotContentSearchMailbox = Read-Host "Enter mailbox to search (for example, admin@contoso.onmicrosoft.com)"
            }

            if (-not $copilotContentSearchUpn) {
                $copilotContentSearchUpn = $upn
            }

            if (-not $copilotContentSearchQuery) {
                # Try a simpler Copilot search first. Copilot messages may be indexed under kind:im or a specific itemclass.
                # Start with kind:im to test basic syntax, then refine if needed.
                $copilotContentSearchQuery = 'kind:im'
            }

            $searchNamePrefix = if ($copilotContentSearchNamePrefix) { $copilotContentSearchNamePrefix } else { "CopilotPromptResponseSearch" }
            $searchName = "{0}-{1}" -f $searchNamePrefix, (Get-Date -Format "yyyyMMdd-HHmmss")
            $contentSearchOutputDirectory = if ($copilotContentSearchOutputDirectory) { $copilotContentSearchOutputDirectory } else { $outputDirectory }

            if (-not (Test-Path $contentSearchOutputDirectory)) {
                New-Item -Path $contentSearchOutputDirectory -ItemType Directory -Force | Out-Null
            }

            $contentSearchResult = New-ContentSearch -SearchName $searchName `
                -Query $copilotContentSearchQuery `
                -Mailbox $copilotContentSearchMailbox `
                -UserPrincipalName $copilotContentSearchUpn

            if (-not $contentSearchResult -or -not $contentSearchResult.Success) {
                Write-Host "Content search failed. Skipping export details retrieval." -ForegroundColor Red
                if ($contentSearchResult -and $contentSearchResult.ErrorMessage) {
                    Write-Host $contentSearchResult.ErrorMessage -ForegroundColor Yellow
                }
                continue
            }

            Write-Host "Content search completed successfully. Search name: $searchName" -ForegroundColor Green
        }
        "Download Azure Blob Files" { 
            
            . "$workingDirectory\azure\Get-AzureBlobFiles.ps1" -StorageAccountName $storageAccountName `
                -ContainerName $containerName `
                -LocalPath $outputDirectory `
                -ClearDestination
        }
        "Allow Azure Blob Storage Access" { 
            
            . "$workingDirectory\azure\Set-AzureBlobStorageAccess.ps1"
            Set-AzureBlobStorageAccess -StorageAccountName $storageAccountName `
                -ResourceGroupName $resourceGroupName `
                -Enable
        }
        "Set Azure SQL Database Access" { 
            
            . "$workingDirectory\azure\Set-AzureSQLServerAccess.ps1"
            Set-AzureSQLServerAccess -ServerName $SQLServerName `
                -ResourceGroupName $SQLResourceGroupName 
        }
        "Start Azure Fabric Capacity" { 
            # Start Azure Fabric Capacity
            
            . "$workingDirectory\azure\Set-FabricCapacityState.ps1"
                Set-FabricCapacityState -ResourceGroupName $FabricResourceGroupName `
                    -FabricName $fabricName `
                    -State "Active"
        }
        "Stop Azure Fabric Capacity" { 
            # Pause Azure Fabric Capacity
            
            . "$workingDirectory\azure\Set-FabricCapacityState.ps1"
                Set-FabricCapacityState -ResourceGroupName $FabricResourceGroupName `
                    -FabricName $fabricName `
                    -State "Paused"
        }
        "Start Azure VMs" { 
            
            . "$workingDirectory\azure\Start-AzureVMs.ps1"
            Start-AzureVMs -SubscriptionId $AzureSubscriptionId `
                -ResourceGroupName $AzureVMResourceGroupName
        }
        "Stop Azure VMs" { 
            
            . "$workingDirectory\azure\Stop-AzureVMs.ps1"
            Stop-AzureVMs -SubscriptionId $AzureSubscriptionId `
                -ResourceGroupName $AzureVMResourceGroupName
        }
        "Request JIT VM Access" {
            . "$workingDirectory\Azure\Request-AzVMJitAccess.ps1"
            Request-AzVMJitAccess -ResourceGroupName $AzureVMResourceGroupName `
                -SubscriptionId $AzureSubscriptionId
        }
        "Enable Public Network Access to Azure Key Vault" {
            . "$workingDirectory\azure\Set-AzureKeyVaultNetworkAccess.ps1"
            Set-AzureKeyVaultNetworkAccess -ResourceGroupName $KeyValutResourceGroupName `
                -KeyVaultName $KeyVaultName `
                -AllowAllNetworks
        }
        "Get Azure Agent Inventory" {
            . "$workingDirectory\Azure\Get-AzureAgentInventory.ps1"
            Get-AzureAgentInventory -SubscriptionId $AzureSubscriptionId `
                -OutputPath "$outputDirectory\azure-agent-inventory.csv"
        }
        "Get SharePoint Embedded Inventory" {
            if (-not $SPOAdminUrl) {
                $SPOAdminUrl = Read-Host "Enter your SharePoint Online Admin URL (e.g., https://contoso-admin.sharepoint.com)"
            }
            . "$workingDirectory\SharePoint-Online\Get-SPOEmbeddedInventory.ps1"
            Get-SPOEmbeddedInventory -SPOAdminUrl $SPOAdminUrl `
                -OutputPath "$outputDirectory\spe-inventory.csv"
        }
        "Get Billing Plans Via API" {
            . "$workingDirectory\Power-Platform\Get-BillingPlansViaAPI.ps1"
            $billingPlans = Get-BillingPlansViaAPI -ClientId $PowerPlatClientId `
                -ClientSecret $PowerPlatClientSecret `
                -TenantDomain $PowerPlatTenantDomain
            $billingPlans | ConvertTo-Json -Depth 10 | Out-File "$outputDirectory\billingplans.json"
            Write-Host "Billing plans exported to $outputDirectory\billingplans.json" -ForegroundColor Green
        }
        "Get Conversation Transcripts Via API" {
            . "$workingDirectory\Power-Platform\Get-ConversationTranscriptsViaAPI.ps1"
            
            $transcriptData =Get-ConversationTranscriptsViaAPI -ClientId $PowerPlatClientId `
                -ClientSecret $PowerPlatClientSecret `
                -OrgUrl $PowerPlatOrgUrl `
                -TenantDomain $PowerPlatTenantDomain `
                -StartDate (Get-Date).AddDays(-30) `
                -EndDate (Get-Date)
            $transcriptData | out-file "$outputDirectory\conversationtranscripts.txt"
            Write-Host "Transcript data exported to $outputDirectory\conversationtranscripts.txt" -ForegroundColor Green
            Write-Host "Parsing transcript data into human-readable format..." -ForegroundColor Green
            . "$workingDirectory\Power-Platform\ConvertFrom-AgentTranscript.ps1" -InputFile "$outputDirectory\conversationtranscripts.txt" `
                -OutputFile "$outputDirectory\parsedconversationtranscripts.txt"
            Write-Host "Parsed transcript data saved to $outputDirectory\parsedconversationtranscripts.txt" -ForegroundColor Green
        }
        "Get Power Platform Users Via API" {
            . "$workingDirectory\Power-Platform\Get-UsersViaAPI.ps1"
            $PowerPlatUsers = Get-UsersViaAPI -ClientId $powerPlatClientId `
                -ClientSecret $clientSecret `
                -OrgUrl $PowerPlatOrgUrl `
                -TenantDomain $tenantDomain
            $PowerPlatUsers | out-file "$outputDirectory\powerplatusers.txt"
        }
        "Get Bot Components Via API"{
            . "$workingDirectory\Power-Platform\Get-BotComponentsViaAPI.ps1"
            Get-BotComponentsViaAPI -ClientId $powerPlatClientId `
            -ClientSecret $powerPlatClientSecret `
            -OrgUrl $PowerPlatOrgUrl `
            -TenantDomain $PowerPlatTenantDomain `
            -FieldList "botcomponentid,componenttype,data,description,filedata,filedata_name,name,schemaname,createdon,_createdby_value,modifiedon,_modifiedby_value,_parentbotid_value" `
            | out-file "c:\temp\botcomponents.txt"
        }
        "Get Copilot Consumption Report" {
            # This is from Joe Rodger and needs to be downloaded separately
            $reportScriptPath = "$workingDirectory\Power-Platform\Get-AgentMessageConsumptionReport.ps1"
            if (-not (Test-Path $reportScriptPath)) {
                Write-Host "The required script 'Get-AgentMessageConsumptionReport.ps1' was not found." -ForegroundColor Red
                Write-Host "Please download it from: https://gist.github.com/joerodgers/665925981c820cc47e8dd8e1c89ebec9" -ForegroundColor Yellow
                Write-Host "Save the file to: $workingDirectory\Power-Platform\" -ForegroundColor Yellow
                Write-Host "Press any key to continue..." -ForegroundColor Cyan
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                continue
            }
            . "$workingDirectory\Power-Platform\Get-AgentMessageConsumptionReport.ps1"
            # export usage to csv
            $consumption | Export-Csv `
                -Path "$outputDirectory\CopilotStudioCreditConsumptionReport-$startDate-$endDate.csv" `
                -NoTypeInformation
            if (Test-Path "$outputDirectory\CopilotStudioCreditConsumptionReport-$startDate-$endDate.csv") {
                Write-Host "Copilot Studio Credit Consumption Report saved to $outputDirectory\CopilotStudioCreditConsumptionReport-$startDate-$endDate.csv" -ForegroundColor Green
            } else {
                Write-Host "Failed to create Copilot Studio Credit Consumption Report" -ForegroundColor Red
            }
        }
        "Get Copilot Agents Via API" {
            Remove-Item "$outputDirectory\bots.txt" -ErrorAction SilentlyContinue
            . "$workingDirectory\Power-Platform\Get-CopilotAgentsViaAPI.ps1"
            Get-CopilotAgentsViaAPI -ClientId $PowerPlatClientId `
                -ClientSecret $PowerPlatClientSecret `
                -AllEnvironments `
                -TenantDomain $PowerPlatTenantDomain `
                -FieldList "botid,componentidunique,applicationmanifestinformation,name,configuration,createdon,publishedon,_ownerid_value,_createdby_value,solutionid,modifiedon,_owninguser_value,schemaname,_modifiedby_value,_publishedby_value,authenticationmode,synchronizationstatus,ismanaged" `
                | out-file "$outputDirectory\bots.txt" -Append
        }
        "Sign Out of Azure" {
            Write-Host "Signing out of Azure sessions..." -ForegroundColor Yellow

            try {
                if (Get-Command Disconnect-AzAccount -ErrorAction SilentlyContinue) {
                    Disconnect-AzAccount -Scope Process -ErrorAction SilentlyContinue | Out-Null
                    Disconnect-AzAccount -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
                }

                if (Get-Command Clear-AzContext -ErrorAction SilentlyContinue) {
                    Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue
                    Clear-AzContext -Scope CurrentUser -Force -ErrorAction SilentlyContinue
                }

                if (Get-Command az -ErrorAction SilentlyContinue) {
                    az logout | Out-Null
                }

                Write-Host "Azure sign-out complete." -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to fully sign out of Azure: $($_.Exception.Message)" -ForegroundColor Red
            }

            Start-Sleep -Seconds 2
        }
        "Reload Environment Variables" {
            Import-DotEnv
            $tenantId = $env:TENANT_ID
            $upn = $env:UPN
            $copilotContentSearchMailbox = $env:COPILOT_CONTENT_SEARCH_MAILBOX
            $copilotContentSearchUpn = $env:COPILOT_CONTENT_SEARCH_UPN
            $copilotContentSearchQuery = $env:COPILOT_CONTENT_SEARCH_QUERY
            $copilotContentSearchNamePrefix = $env:COPILOT_CONTENT_SEARCH_NAME_PREFIX
            $copilotContentSearchOutputDirectory = $env:COPILOT_CONTENT_SEARCH_OUTPUT_DIRECTORY
            $storageAccountName = $env:STORAGE_ACCOUNT_NAME
            $resourceGroupName = $env:RESOURCE_GROUP_NAME
            $containerName = $env:CONTAINER_NAME
            $SQLServerName = $env:SQL_SERVER_NAME
            $SQLResourceGroupName = $env:SQL_RESOURCE_GROUP_NAME
            $FabricResourceGroupName = $env:FABRIC_RESOURCE_GROUP_NAME
            $fabricName = $env:FABRIC_NAME
            $PowerPlatClientId = $env:POWER_PLAT_CLIENT_ID
            $PowerPlatClientSecret = $env:POWER_PLAT_CLIENT_SECRET
            $PowerPlatTenantDomain = $env:POWER_PLAT_TENANT_DOMAIN
            $PowerPlatOrgUrl = $env:POWER_PLAT_ORG_URL
            $AzureSubscriptionId = $env:AZURE_SUBSCRIPTION_ID
            $AzureVMResourceGroupName = $env:AZURE_VM_RESOURCE_GROUP_NAME
            $KeyVaultName = $env:KEY_VAULT_NAME
            $KeyValutResourceGroupName = $env:KEY_VAULT_RESOURCE_GROUP_NAME
            $SPOAdminUrl = $env:SHAREPOINT_ONLINE_ADMIN_URL
            Write-Host "Environment variables reloaded." -ForegroundColor Green
            Start-Sleep -Seconds 2
        }
        "Exit" { 
            Write-Host "`nExiting the script. Goodbye!" -ForegroundColor Yellow
            $exitMenu = $true
        }
        default { 
            Write-Host "`nInvalid selection." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while (-not $exitMenu)