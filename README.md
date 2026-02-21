# MW-Toolbox

A collection of scripts and files that I use as part of my role as a Copilot Solution Engineer.

## Environment Configuration

### Setting Up Your .env File

Many scripts in this toolbox use environment variables for configuration. These variables can be set using a `.env` file in the root directory of the repository.

#### Creating Your .env File

1. Copy the `.env-example` file to create your own `.env` file:

   ```powershell
   Copy-Item .env-example .env
   ```

2. Edit the `.env` file and replace the placeholder values with your actual configuration:

   ```plaintext
   # Multiple Scripts
   TENANT_ID=your-tenant-id-guid

   # Compliance scripts
   UPN=admin@yourtenant.onmicrosoft.com

   # Blob storage scripts
   STORAGE_ACCOUNT_NAME=yourstorageaccount
   RESOURCE_GROUP_NAME=your-resource-group
   CONTAINER_NAME=yourcontainer

   # And so on...
   ```

3. The `Menu.ps1` script will automatically load these variables when executed.

#### Available Environment Variables

The `.env-example` file includes configuration for:

- **Multiple Scripts**: `TENANT_ID`
- **Compliance Scripts**: `UPN`
- **Blob Storage Scripts**: `STORAGE_ACCOUNT_NAME`, `RESOURCE_GROUP_NAME`, `CONTAINER_NAME`
- **Database Scripts**: `SQL_SERVER_NAME`, `SQL_RESOURCE_GROUP_NAME`
- **Fabric Scripts**: `FABRIC_RESOURCE_GROUP_NAME`, `FABRIC_NAME`
- **Power Platform Scripts**: `POWER_PLAT_CLIENT_ID`, `POWER_PLAT_CLIENT_SECRET`, `POWER_PLAT_TENANT_DOMAIN`, `POWER_PLAT_ORG_URL`
- **Azure VM Scripts**: `AZURE_SUBSCRIPTION_ID`, `AZURE_VM_RESOURCE_GROUP_NAME`
- **SharePoint Online Scripts**: `SHAREPOINT_ONLINE_CLIENT_ID`, `SHAREPOINT_ONLINE_CERTIFICATE_PATH`, `SHAREPOINT_ONLINE_SITE_ID`, `SHAREPOINT_ONLINE_DRIVE_ID`, `SHAREPOINT_ONLINE_FOLDER_PATH`

> **Note**: The `.env` file is included in `.gitignore` to prevent accidentally committing sensitive credentials to version control.

## Root Scripts

### [Menu.ps1](Menu.ps1)

Central configuration file that sets up environment variables and common configuration used by multiple scripts. Includes functionality to load settings from a .env file.

#### Menu.ps1 Example

```PowerShell
# Load the configuration file
. .\Menu.ps1

# Environment variables will be loaded from .env file if present
# Variables include: UPN, TENANT_ID, STORAGE_ACCOUNT_NAME, etc.
```

## Azure

### [Get-AzureAppRegistrations.ps1](Azure/Get-AzureAppRegistrations.ps1)

Retrieves all Azure App Registrations and displays their names and App IDs.

#### Get-AzureAppRegistrations.ps1 Example

```PowerShell
# Run the script directly - it handles authentication and retrieval
.\Azure\Get-AzureAppRegistrations.ps1
```

### [Get-AzureBlobFiles.ps1](Azure/Get-AzureBlobFiles.ps1)

Retrieves information about files stored in Azure Blob Storage containers.

#### Get-AzureBlobFiles.ps1 Example

```PowerShell
# Set your Azure storage parameters
$storageAccountName = "yourstorageaccount"
$containerName = "yourcontainer"

# Run the script
.\Azure\Get-AzureBlobFiles.ps1
```

### [Get-CostReportsByResourceGroups.ps1](Azure/Get-CostReportsByResourceGroups.ps1)

Retrieves cost reports for Azure resource groups for a specified date range using Azure Cost Management API. Allows selection of resource groups and provides detailed cost breakdown by resource type.

#### Get-CostReportsByResourceGroups.ps1 Example

```PowerShell
# Get cost reports for the last 7 days with resource group selection prompt
Get-AzureCostReportsByResourceGroups

# Get cost reports for a specific date range
Get-AzureCostReportsByResourceGroups -StartDate "2025-12-01" -EndDate "2025-12-17"

# Specify subscription and output directory
Get-AzureCostReportsByResourceGroups -SubscriptionId "your-subscription-id" `
    -OutputDirectory "C:\temp\CostReports"
```

### [Get-EntraGroupMembers.ps1](Azure/Get-EntraGroupMembers.ps1)

Retrieves members of an Entra ID (Azure AD) group by name or email. Displays users, groups, and service principals with categorized output.

#### Get-EntraGroupMembers.ps1 Example

```PowerShell
# Get members of a group by display name
.\Azure\Get-EntraGroupMembers.ps1 -GroupNameOrEmail "Marketing Team"

# Get members of a group by email
.\Azure\Get-EntraGroupMembers.ps1 -GroupNameOrEmail "marketing@contoso.com"
```

### [Set-AzureBlobStorageAccess.ps1](Azure/Set-AzureBlobStorageAccess.ps1)

Configures network access rules for Azure Blob Storage accounts. Enables or disables public access and manages IP firewall rules.

#### Set-AzureBlobStorageAccess.ps1 Example

```PowerShell
# Enable network restrictions and add current IP
Set-AzureBlobStorageAccess -ResourceGroupName "myResourceGroup" `
    -StorageAccountName "mystorageaccount" `
    -Enable

# Disable network restrictions
Set-AzureBlobStorageAccess -ResourceGroupName "myResourceGroup" `
    -StorageAccountName "mystorageaccount"
```

### [Set-AzureSQLServerAccess.ps1](Azure/Set-AzureSQLServerAccess.ps1)

Configures Azure SQL Server access settings and firewall rules.

#### Set-AzureSQLServerAccess.ps1 Example

```PowerShell
# Configure SQL Server access
Set-AzureSQLServerAccess -ServerName "yoursqlserver" `
    -ResourceGroupName "your-resource-group"
