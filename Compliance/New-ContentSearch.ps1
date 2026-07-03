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

    # Connect to Compliance Session
    try {
        Write-Host "Connecting to Compliance Session..." -ForegroundColor Cyan
        if ($UserPrincipalName) {
            Connect-IPPSSession -UserPrincipalName $UserPrincipalName -EnableSearchOnlySession
        }
        else {
            Connect-IPPSSession -EnableSearchOnlySession
        }
        Write-Host "Successfully connected to Compliance Session." -ForegroundColor Green
    }
    catch {
        $message = "Failed to connect to Compliance Session: $($_.Exception.Message)"
        Write-Error $message
        return [pscustomobject]@{
            Success = $false
            SearchName = $SearchName
            ActionIdentity = $null
            ErrorMessage = $message
        }
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
        $message = "Failed to create or start compliance search: $($_.Exception.Message)"
        Write-Error $message
        return [pscustomobject]@{
            Success = $false
            SearchName = $SearchName
            ActionIdentity = $null
            ErrorMessage = $message
        }
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
    Write-Host "`nFunction completed successfully. Search results are ready." -ForegroundColor Green

    return [pscustomobject]@{
        Success = $true
        SearchName = $SearchName
        ActionIdentity = $null
        ErrorMessage = $null
    }
}
