<#
.SYNOPSIS
    Returns the Microsoft Graph Drive ID for a SharePoint site's document libraries.

.DESCRIPTION
    Given a SharePoint site URL, connects to Microsoft Graph and returns the Drive ID(s)
    for one or all document libraries in that site.

.PARAMETER SharePointUrl
    The URL of the SharePoint site (e.g. https://contoso.sharepoint.com/sites/MySite).

.PARAMETER LibraryName
    Optional. Filter results to a specific document library by name.

.EXAMPLE
    .\Get-SharePointDriveId.ps1 -SharePointUrl "https://contoso.sharepoint.com/sites/MySite"

.EXAMPLE
    .\Get-SharePointDriveId.ps1 -SharePointUrl "https://contoso.sharepoint.com/sites/MySite" -LibraryName "Documents"
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$SharePointUrl,

    [Parameter(Mandatory = $false)]
    [string]$LibraryName
)

# Normalize URL: strip trailing slash
$SharePointUrl = $SharePointUrl.TrimEnd('/')

# Parse hostname and path
$uri = [System.Uri]$SharePointUrl
$hostname = $uri.Host
$path = $uri.AbsolutePath   # e.g. /sites/MySite

# Connect to Microsoft Graph if not already connected
if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes "Sites.Read.All" -NoWelcome
}

# Resolve the site
$siteUri = "https://graph.microsoft.com/v1.0/sites/${hostname}:${path}"
Write-Host "Resolving site: $SharePointUrl" -ForegroundColor Yellow

try {
    $site = Invoke-MgGraphRequest -Uri $siteUri -Method GET -ErrorAction Stop
}
catch {
    Write-Error "Could not resolve site '$SharePointUrl'. Verify the URL is correct and you have access.`n$($_.Exception.Message)"
    exit 1
}

Write-Host "Site: $($site.displayName)  (id: $($site.id))" -ForegroundColor Green

# Retrieve drives (document libraries)
$drivesUri = "https://graph.microsoft.com/v1.0/sites/$($site.id)/drives"

try {
    $drivesResponse = Invoke-MgGraphRequest -Uri $drivesUri -Method GET -ErrorAction Stop
}
catch {
    Write-Error "Could not retrieve drives for site '$SharePointUrl'.`n$($_.Exception.Message)"
    exit 1
}

$drives = $drivesResponse.value

if (-not $drives -or $drives.Count -eq 0) {
    Write-Warning "No document libraries found for this site."
    exit 0
}

# Filter by library name if specified
if ($LibraryName) {
    $drives = $drives | Where-Object { $_.name -eq $LibraryName }
    if (-not $drives) {
        Write-Error "No library named '$LibraryName' found in this site. Available libraries:`n$(($drivesResponse.value | Select-Object -ExpandProperty name) -join ', ')"
        exit 1
    }
}

# Output results
$drives | ForEach-Object {
    [PSCustomObject]@{
        Name      = $_.name
        DriveId   = $_.id
        DriveType = $_.driveType
        WebUrl    = $_.webUrl
    }
} | Format-Table -AutoSize