```

### [Set-FabricCapacityState.ps1](Azure/Set-FabricCapacityState.ps1)

Manages the state (start/stop) of Microsoft Fabric capacities in Azure.

#### Set-FabricCapacityState.ps1 Example

```PowerShell
# Set your Fabric capacity parameters
$subscriptionId = "your-subscription-id"
$resourceGroupName = "your-resource-group"
$capacityName = "your-fabric-capacity"
$state = "Active" # or "Paused"

# Run the script
.\Azure\Set-FabricCapacityState.ps1
Set-FabricCapacityState -ResourceGroupName $resourceGroupName `
        -FabricName $fabricName `
        -State "Active"
```

### [Start-AzureVMs.ps1](Azure/Start-AzureVMs.ps1)

Starts Azure Virtual Machines across resource groups.

#### Start-AzureVMs.ps1 Example

```PowerShell
# Run the script
.\Azure\Start-AzureVMs.ps1

Start-AzureVMs -ResourceGroupName "<your resource group>" `
    -SubscriptionId "<your subscription id>"

```

### [Stop-AzureVMs.ps1](Azure/Stop-AzureVMs.ps1)

Stops Azure Virtual Machines across resource groups.

#### Stop-AzureVMs.ps1 Example

```PowerShell
# Stop VMs in a resource group
Stop-AzureVMs -ResourceGroupName "<your resource group>" `
    -SubscriptionId "<your subscription id>"
```

### [azure-maps-render-api.swagger.yaml](Azure/azure-maps-render-api.swagger.yaml)

A Swagger 2.0/OpenAPI definition file for the Azure Maps Render API. This file describes the API endpoints for generating static map images with customizable pins, paths, and styling. Can be used to create a custom Power Platform connector to the Azure Maps API.

#### azure-maps-render-api.swagger.yaml Example

Import this file into Power Platform to create a custom connector, or use a Swagger UI viewer to visualize and interact with the API.

## Compliance

### [ContentSearch.ps1](Compliance/ContentSearch.ps1)

Performs a compliance content search and exports the results.

#### ContentSearch.ps1 Example

```PowerShell
# Set your search parameters
$upn="admin@domain.com"
$complianceSearchName = "MyContentSearch"
$mailbox = "<mailbox email address>"
$startDate="2025-02-20"
$endDate="2025-02-22"
$kql="Subject:`"`" AND sent>=$startDate AND sent<=$endDate"

# Run the script
.\Compliance\ContentSearch.ps1
```

### [Get-AllRetentionPoliciesAndRules.ps1](Compliance/Get-AllRetentionPoliciesAndRules.ps1)

Retrieves all retention policies and their associated rules from Microsoft 365 Compliance Center.

#### Get-AllRetentionPoliciesAndRules.ps1 Example

```PowerShell
# Set your parameters
$upn = "admin@yourdomain.com"

# Run the script
.\Compliance\Get-AllRetentionPoliciesAndRules.ps1
```

### [Get-AuditLogResults.ps1](Compliance/Get-AuditLogResults.ps1)

Searches the unified audit log and retrieves results for specified date ranges.

#### Get-AuditLogResults.ps1 Example

```PowerShell
# Set your parameters
$startDate = "2025-06-01"
$endDate = "2025-06-24"

# Run the script
.\Compliance\Get-AuditLogResults.ps1
```

## Copilot

### [Get-CopilotCreationAuditLogItems.ps1](Copilot/Get-CopilotCreationAuditLogItems.ps1)

Retrieves audit log entries for Copilot bot creation events.

#### Get-CopilotCreationAuditLogItems.ps1 Example

```PowerShell
# Set your parameters
$upn = "admin@yourdomain.com"
$startDate = "2025-06-01"
$endDate = "2025-06-24"

# Run the script
.\Copilot\Get-CopilotCreationAuditLogItems.ps1
```

### [Get-CopilotInteractionAuditLogItems.ps1](Copilot/Get-CopilotInteractionAuditLogItems.ps1)

Retrieves audit log entries for Copilot interaction events.

#### Get-CopilotInteractionAuditLogItems.ps1 Example

```PowerShell

# Run the script with parameters
.\Copilot\Get-CopilotInteractionAuditLogItems.ps1 -StartDate '2025-06-01' `
    -EndDate '2025-06-30' `
    -UserPrincipalName 'admin@yourdomain.com' `
    -OutputFile 'c:\temp\copilotinteractionauditlog.csv' `
    -Append
```

### [copilot_retrieval_api.ipynb](Copilot/copilot_retrieval_api.ipynb)

A Jupyter Notebook for interacting with a Copilot retrieval API.

#### copilot_retrieval_api.ipynb Example

Open the notebook in a compatible environment like VS Code to see the documented steps for API interaction.

### [copilot-retrieval-api.swagger.yaml](Copilot/copilot-retrieval-api.swagger.yaml)

A Swagger/OpenAPI definition file for a Copilot retrieval API. This file describes the API endpoints, parameters, and responses & can be used to create a custom Power Platform connector to this API.

#### copilot-retrieval-api.swagger.yaml Example

Use a Swagger UI viewer to visualize and interact with the API defined in this file.

### [copilot_usage_reports_api.ipynb](Copilot/copilot_usage_reports_api.ipynb)

A Jupyter Notebook for retrieving Microsoft 365 Copilot usage reports via Microsoft Graph API using application permissions. Demonstrates authentication with client credentials and accessing Reports.Read.All API endpoints.

#### copilot_usage_reports_api.ipynb Example

Open the notebook in VS Code or Jupyter. Ensure your .env file contains:
- `CopilotReportAPIPythonClient_Id`
- `CopilotReportAPIPythonClient_Secret`
- `CopilotAPIPythonClient_Tenant`

Grant `Reports.Read.All` application permission in your Entra App Registration.

### [meeting_insights_api.ipynb](Copilot/meeting_insights_api.ipynb)

A Jupyter Notebook for retrieving Microsoft Teams meeting insights and transcripts using Microsoft Graph API with delegated user permissions. Demonstrates how to access meeting transcripts and AI-generated insights.

#### meeting_insights_api.ipynb Example

Open the notebook in VS Code or Jupyter. Configure your Entra App Registration with delegated permissions:
- `User.Read`
- `Calendars.Read`
- `OnlineMeetings.Read`
- `OnlineMeetingTranscript.Read.All`
- `OnlineMeetingAiInsight.Read.All`

