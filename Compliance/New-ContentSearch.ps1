#Requires -Modules ExchangeOnlineManagement

function New-ContentSearch {
    <#
    .SYNOPSIS
        Create and export a compliance search in Microsoft 365.

    .DESCRIPTION
        This function creates a new compliance search, waits for it to complete, and then exports the results.
        It monitors the status of both the search and export operations.

    .PARAMETER SearchName
        The name for the compliance search.

    .PARAMETER Query
        The KQL (Keyword Query Language) query for the content search.

    .PARAMETER Mailbox
        The mailbox location to search. Can be a specific mailbox or "All" for all mailboxes.

    .PARAMETER UserPrincipalName
        The UPN to use for connecting to the compliance session. If not specified, uses interactive authentication.

    .PARAMETER ExportFormat
        The format for the export. Default is "Mime". Options: Mime, FxStream, Pst.

    .PARAMETER StatusCheckInterval
        The interval in seconds to check the status of the search and export. Default is 10 seconds.

    .EXAMPLE
        New-ContentSearch -SearchName "Investigation001" -Query "subject:confidential" -Mailbox "user@contoso.com"
        Creates a compliance search for emails with "confidential" in the subject line.

    .EXAMPLE
        New-ContentSearch -SearchName "Q4Search" -Query "date>=2025-10-01" -Mailbox "All" -UserPrincipalName "admin@contoso.com"
        Creates a compliance search across all mailboxes for items from Q4 2025.

    .NOTES
        Author: James Hammonds
        Requires: ExchangeOnlineManagement module
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SearchName,
        
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [Parameter(Mandatory = $true)]
        [string]$Mailbox,
        
        [Parameter(Mandatory = $false)]
        [string]$UserPrincipalName,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Mime", "FxStream", "Pst")]
        [string]$ExportFormat = "Mime",
        
        [Parameter(Mandatory = $false)]
        [int]$StatusCheckInterval = 10
    )

    # Function to check the status of the compliance search
    function Get-ComplianceSearchStatus {
        param (
            [string]$searchName
        )
        # Get the status of the compliance search
        $searchStatus = Get-ComplianceSearch -Identity $searchName
        # Return the status
        return $searchStatus.Status
    }

    # Function to check the status of the compliance search action
    function Get-ComplianceSearchActionStatus {
        param (
            [string]$searchActionName
        )
        # Get the status of the compliance search action
        $searchActionStatus = Get-ComplianceSearchAction -Identity $searchActionName
        # Return the status
        return $searchActionStatus.Status
    }

    # Connect to Compliance Session
    try {
        Write-Host "Connecting to Compliance Session..." -ForegroundColor Cyan
        if ($UserPrincipalName) {
            Connect-IPPSSession -UserPrincipalName $UserPrincipalName
        }
        else {
            Connect-IPPSSession
        }
        Write-Host "Successfully connected to Compliance Session." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Compliance Session: $_"
        return
    }

    # Create new compliance search
    try {
        Write-Host "`nCreating compliance search: $SearchName" -ForegroundColor Cyan
        New-ComplianceSearch -Name $SearchName `
            -ContentMatchQuery $Query `
            -ExchangeLocation $Mailbox
        
        Write-Host "Starting compliance search..." -ForegroundColor Cyan
        Start-ComplianceSearch -Identity $SearchName
    }
    catch {
        Write-Error "Failed to create or start compliance search: $_"
        return
    }

    # Loop to check the status until the search is completed
    Write-Host "`nMonitoring search progress..." -ForegroundColor Yellow
    do {
        $status = Get-ComplianceSearchStatus -searchName $SearchName
        Write-Host "Current status of the compliance search '$SearchName': $status"
        if ($status -ne "Completed") {
            Start-Sleep -Seconds $StatusCheckInterval
        }
    } while ($status -ne "Completed")

    Write-Host "`nThe compliance search '$SearchName' is completed." -ForegroundColor Green

    # Create export action
    try {
        $complianceSearchActionName = "$SearchName - Export"
        Write-Host "`nCreating export action: $complianceSearchActionName" -ForegroundColor Cyan
        
        New-ComplianceSearchAction -SearchName $SearchName `
            -Export `
            -Format $ExportFormat `
            -Confirm:$false
    }
    catch {
        Write-Error "Failed to create compliance search export action: $_"
        return
    }

    # Loop to check the status until the search action is completed
    Write-Host "`nMonitoring export progress..." -ForegroundColor Yellow
    do {
        $status = Get-ComplianceSearchActionStatus -searchActionName "$SearchName`_Export"
        Write-Host "Current status of the compliance search action '$SearchName`_Export': $status"
        if ($status -ne "Completed") {
            Start-Sleep -Seconds $StatusCheckInterval
        }
    } while ($status -ne "Completed")

    Write-Host "`nThe compliance search action '$SearchName`_Export' is completed." -ForegroundColor Green
    Write-Host "`nFunction completed successfully. Export is ready for download." -ForegroundColor Green
}
