# Configuration Variables used by multiple scripts
$workingDirectory = (Get-Location).Path
$startDate = (Get-Date).AddDays(-10).ToString("yyyy-MM-dd")
$endDate = (Get-Date).AddDays(1).ToString("yyyy-MM-dd")
$outputDirectory = "c:\temp"

# Function to load .env file if environment variables are not set
function Import-DotEnv {
    param(
        [string]$Path = (Join-Path $workingDirectory ".env")
    )
    
    if (Test-Path $Path) {
        Get-Content $Path | ForEach-Object {
            if ($_ -match '^([^#][^=]+)=(.*)$') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                # Remove quotes if present
                $value = $value -replace '^["'']|["'']$', ''
                [Environment]::SetEnvironmentVariable($name, $value, [EnvironmentVariableTarget]::Process)
            }
        }
        Write-Host "Loaded environment variables from .env file" -ForegroundColor Green
    } else {
        Write-Warning ".env file not found at $Path"
    }
}

# Load .env file if environment variables are not already set
if (-not $env:UPN) {
    Import-DotEnv
}

#multiple scripts
$tenantId = $env:TENANT_ID

#compliance scripts
$upn = $env:UPN

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

# PowerShell Menu Script Template with Categories

#Trim trailing backslash from working directory, if it exists
$workingDirectory = $workingDirectory.TrimEnd('\')

# Define menu items with categories
$menuCategories = [ordered]@{
    "Compliance" = @(
        "Download Copilot Audit Logs from M365 Tenant",
        "Download Full Audit Logs from M365 Tenant"
    )
    "Compute" = @(
        "Start Azure VMs",
        "Stop Azure VMs"
    )
    "Copilot" = @(
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