Enable public client flow in your App Registration authentication settings.


### [Get-CopilotSharingAuditLogItems.ps1](Copilot/Get-CopilotSharingAuditLogItems.ps1)

Retrieves audit log entries for Copilot sharing events and activities.

#### Get-CopilotSharingAuditLogItems.ps1 Example

```PowerShell
# Set your parameters
$upn = "admin@yourdomain.com"
$startDate = "2025-06-01"
$endDate = "2025-06-24"

# Run the script
.\Copilot\Get-CopilotSharingAuditLogItems.ps1 -StartDate $startDate `
    -EndDate $endDate `
    -UserPrincipalName $upn `
    -OutputFile 'c:\temp\copilotsharingauditlog.csv'
```

## Entra

### [Get-EntraUserInfo.ps1](Entra/Get-EntraUserInfo.ps1)

Retrieves detailed information about an Entra ID user.

#### Get-EntraUserInfo.ps1 Example

```PowerShell
# Set the user UPN
$upn = "user@yourdomain.com"

# Run the script
.\Entra\Get-EntraUserInfo.ps1
```

### [Get-EntraUserLicenseInfo.ps1](Entra/Get-EntraUserLicenseInfo.ps1)

Gets license information for Entra ID users.

#### Get-EntraUserLicenseInfo.ps1 Example

```PowerShell
# Set the user UPN
$upn = "user@yourdomain.com"

# Run the script
.\Entra\Get-EntraUserLicenseInfo.ps1
```

### [New-EntraAppCertificate.ps1](Entra/New-EntraAppCertificate.ps1)

Creates a self-signed certificate for Entra (Azure AD) app registration authentication. Generates both PFX (with private key) and CER (public key) files with configurable validity period. Optionally installs the certificate to CurrentUser or LocalMachine certificate store.

#### New-EntraAppCertificate.ps1 Example

```PowerShell
# Create certificate with default settings (exports to C:\temp)
.\Entra\New-EntraAppCertificate.ps1

# Create certificate for specific app and install to CurrentUser store
.\Entra\New-EntraAppCertificate.ps1 -SubjectName "CN=SharePoint Scripts" -InstallToStore

# Create certificate with custom validity and install to LocalMachine (requires admin)
.\Entra\New-EntraAppCertificate.ps1 -SubjectName "CN=MyApp" `
    -ValidityYears 3 `
    -InstallToStore `
    -StoreLocation LocalMachine

# Specify custom export location and certificate name
.\Entra\New-EntraAppCertificate.ps1 -SubjectName "CN=MyApp" `
    -ExportPath "C:\Certificates" `
    -CertificateName "MyAppCert"
```

### [Update-AzureADUserUPN.ps1](Entra/Update-AzureADUserUPN.ps1)

Updates the User Principal Name (UPN) for Azure AD users.

#### Update-AzureADUserUPN.ps1 Example

```PowerShell
# Set the old and new UPN values
Update-AADUserUPN -originalUpn "user@olddomain.com" `
    -newUpn "user@newdomain.com" `
    -applyChanges `
    -logFolder 'c:\temp\upnupdatelog.csv'
```

## Misc

### [Get-SystemPerformanceAnalysis.ps1](Misc/Get-SystemPerformanceAnalysis.ps1)

Analyzes system performance metrics and provides detailed performance insights.

#### Get-SystemPerformanceAnalysis.ps1 Example

```PowerShell
# Run the script to analyze system performance
.\Misc\Get-SystemPerformanceAnalysis.ps1
```


## MsGraph

### [Get-OnlineMeetingRecordings.ps1](MsGraph/Get-OnlineMeetingRecordings.ps1)

Retrieves online meeting recordings for a specific user within a date range using Microsoft Graph.

#### Get-OnlineMeetingRecordings.ps1 Example

```PowerShell
# Set your parameters
$clientId = "your-app-registration-id"
$tenantId = "your-tenant-id"
$cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object {$_.Subject -like "*YourCertName*"}
$meetingOrganizerUserId = "user@yourdomain.com"

# Run the script
.\MsGraph\Get-OnlineMeetingRecordings.ps1
```

### [M365Reporting.ps1](MsGraph/M365Reporting.ps1)

Generates comprehensive Microsoft 365 usage and activity reports using Microsoft Graph.

#### M365Reporting.ps1 Example

```PowerShell
# Set your reporting parameters
$tenantId = "your-tenant-id"
$clientId = "your-app-registration-id"

# Run the script
.\MsGraph\M365Reporting.ps1
```

## Power-Platform

### [Add-AppUserViaCLI.ps1](Power-Platform/Add-AppUserViaCLI.ps1)

Adds an application user to Power Platform environment(s) using the Power Platform CLI. Supports adding to a single environment or all environments in a tenant with a specified security role. Requires Power Platform CLI (pac) to be installed.

#### Add-AppUserViaCLI.ps1 Example

```PowerShell
# Add app user to a specific environment
.\Power-Platform\Add-AppUserViaCLI.ps1 -AppId "12345678-1234-1234-1234-123456789012" `
    -OrgUrl "https://org.crm.dynamics.com"

# Add app user to ALL environments in the tenant
.\Power-Platform\Add-AppUserViaCLI.ps1 -AppId "12345678-1234-1234-1234-123456789012" `
    -AllEnvironments

# Use custom role and skip authentication
.\Power-Platform\Add-AppUserViaCLI.ps1 -AppId "12345678-1234-1234-1234-123456789012" `
    -OrgUrl "https://org.crm.dynamics.com" `
    -Role "Basic User" `
    -SkipAuth
```

### [ConvertFrom-AgentTranscript.ps1](Power-Platform/ConvertFrom-AgentTranscript.ps1)

Converts conversation transcript data from Power Platform to human-readable format, reconstructing chronological conversations between users and bots.

#### ConvertFrom-AgentTranscript.ps1 Example

```PowerShell
# Convert transcript data to readable format
.\Power-Platform\ConvertFrom-AgentTranscript.ps1 -InputFile "C:\temp\conversationtranscripts.txt" `
    -OutputFile "C:\temp\readable_transcripts.txt"
```

### [Get-AllDataPolicyConnectorInfo.ps1](Power-Platform/Get-AllDataPolicyConnectorInfo.ps1)

Retrieves information about all data policy connectors in the Power Platform tenant.

#### Get-AllDataPolicyConnectorInfo.ps1 Example

```PowerShell
# Run the script directly - it handles authentication and data retrieval
Get-AllDataPolicyConnectorInfo | Export-Csv -Path "C:\temp\PowerPlatformDataPolicyConnectors.csv" -NoTypeInformation -Force
```

### [Get-BotComponentsViaAPI.ps1](Power-Platform/Get-BotComponentsViaAPI.ps1)

Gets bot components information using Power Platform APIs.

#### Get-BotComponentsViaAPI.ps1 Example

```PowerShell
# Set your environment parameters
$clientId="<your client id>"
$clientSecret="<your client secret>"
$orgUrl="<your org>.crm.dynamics.com"
$tenantDomain="<your tenant domain>.onmicrosoft.com"

# Run the script
Get-BotComponentsViaAPI -ClientId $clientId `
    -ClientSecret $clientSecret `
    -OrgUrl $orgUrl `
    -TenantDomain $tenantDomain `
    -FieldList $fieldList
```

### [Get-ConversationTranscriptsViaAPI.ps1](Power-Platform/Get-ConversationTranscriptsViaAPI.ps1)

Retrieves conversation transcripts from Power Platform bots via API within a specified date range.

#### Get-ConversationTranscriptsViaAPI.ps1 Example

```PowerShell
# Set your environment parameters
$clientId = "<your client id>"
$clientSecret = "<your client secret>"
$orgUrl = "<your org>.crm.dynamics.com"
$tenantDomain = "<your tenant domain>.onmicrosoft.com"
$endDate = (Get-Date).ToString("yyyy-MM-dd")
$startDate = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")

# Run the script
Get-ConversationTranscriptsViaAPI -ClientId $clientId `
    -ClientSecret $clientSecret `
    -OrgUrl $orgUrl `
    -TenantDomain $tenantDomain `
    -StartDate $startDate `
    -EndDate $endDate `
    -FieldList "content,createdon,conversationtranscriptid,_bot_conversationtranscriptid_value,metadata" `
    | Export-Csv -Path "C:\temp\conversation-transcripts.csv" -NoTypeInformation
```

### [Get-CopilotAgentsViaAPI.ps1](Power-Platform/Get-CopilotAgentsViaAPI.ps1)

Retrieves Copilot agents information via Power Platform APIs.

#### Get-CopilotAgentsViaAPI.ps1 Example

```PowerShell
# Run the script

Get-CopilotAgentsViaAPI -ClientId "<your client id>" `
    -ClientSecret "<your client secret>" `
    -OrgUrl "<your org>.crm.dynamics.com" `
    -TenantDomain "<your domain>.onmicrosoft.com" `
    -FieldList "botid,componentidunique,applicationmanifestinformation,name,configuration,createdon,publishedon,_ownerid_value,_createdby_value,solutionid,modifiedon,_owninguser_value,schemaname,_modifiedby_value,_publishedby_value,authenticationmode,synchronizationstatus,ismanaged" `
    | Out-File "c:\temp\bots.txt"
```

### [Get-CopilotsAndComponentsFromAllEnvironments.ps1](Power-Platform/Get-CopilotsAndComponentsFromAllEnvironments.ps1)

Retrieves a comprehensive list of all Copilot agents and their components from all Power Platform environments.

#### Get-CopilotsAndComponentsFromAllEnvironments.ps1 Example

```PowerShell
# Run the script to get all copilots and components
.\Power-Platform\Get-CopilotsAndComponentsFromAllEnvironments.ps1 | Export-Csv -Path "C:\temp\AllCopilotsAndComponents.csv" -NoTypeInformation
```

### [Get-PowerAppsAndConnections.ps1](Power-Platform/Get-PowerAppsAndConnections.ps1)

Retrieves all Power Apps and their connections within the tenant.

#### Get-PowerAppsAndConnections.ps1 Example

```PowerShell
# Run the script to get all Power Apps and their connections
.\Power-Platform\Get-PowerAppsAndConnections.ps1 | Export-Csv -Path "C:\temp\PowerAppsAndConnections.csv" -NoTypeInformation
```

### [Get-PowerPlatformEnvironmentInfo.ps1](Power-Platform/Get-PowerPlatformEnvironmentInfo.ps1)

Retrieves detailed information about all Power Platform environments.

#### Get-PowerPlatformEnvironmentInfo.ps1 Example

```PowerShell
# Run the script to get environment information
.\Power-Platform\Get-PowerPlatformEnvironmentInfo.ps1 | Export-Csv -Path "C:\temp\PowerPlatformEnvironments.csv" -NoTypeInformation
```

### [Get-PowerPlatformUsageReports.ps1](Power-Platform/Get-PowerPlatformUsageReports.ps1)

Generates usage reports for Power Platform services.

#### Get-PowerPlatformUsageReports.ps1 Example

```PowerShell
# Run the script to generate usage reports
.\Power-Platform\Get-PowerPlatformUsageReports.ps1 -ReportType "ActiveUsers" -OutputDirectory "C:\temp\UsageReports"
```

### [Get-PowerPlatTenantSettingsViaAPI.ps1](Power-Platform/Get-PowerPlatTenantSettingsViaAPI.ps1)

Retrieves tenant-level settings for Power Platform via API.

#### Get-PowerPlatTenantSettingsViaAPI.ps1 Example

```PowerShell
# Set your environment parameters
$clientId = "<your client id>"
$clientSecret = "<your client secret>"
$tenantDomain = "<your tenant domain>.onmicrosoft.com"

# Run the script
.\Power-Platform\Get-PowerPlatTenantSettingsViaAPI.ps1 -ClientId $clientId -ClientSecret $clientSecret -TenantDomain $tenantDomain
```

### [Get-UsersViaAPI.ps1](Power-Platform/Get-UsersViaAPI.ps1)

Retrieves users from a Power Platform environment via API.

#### Get-UsersViaAPI.ps1 Example

```PowerShell
# Set your environment parameters
$clientId = "<your client id>"
$clientSecret = "<your client secret>"
$orgUrl = "<your org>.crm.dynamics.com"
$tenantDomain = "<your tenant domain>.onmicrosoft.com"

# Run the script
.\Power-Platform\Get-UsersViaAPI.ps1 -ClientId $clientId -ClientSecret $clientSecret -OrgUrl $orgUrl -TenantDomain $tenantDomain
```

## SharePoint

### [Inventory-SPFarm.ps1](SharePoint/Inventory-SPFarm.ps1)

Performs an inventory of a SharePoint farm. This is for on-premises SharePoint environments.

#### Inventory-SPFarm.ps1 Example

```PowerShell
# Run the script to start the inventory process
.\SharePoint\Inventory-SPFarm.ps1 -FarmConfigDatabase "SP_Config"
```

## SharePoint-Online

### [Add-OwnersToSharePointSite.ps1](SharePoint-Online/Add-OwnersToSharePointSite.ps1)

Adds owners to a SharePoint Online site.

#### Add-OwnersToSharePointSite.ps1 Example

```PowerShell
# Set your parameters
$siteUrl = "https://yourtenant.sharepoint.com/sites/YourSite"
$ownerEmails = "user1@yourdomain.com", "user2@yourdomain.com"

# Run the script
.\SharePoint-Online\Add-OwnersToSharePointSite.ps1 -SiteUrl $siteUrl -OwnerEmails $ownerEmails
```

### [ConvertTo-SharePointDriveId.ps1](SharePoint-Online/ConvertTo-SharePointDriveId.ps1)

Converts SharePoint site information to Drive IDs for Microsoft Graph API usage.

#### ConvertTo-SharePointDriveId.ps1 Example

```PowerShell
# Set the SharePoint site URL

ConvertTo-SharePointDriveId -siteId "<site GUID>" `
    -webId "<web GUID>" `
    -listId "<list GUID>"
```

### [Get-CopilotAgentReport.ps1](SharePoint-Online/Get-CopilotAgentReport.ps1)

Generates a report on Copilot agents in SharePoint Online.

#### Get-CopilotAgentReport.ps1 Example

```PowerShell
# Run the script to generate the report
.\SharePoint-Online\Get-CopilotAgentReport.ps1 -OutputDirectory "C:\temp\Reports"
```

### [Get-GraphDeltaQueryResults.ps1](SharePoint-Online/Get-GraphDeltaQueryResults.ps1)

Retrieves results from a Microsoft Graph delta query, which can be used to track changes to SharePoint Online resources.

#### Get-GraphDeltaQueryResults.ps1 Example

```PowerShell
# Run the script with your delta query parameters
.\SharePoint-Online\Get-GraphDeltaQueryResults.ps1 -DeltaLink "your_delta_link"
```

### [Get-SharePointAgentCreationAuditLogItems.ps1](SharePoint-Online/Get-SharePointAgentCreationAuditLogItems.ps1)

Retrieves audit log items related to the creation of SharePoint agents.

#### Get-SharePointAgentCreationAuditLogItems.ps1 Example

```PowerShell
# Set your parameters
$upn = "admin@yourdomain.com"
$startDate = "2025-06-01"
$endDate = "2025-06-24"

# Run the script
.\SharePoint-Online\Get-SharePointAgentCreationAuditLogItems.ps1 -StartDate $startDate -EndDate $endDate -UserPrincipalName $upn
```

### [Get-SharePointAgentInteractionAuditLogItems.ps1](SharePoint-Online/Get-SharePointAgentInteractionAuditLogItems.ps1)

Retrieves audit log items for SharePoint agent interactions.

#### Get-SharePointAgentInteractionAuditLogItems.ps1 Example

```PowerShell
# Set your parameters
$upn = "admin@yourdomain.com"
$startDate = "2025-06-01"
$endDate = "2025-06-24"

# Run the script
.\SharePoint-Online\Get-SharePointAgentInteractionAuditLogItems.ps1 -StartDate $startDate -EndDate $endDate -UserPrincipalName $upn
```

### [Get-SharePointFileProperties.ps1](SharePoint-Online/Get-SharePointFileProperties.ps1)

Retrieves properties of files in a SharePoint Online document library.

#### Get-SharePointFileProperties.ps1 Example

```PowerShell
# Set your parameters
$siteUrl = "https://yourtenant.sharepoint.com/sites/YourSite"
$libraryName = "Documents"

# Run the script
.\SharePoint-Online\Get-SharePointFileProperties.ps1 -SiteUrl $siteUrl -LibraryName $libraryName
```

### [New-DemoProjectHubSites.ps1](SharePoint-Online/New-DemoProjectHubSites.ps1)

Creates new hub sites for a demo project in SharePoint Online.

#### New-DemoProjectHubSites.ps1 Example

```PowerShell
# Run the script to create the demo hub sites
.\SharePoint-Online\New-DemoProjectHubSites.ps1
```

### [New-DemoProjectPlanDocs.ps1](SharePoint-Online/New-DemoProjectPlanDocs.ps1)

Creates new project plan documents for a demo in SharePoint Online.

#### New-DemoProjectPlanDocs.ps1 Example

```PowerShell
# Run the script to create the demo documents
.\SharePoint-Online\New-DemoProjectPlanDocs.ps1
```

### [New-HubSites.ps1](SharePoint-Online/New-HubSites.ps1)

Creates new hub sites in SharePoint Online.

#### New-HubSites.ps1 Example

```PowerShell
# Run the script to create new hub sites
.\SharePoint-Online\New-HubSites.ps1 -HubSiteNames "HR", "IT", "Finance"
```

### [New-OneDriveSites.ps1](SharePoint-Online/New-OneDriveSites.ps1)

Provisions new OneDrive for Business sites for users.

#### New-OneDriveSites.ps1 Example

```PowerShell
# Set the user emails
$userEmails = "user1@yourdomain.com", "user2@yourdomain.com"

# Run the script
.\SharePoint-Online\New-OneDriveSites.ps1 -UserEmails $userEmails
```

### [Set-SPOOrgAssetLibrary.ps1](SharePoint-Online/Set-SPOOrgAssetLibrary.ps1)

Designates a SharePoint Online document library as an organization assets library.

#### Set-SPOOrgAssetLibrary.ps1 Example

```PowerShell
# Set your parameters
$libraryUrl = "https://yourtenant.sharepoint.com/sites/branding/logos"

# Run the script
.\SharePoint-Online\Set-SPOOrgAssetLibrary.ps1 -LibraryUrl $libraryUrl
```

### [Upload-Documents.ps1](SharePoint-Online/Upload-Documents.ps1)

Uploads documents to a SharePoint Online document library.

#### Upload-Documents.ps1 Example

```PowerShell
# Set your parameters
$siteUrl = "https://yourtenant.sharepoint.com/sites/YourSite"
$libraryName = "Documents"
$sourceFolder = "C:\temp\Upload"

# Run the script
.\SharePoint-Online\Upload-Documents.ps1 -SiteUrl $siteUrl -LibraryName $libraryName -SourceFolder $sourceFolder
```

## SQL

### [TableSchemaToJSON.sql](SQL/TableSchemaToJSON.sql)

A SQL script that converts a table schema to a JSON format.

#### TableSchemaToJSON.sql Example

```sql
-- Execute this script in your SQL management tool against your database.
-- It will output the schema of a specified table as JSON.
```

## Teams

### [Get-AllTeamsMeetingPolicies.ps1](Teams/Get-AllTeamsMeetingPolicies.ps1)

Retrieves all Microsoft Teams meeting policies.

#### Get-AllTeamsMeetingPolicies.ps1 Example

```PowerShell
# Run the script to get all meeting policies
.\Teams\Get-AllTeamsMeetingPolicies.ps1 | Export-Csv -Path "C:\temp\TeamsMeetingPolicies.csv" -NoTypeInformation
```

### [Get-AllTeamsViaGraph.ps1](Teams/Get-AllTeamsViaGraph.ps1)

Retrieves a list of all teams in the organization using Microsoft Graph.

#### Get-AllTeamsViaGraph.ps1 Example

```PowerShell
# Run the script to get all teams
.\Teams\Get-AllTeamsViaGraph.ps1
```

### [Get-ChannelMessages.ps1](Teams/Get-ChannelMessages.ps1)

Retrieves messages from a specific Microsoft Teams channel.

#### Get-ChannelMessages.ps1 Example

```PowerShell
# Set your parameters
$teamId = "your-team-id"
$channelId = "your-channel-id"

# Run the script
.\Teams\Get-ChannelMessages.ps1 -TeamId $teamId -ChannelId $channelId
```

### [Get-TeamsAndMembers.ps1](Teams/Get-TeamsAndMembers.ps1)

Retrieves all teams and their members.

#### Get-TeamsAndMembers.ps1 Example

```PowerShell
# Run the script to get teams and members
.\Teams\Get-TeamsAndMembers.ps1 | Export-Csv -Path "C:\temp\TeamsAndMembers.csv" -NoTypeInformation
```

### [Get-UserTeams.ps1](Teams/Get-UserTeams.ps1)

Retrieves the teams that a specific user is a member of.

#### Get-UserTeams.ps1 Example

```PowerShell
# Set the user UPN
$upn = "user@yourdomain.com"

# Run the script
.\Teams\Get-UserTeams.ps1 -UserPrincipalName $upn
```

### [New-Channels.ps1](Teams/New-Channels.ps1)

Creates new channels in a Microsoft Team.

#### New-Channels.ps1 Example

```PowerShell
# Set your parameters
$teamId = "your-team-id"
$channelNames = "General", "Announcements", "Project-X"

# Run the script
.\Teams\New-Channels.ps1 -TeamId $teamId -ChannelNames $channelNames
```

### [New-Teams.ps1](Teams/New-Teams.ps1)

Creates new teams in Microsoft Teams.

#### New-Teams.ps1 Example

```PowerShell
# Run the script to create new teams
.\Teams\New-Teams.ps1 -TeamNames "Marketing Team", "Sales Team"
```

### [Set-ChannelModerationSettings.ps1](Teams/Set-ChannelModerationSettings.ps1)

Configures moderation settings for a Microsoft Teams channel.

#### Set-ChannelModerationSettings.ps1 Example

```PowerShell
# Set your parameters
$teamId = "your-team-id"
$channelId = "your-channel-id"

# Run the script
.\Teams\Set-ChannelModerationSettings.ps1 -TeamId $teamId -ChannelId $channelId -EnableModeration $true
```

### [Get-PowerPlatTenantSettingsViaAPI.ps1](Power-Platform/Get-PowerPlatTenantSettingsViaAPI.ps1)

Retrieves information about Power Platform Environments.

#### Get-PowerPlatTenantSettingsViaAPI.ps1 Example

```PowerShell
#Modify the following variables with your own values
    $clientId="<your client id>"
    $clientSecret="<your client secret>"
    $tenantDomain="<your tenant>.onmicrosoft.com>"

    .\Power-Platform\Get-PowerPlatTenantSettingsViaAPI.ps1
```

### [Get-UsersViaAPI.ps1](Power-Platform/Get-UsersViaAPI.ps1)

Retrieves user information via Power Platform APIs.

#### Get-UsersViaAPI.ps1 Example

```PowerShell
# Set your environment parameters
$clientId = "<your client id>"
$clientSecret = "<your client secret>"
$orgUrl = "<your org>.crm.dynamics.com"
$tenantDomain = "<your tenant domain>.onmicrosoft.com"

# Run the script
Get-UsersViaAPI -ClientId $clientId `
    -ClientSecret $clientSecret `
    -OrgUrl $orgUrl `
    -TenantDomain $tenantDomain `
    -FieldList "systemuserid,fullname,internalemailaddress,domainname,isdisabled,accessmode,createdon" `
    | Export-Csv -Path "C:\temp\users.csv" -NoTypeInformation
```

### [Set-NewPowerAppOwner.ps1](Power-Platform/Set-NewPowerAppOwner.ps1)

Changes the owner of a Power App in a Power Platform environment. Automatically installs required Power Apps administration modules if not present.

#### Set-NewPowerAppOwner.ps1 Example

```PowerShell
# Set the Power App ownership
.\Power-Platform\Set-NewPowerAppOwner.ps1 -AppName "cd304785-1a9b-44c3-91a8-c4174b59d835" `
    -EnvironmentName "de6b35af-dd3f-e14d-80ff-7a702c009100" `
    -AppOwner "7eda74de-bd8b-ef11-ac21-000d3a5a9ee8"
```

## SharePoint

### [Inventory-SPFarm.ps1](SharePoint/Inventory-SPFarm.ps1)

Creates an inventory of SharePoint on-premises farm components and configuration.

#### Inventory-SPFarm.ps1 Example

```PowerShell
# Set your SharePoint farm parameters
Inventory-SPFarm `
    -LogFilePrefix "Test_" `
    -DestinationFolder "d:\temp" `
    -InventoryFarmSolutions `
    -InventoryFarmFeatures `
    -InventoryWebTemplates `
    -InventoryTimerJobs `
    -InventoryWebApplications `
    -InventorySiteCollections `
    -InventorySiteCollectionAdmins `
    -InventorySiteCollectionFeatures `
    -InventoryWebPermissions `
    -InventoryWebs `
    -InventorySiteContentTypes `
    -InventoryWebFeatures `
    -InventoryLists `
    -InventoryWebWorkflowAssociations `
    -InventoryListContentTypes `
    -InventoryListWorkflowAssociations `
    -InventoryContentTypeWorkflowAssociations `
    -InventoryContentDatabases `
    -InventoryListFields `
    -InventoryListViews `
    -InventoryWebParts

```

## SQL

### [TableSchemaToJSON.sql](SQL/TableSchemaToJSON.sql)

SQL query that converts a table schema to JSON format, useful for documentation and schema analysis. Can be used in agent instructions to tell the agent how the tables are structured.

## Swagger Files

### [copilot-retrieval-api.swagger.yaml](Swagger%20Files/copilot-retrieval-api.swagger.yaml)

OpenAPI/Swagger specification for the Copilot Retrieval API, for use when building custom connectors for Power Platform.



## SharePoint-Online

### [Add-OwnersToSharePointSite.ps1](SharePoint-Online/Add-OwnersToSharePointSite.ps1)

Adds users as owners to a SharePoint site using certificate-based authentication.

#### Add-OwnersToSharePointSite.ps1 Example

```PowerShell
# Set your parameters
$siteUrl = "https://contoso.sharepoint.com/sites/yoursite"
$ownerEmails = @("user1@contoso.com", "user2@contoso.com")
$clientId = "your-app-registration-id"
$tenant = "contoso.onmicrosoft.com"
$certificatePath = "C:\path\to\certificate.pfx"

# Run the function
Add-OwnersToSharePointSite -SiteUrl $siteUrl `
    -OwnerEmails $ownerEmails `
    -ClientId $clientId `
    -Tenant $tenant `
    -CertificatePath $certificatePath
```

### [Get-CopilotAgentReport.ps1](SharePoint-Online/Get-CopilotAgentReport.ps1)

Generates reports on Copilot agent usage and activities in SharePoint Online.

#### Get-CopilotAgentReport.ps1 Example

```PowerShell
$spoAdminUrl="https://<your tenant>-admin.sharepoint.com"

.\SharePoint-Online\Get-CopilotAgentReport.ps1

```

### [Get-GraphDeltaQueryResults.ps1](SharePoint-Online/Get-GraphDeltaQueryResults.ps1)

Retrieves Microsoft Graph delta query results for tracking changes in SharePoint Online.

#### Get-GraphDeltaQueryResults.ps1 Example

```PowerShell
# Run the script to get delta query results
.\SharePoint-Online\Get-GraphDeltaQueryResults.ps1
```

### [Get-SharePointAgentCreationAuditLogItems.ps1](SharePoint-Online/Get-SharePointAgentCreationAuditLogItems.ps1)

Retrieves audit log entries for SharePoint agent creation events.

#### Get-SharePointAgentCreationAuditLogItems.ps1 Example

```PowerShell
# Set your parameters
$upn = "admin@yourdomain.com"
$startDate = "2025-06-01"
$endDate = "2025-06-24"

# Run the script
.\SharePoint-Online\Get-SharePointAgentCreationAuditLogItems.ps1
```

### [Get-SharePointAgentInteractionAuditLogItems.ps1](SharePoint-Online/Get-SharePointAgentInteractionAuditLogItems.ps1)

Retrieves audit log entries for SharePoint agent interaction events.

#### Get-SharePointAgentInteractionAuditLogItems.ps1 Example

```PowerShell
# Set your parameters
$upn = "admin@yourdomain.com"
$startDate = "2025-06-01"
$endDate = "2025-06-24"

# Run the script
.\SharePoint-Online\Get-SharePointAgentInteractionAuditLogItems.ps1
```

### [Get-SharePointFileProperties.ps1](SharePoint-Online/Get-SharePointFileProperties.ps1)

Gets metadata properties of a file in a SharePoint document library using PnP PowerShell.

#### Get-SharePointFileProperties.ps1 Example

```PowerShell
# Get file properties
.\SharePoint-Online\Get-SharePointFileProperties.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/team" `
    -LibraryUrl "/sites/team/Shared Documents" `
    -FileName "Document.docx"
```

### [New-DemoProjectHubSites.ps1](SharePoint-Online/New-DemoProjectHubSites.ps1)

Creates a complete demo environment with hub sites, regional sites, and project sites with proper associations.

#### New-DemoProjectHubSites.ps1 Example

```PowerShell
# Run the script to create demo project hub structure
.\SharePoint-Online\New-DemoProjectHubSites.ps1
```

### [New-DemoProjectPlanDocs.ps1](SharePoint-Online/New-DemoProjectPlanDocs.ps1)

Creates demo project plan documents with random team assignments and tasks.

#### New-DemoProjectPlanDocs.ps1 Example

```PowerShell
# Requires ImportExcel and PSWriteWord modules
# Run the script to generate project plan documents
.\SharePoint-Online\New-DemoProjectPlanDocs.ps1
```

### [New-HubSites.ps1](SharePoint-Online/New-HubSites.ps1)

Creates SharePoint Online Hub Sites using PnP.PowerShell, with optional parent hub site association.

#### New-HubSites.ps1 Example

```PowerShell
# Create hub sites
$siteUrls = @("https://contoso.sharepoint.com/sites/Hub1", "https://contoso.sharepoint.com/sites/Hub2")
$parentHubSiteId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Run the script
.\SharePoint-Online\New-HubSites.ps1 -SiteUrls $siteUrls -ParentHubSiteId $parentHubSiteId
```

### [New-OneDriveSites.ps1](SharePoint-Online/New-OneDriveSites.ps1)

Creates new OneDrive sites for users in SharePoint Online.

#### New-OneDriveSites.ps1 Example

```PowerShell
# Set your parameters
$usernames = @("user1@domain.com", "user2@domain.com", "user3@domain.com")
$batchSize = 200
$tenantName = "yourtenant"

# Run the script function
New-OneDriveSites -usernames $usernames -batchsize $batchSize -tenantname $tenantName
```

### [Set-SPOOrgAssetLibrary.ps1](SharePoint-Online/Set-SPOOrgAssetLibrary.ps1)

Configures SharePoint Online organizational asset libraries for Office templates and images.

#### Set-SPOOrgAssetLibrary.ps1 Example

```PowerShell
# Update the tenant variable with your tenant name
$tenant = "contoso"

# Run the script to configure organizational asset libraries
.\SharePoint-Online\Set-SPOOrgAssetLibrary.ps1
```

### [Upload-Documents.ps1](SharePoint-Online/Upload-Documents.ps1)

Uploads documents to specified SharePoint sites and libraries using an input array.

#### Upload-Documents.ps1 Example

```PowerShell
# Define documents to upload
$documents = @(
    @{
        FilePath = "C:\temp\ProjectA Plan.docx"
        SiteUrl = "https://contoso.sharepoint.com/sites/ProjectA"
        Library = "Shared Documents"
    },
    @{
        FilePath = "C:\temp\ProjectB Plan.docx"
        SiteUrl = "https://contoso.sharepoint.com/sites/ProjectB"
        Library = "Shared Documents"
    }
)

# Run the script
.\SharePoint-Online\Upload-Documents.ps1
```

## Teams

### [Get-AllTeamsMeetingPolicies.ps1](Teams/Get-AllTeamsMeetingPolicies.ps1)

Retrieves all Teams meeting policies and their configuration settings.

#### Get-AllTeamsMeetingPolicies.ps1 Example

```PowerShell
# Run the script to get all Teams meeting policies
.\Teams\Get-AllTeamsMeetingPolicies.ps1
```

### [Get-AllTeamsViaGraph.ps1](Teams/Get-AllTeamsViaGraph.ps1)

Retrieves all Microsoft Teams using Microsoft Graph API.

#### Get-AllTeamsViaGraph.ps1 Example

```PowerShell
# Set your Graph API parameters
$clientId = "your-app-registration-id"
$tenantId = "your-tenant-id"
$cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object {$_.Subject -like "*YourCertName*"}

# Run the script
.\Teams\Get-AllTeamsViaGraph.ps1
```

### [Get-ChannelMessages.ps1](Teams/Get-ChannelMessages.ps1)

Retrieves messages from specified Teams channels.

#### Get-ChannelMessages.ps1 Example

```PowerShell
# Run the script
.\Teams\Get-ChannelMessages.ps1
```

### [Get-TeamsAndMembers.ps1](Teams/Get-TeamsAndMembers.ps1)

Gets Teams and their membership information.

#### Get-TeamsAndMembers.ps1 Example

```PowerShell
# Run the script
.\Teams\Get-TeamsAndMembers.ps1
```

### [Get-UserTeams.ps1](Teams/Get-UserTeams.ps1)

Retrieves all Teams that a specific user is a member of.

#### Get-UserTeams.ps1 Example

```PowerShell
# Set the user parameters
$userId = "user@yourdomain.com"
$tenantId = "your-tenant-id"

# Run the script
.\Teams\Get-UserTeams.ps1
```

### [New-Channels.ps1](Teams/New-Channels.ps1)

Creates new channels in a specified Microsoft Team.

#### New-Channels.ps1 Example

```PowerShell
# Set your parameters
$teamId = "<your team id>"
$channelNames = @("General Discussion", "Project Updates", "Resources")

# Run the script
.\Teams\New-Channels.ps1 -TeamId $teamId -ChannelNames $channelNames
```

### [New-Teams.ps1](Teams/New-Teams.ps1)

Creates new Microsoft Teams with specified names and optional owners/members.

#### New-Teams.ps1 Example

```PowerShell
# Set your parameters
$teamNames = @("Project Alpha", "Project Beta", "Project Gamma")
$owner = "admin@yourdomain.com"
$members = @("user1@yourdomain.com", "user2@yourdomain.com")

# Run the script
.\Teams\New-Teams.ps1 -TeamNames $teamNames -Owner $owner -Members $members
```

### [Set-ChannelModerationSettings.ps1](Teams/Set-ChannelModerationSettings.ps1)

Configures moderation settings for Teams channels.

#### Set-ChannelModerationSettings.ps1 Example

```PowerShell
# Set your channel parameters
$clientId="<your client id>"
$teamId = "<your team id>"
$channelId = "<your-channel-id>"
$tenantDomain = "yourdomain.onmicrosoft.com"
$moderationSettings = @{
    "moderationSettings"= @{
        "userNewMessageRestriction"= "moderators"
        "replyRestriction" = "authorAndModerators"
        "allowNewMessageFromBots" = "false"
        "allowNewMessageFromConnectors"= "false"
    }
}

# Run the script
.\Teams\Set-ChannelModerationSettings.ps1
```

### [Set-TeamsAppAvailability.ps1](Teams/Set-TeamsAppAvailability.ps1)

Blocks a Teams app, making it unavailable to all users by modifying the app permission policy.

#### Set-TeamsAppAvailability.ps1 Example

```PowerShell
# Block a Teams app using its App ID
.\Teams\Set-TeamsAppAvailability.ps1 -AppId "12345678-1234-1234-1234-123456789012"

# Block app with a custom policy name
.\Teams\Set-TeamsAppAvailability.ps1 -AppId "12345678-1234-1234-1234-123456789012" `
    -PolicyName "CustomPolicy"
```
