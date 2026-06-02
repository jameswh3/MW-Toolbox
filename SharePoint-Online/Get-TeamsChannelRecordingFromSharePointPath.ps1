#Requires -Version 7.0

<#
.SYNOPSIS
    Downloads transcript files for a Teams channel recording from SharePoint.

.DESCRIPTION
    Uses the SharePoint drive/item transcript endpoint pattern:
    /_api/v2.1/drives/{driveId}/items/{itemId}/media/transcripts

    Input is a recording URL in SharePoint. The script resolves the site, library,
    folder, and item, requests transcript metadata, and downloads transcript file(s)
    using temporaryDownloadUrl.

.PARAMETER RecordingUrl
    Full SharePoint URL to the recording file.

.PARAMETER OutputFolder
    Local folder for downloaded transcript files.
    Aliases: OutputPath, DestinationFolder

.PARAMETER PnPWebConnection
    Optional existing PnP connection. If omitted, the script connects interactively.

.PARAMETER ClientId
    Entra app registration client ID used for Connect-PnPOnline interactive auth.
    If omitted, the script attempts to resolve it from environment variables.

.PARAMETER TenantId
    Entra tenant ID (GUID or domain). Required for app-only client secret mode.

.PARAMETER ClientSecret
    Entra app client secret. Required for app-only client secret mode.

.PARAMETER CertificatePath
    Path to PFX certificate used for app-only certificate auth mode.

.PARAMETER CertificatePassword
    Password for the PFX certificate used for app-only certificate auth mode.

.PARAMETER CertificateThumbprint
    Certificate thumbprint in CurrentUser/My used for app-only certificate auth mode.

.PARAMETER AuthMode
    Authentication mode.
        - Auto: Uses Certificate mode when ClientId + TenantId + CertificatePath + CertificatePassword are available,
            otherwise ClientSecret mode when ClientId + TenantId + ClientSecret are available,
            otherwise Interactive.
    - Interactive: Uses delegated Connect-PnPOnline interactive auth.
        - Certificate: Uses app-only certificate auth via Connect-PnPOnline.
    - ClientSecret: Uses app-only OAuth client credentials and SharePoint REST.

.PARAMETER ForceAuthentication
    Forces re-auth when establishing a new PnP connection.

.PARAMETER Force
    Overwrite existing output files. If not set, files are auto-renamed to avoid overwrite.

.PARAMETER PassThru
    Return objects describing downloaded transcript files.

.EXAMPLE
    .\Get-TeamsChannelRecordingFromSharePointPath.ps1 `
      -RecordingUrl "https://contoso.sharepoint.com/sites/Leadership/Shared%20Documents/General/Recordings/MyMeeting-Meeting Recording.mp4" `
      -OutputFolder "C:\Temp\Transcripts" `
      -PassThru

.EXAMPLE
        .\Get-TeamsChannelRecordingFromSharePointPath.ps1 `
            -RecordingUrl "https://contoso.sharepoint.com/sites/Leadership/Shared%20Documents/General/Recordings/MyMeeting-Meeting Recording.mp4" `
            -AuthMode ClientSecret `
            -ClientId "00000000-0000-0000-0000-000000000000" `
            -TenantId "11111111-1111-1111-1111-111111111111" `
            -ClientSecret "<secret>" `
            -OutputFolder "C:\Temp\Transcripts" `
            -PassThru
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RecordingUrl,

    [Parameter(Mandatory = $false)]
    [Alias("OutputPath", "DestinationFolder")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputFolder = (Join-Path (Get-Location).Path "Transcripts"),

    [Parameter(Mandatory = $false)]
    [object]$PnPWebConnection,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [string]$CertificatePath,

    [Parameter(Mandatory = $false)]
    [string]$CertificatePassword,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [ValidateSet("Auto", "Interactive", "Certificate", "ClientSecret")]
    [string]$AuthMode = "Auto",

    [switch]$ForceAuthentication,
    [switch]$Force,
    [switch]$PassThru
)

function Get-UniqueOutputPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        return $Path
    }

    $directory = Split-Path -Path $Path -Parent
    $fileNameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $extension = [System.IO.Path]::GetExtension($Path)

    $index = 1
    while ($true) {
        $candidate = Join-Path -Path $directory -ChildPath ("{0} ({1}){2}" -f $fileNameNoExt, $index, $extension)
        if (-not (Test-Path -Path $candidate)) {
            return $candidate
        }
        $index++
    }
}

function Parse-RecordingUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $uri = [System.Uri]$Url
    $segments = $uri.AbsolutePath.Trim('/') -split '/'

    if ($segments.Count -lt 5) {
        throw "RecordingUrl must include site, library, folder, and file path."
    }

    $scope = $segments[0].ToLowerInvariant()
    if ($scope -notin @('sites', 'teams')) {
        throw "RecordingUrl must use /sites/ or /teams/ path."
    }

    $sitePath = "/{0}/{1}" -f $segments[0], $segments[1]
    $siteUrl = "{0}://{1}{2}" -f $uri.Scheme, $uri.Host, $sitePath

    $documentLibrary = [System.Uri]::UnescapeDataString($segments[2])
    $recordingFileName = [System.Uri]::UnescapeDataString($segments[-1])

    $folderSegments = @()
    if ($segments.Count -gt 4) {
        $folderSegments = $segments[3..($segments.Count - 2)] | ForEach-Object { [System.Uri]::UnescapeDataString($_) }
    }

    [PSCustomObject]@{
        SiteUrl         = $siteUrl
        DocumentLibrary = $documentLibrary
        FolderPath      = ($folderSegments -join '/')
        FileName        = $recordingFileName
    }
}

function Get-SharePointOAuthToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant,

        [Parameter(Mandatory = $true)]
        [string]$AppId,

        [Parameter(Mandatory = $true)]
        [string]$AppSecret,

        [Parameter(Mandatory = $true)]
        [string]$SharePointHost
    )

    $tokenEndpoint = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token"
    $tokenBody = @{
        client_id     = $AppId
        client_secret = $AppSecret
        scope         = "https://$SharePointHost/.default"
        grant_type    = "client_credentials"
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
    if (-not $tokenResponse.access_token) {
        throw "Failed to acquire app-only token for SharePoint resource."
    }

    return $tokenResponse.access_token
}

function Invoke-SharePointRest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    $headers = @{
        Authorization = "Bearer $AccessToken"
        Accept        = "application/json;odata=nometadata"
    }

    return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers -ErrorAction Stop
}

function Get-SharePointRestFilesArray {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    if ($Response.value) {
        return @($Response.value)
    }
    if ($Response.d -and $Response.d.results) {
        return @($Response.d.results)
    }
    return @()
}

try {
    Import-Module PnP.PowerShell -ErrorAction Stop

    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $importDotEnvPath = Join-Path $repoRoot "Shared\Import-DotEnv.ps1"
    $dotEnvPath = Join-Path $repoRoot ".env"

    if ((Test-Path -Path $importDotEnvPath) -and (Test-Path -Path $dotEnvPath)) {
        . $importDotEnvPath
        Import-DotEnv -Path $dotEnvPath
    }

    $resolvedClientId = $ClientId
    if ([string]::IsNullOrWhiteSpace($resolvedClientId)) {
        $resolvedClientId = $env:SHAREPOINT_ONLINE_SELECTED_SITES_CLIENT_ID
    }
    if ([string]::IsNullOrWhiteSpace($resolvedClientId)) {
        $resolvedClientId = $env:SHAREPOINT_ONLINE_CLIENT_ID
    }
    if ([string]::IsNullOrWhiteSpace($resolvedClientId)) {
        $resolvedClientId = $env:CLIENT_ID
    }

    $resolvedTenantId = $TenantId
    if ([string]::IsNullOrWhiteSpace($resolvedTenantId)) {
        $resolvedTenantId = $env:SHAREPOINT_ONLINE_SELECTED_SITES_TENANT_ID
    }
    if ([string]::IsNullOrWhiteSpace($resolvedTenantId)) {
        $resolvedTenantId = $env:SHAREPOINT_ONLINE_TENANT_ID
    }
    if ([string]::IsNullOrWhiteSpace($resolvedTenantId)) {
        $resolvedTenantId = $env:TENANT_ID
    }

    $resolvedClientSecret = $ClientSecret
    if ([string]::IsNullOrWhiteSpace($resolvedClientSecret)) {
        $resolvedClientSecret = $env:SHAREPOINT_ONLINE_SELECTED_SITES_CLIENT_SECRET
    }
    if ([string]::IsNullOrWhiteSpace($resolvedClientSecret)) {
        $resolvedClientSecret = $env:SHAREPOINT_ONLINE_CLIENT_SECRET
    }

    $resolvedCertificatePath = $CertificatePath
    if ([string]::IsNullOrWhiteSpace($resolvedCertificatePath)) {
        $resolvedCertificatePath = $env:SHAREPOINT_ONLINE_SELECTED_SITES_CERTIFICATE_PATH
    }
    if ([string]::IsNullOrWhiteSpace($resolvedCertificatePath)) {
        $resolvedCertificatePath = $env:SHAREPOINT_ONLINE_CERTIFICATE_PATH
    }

    $resolvedCertificatePassword = $CertificatePassword
    if ([string]::IsNullOrWhiteSpace($resolvedCertificatePassword)) {
        $resolvedCertificatePassword = $env:SHAREPOINT_ONLINE_SELECTED_SITES_CERTIFICATE_PASSWORD
    }
    if ([string]::IsNullOrWhiteSpace($resolvedCertificatePassword)) {
        $resolvedCertificatePassword = $env:SHAREPOINT_ONLINE_CERTIFICATE_PASSWORD
    }

    $resolvedCertificateThumbprint = $CertificateThumbprint
    if ([string]::IsNullOrWhiteSpace($resolvedCertificateThumbprint)) {
        $resolvedCertificateThumbprint = $env:SHAREPOINT_ONLINE_SELECTED_SITES_CERTIFICATE_THUMBPRINT
    }
    if ([string]::IsNullOrWhiteSpace($resolvedCertificateThumbprint)) {
        $resolvedCertificateThumbprint = $env:SHAREPOINT_ONLINE_CERTIFICATE_THUMBPRINT
    }

    $effectiveAuthMode = $AuthMode
    if ($AuthMode -eq "Auto" -and -not [string]::IsNullOrWhiteSpace($env:SHAREPOINT_ONLINE_SELECTED_SITES_AUTH_MODE)) {
        $effectiveAuthMode = $env:SHAREPOINT_ONLINE_SELECTED_SITES_AUTH_MODE
    }
    if ($effectiveAuthMode -eq "Auto") {
        if (
            -not [string]::IsNullOrWhiteSpace($resolvedClientId) -and
            -not [string]::IsNullOrWhiteSpace($resolvedTenantId) -and
            -not [string]::IsNullOrWhiteSpace($resolvedCertificateThumbprint)
        ) {
            $effectiveAuthMode = "Certificate"
        }
        elseif (
            -not [string]::IsNullOrWhiteSpace($resolvedClientId) -and
            -not [string]::IsNullOrWhiteSpace($resolvedTenantId) -and
            -not [string]::IsNullOrWhiteSpace($resolvedCertificatePath) -and
            -not [string]::IsNullOrWhiteSpace($resolvedCertificatePassword)
        ) {
            $effectiveAuthMode = "Certificate"
        }
        elseif (
            -not [string]::IsNullOrWhiteSpace($resolvedClientId) -and
            -not [string]::IsNullOrWhiteSpace($resolvedTenantId) -and
            -not [string]::IsNullOrWhiteSpace($resolvedClientSecret)
        ) {
            $effectiveAuthMode = "ClientSecret"
        }
        else {
            $effectiveAuthMode = "Interactive"
        }
    }

    $parsed = Parse-RecordingUrl -Url $RecordingUrl

    if (-not (Test-Path -Path $OutputFolder)) {
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    }

    $response = $null
    $recordingFile = $null
    $siteUrl = $parsed.SiteUrl
    $driveId = $null
    $itemId = $null
    $sharePointAccessToken = $null

    if ($effectiveAuthMode -in @("Interactive", "Certificate")) {
        $connection = $PnPWebConnection
        if (-not $connection) {
            if ($effectiveAuthMode -eq "Interactive") {
                Write-Host "Connecting to SharePoint site (Interactive): $($parsed.SiteUrl)" -ForegroundColor Yellow
            }
            else {
                Write-Host "Connecting to SharePoint site (Certificate app-only): $($parsed.SiteUrl)" -ForegroundColor Yellow
            }

            if ([string]::IsNullOrWhiteSpace($resolvedClientId)) {
                throw "ClientId is required for $effectiveAuthMode mode. Provide -ClientId or set SHAREPOINT_ONLINE_SELECTED_SITES_CLIENT_ID in .env."
            }

            if ($effectiveAuthMode -eq "Interactive") {
                $connectArgs = @{
                    Url              = $parsed.SiteUrl
                    Interactive      = $true
                    ReturnConnection = $true
                    ClientId         = $resolvedClientId
                }
                if ($ForceAuthentication) {
                    $connectArgs.ForceAuthentication = $true
                }
            }
            else {
                if ([string]::IsNullOrWhiteSpace($resolvedTenantId)) {
                    throw "TenantId is required for Certificate mode. Provide -TenantId or set SHAREPOINT_ONLINE_SELECTED_SITES_TENANT_ID in .env."
                }
                if (-not [string]::IsNullOrWhiteSpace($resolvedCertificateThumbprint)) {
                    $connectArgs = @{
                        Url              = $parsed.SiteUrl
                        ClientId         = $resolvedClientId
                        Tenant           = $resolvedTenantId
                        Thumbprint       = $resolvedCertificateThumbprint
                        ReturnConnection = $true
                    }
                }
                else {
                    if ([string]::IsNullOrWhiteSpace($resolvedCertificatePath)) {
                        throw "Certificate mode requires CertificateThumbprint or CertificatePath. Set SHAREPOINT_ONLINE_SELECTED_SITES_CERTIFICATE_THUMBPRINT or SHAREPOINT_ONLINE_SELECTED_SITES_CERTIFICATE_PATH in .env."
                    }
                    if (-not (Test-Path -Path $resolvedCertificatePath)) {
                        throw "CertificatePath not found: $resolvedCertificatePath"
                    }
                    if ([string]::IsNullOrWhiteSpace($resolvedCertificatePassword)) {
                        throw "CertificatePassword is required when using CertificatePath. Provide -CertificatePassword or set SHAREPOINT_ONLINE_SELECTED_SITES_CERTIFICATE_PASSWORD in .env."
                    }

                    $secureCertificatePassword = ConvertTo-SecureString -String $resolvedCertificatePassword -AsPlainText -Force
                    $connectArgs = @{
                        Url                 = $parsed.SiteUrl
                        ClientId            = $resolvedClientId
                        Tenant              = $resolvedTenantId
                        CertificatePath     = $resolvedCertificatePath
                        CertificatePassword = $secureCertificatePassword
                        ReturnConnection    = $true
                    }
                }
            }

            $connection = Connect-PnPOnline @connectArgs
        }

        $site = Get-PnPSite -Connection $connection -Includes Id, Url
        $web = Get-PnPWeb -Connection $connection -Includes Id
        $library = Get-PnPList -Identity $parsed.DocumentLibrary -Connection $connection -Includes Id, Title

        $siteIdGuid = $site.Id
        $webIdGuid = $web.Id
        $listIdGuid = $library.Id

        $bytes = $siteIdGuid.ToByteArray() + $webIdGuid.ToByteArray() + $listIdGuid.ToByteArray()
        $driveId = "b!" + ([Convert]::ToBase64String($bytes)).Replace('/', '_').Replace('+', '-')

        $folderSiteRelativeUrl = $parsed.DocumentLibrary
        if (-not [string]::IsNullOrWhiteSpace($parsed.FolderPath)) {
            $folderSiteRelativeUrl = "$folderSiteRelativeUrl/$($parsed.FolderPath)"
        }

        Write-Host "Resolving recording item in folder: $folderSiteRelativeUrl" -ForegroundColor Yellow
        $files = Get-PnPFileInFolder -FolderSiteRelativeUrl $folderSiteRelativeUrl -Connection $connection -Includes UniqueId, Name, ServerRelativeUrl

        $recordingFile = $files | Where-Object { $_.Name -eq $parsed.FileName } | Select-Object -First 1
        if (-not $recordingFile) {
            throw "Recording file not found in folder '$folderSiteRelativeUrl': $($parsed.FileName)"
        }

        $itemId = $recordingFile.UniqueId
        $transcriptsRequestUrl = "$($site.Url)/_api/v2.1/drives/$driveId/items/$itemId/media/transcripts"

        Write-Host "Retrieving transcript metadata..." -ForegroundColor Yellow
        $response = Invoke-PnPSPRestMethod -Method Get -Url $transcriptsRequestUrl -Connection $connection
        $sharePointAccessToken = Get-PnPAccessToken -ResourceTypeName SharePoint -Connection $connection
    }
    else {
        if ([string]::IsNullOrWhiteSpace($resolvedClientId) -or [string]::IsNullOrWhiteSpace($resolvedTenantId) -or [string]::IsNullOrWhiteSpace($resolvedClientSecret)) {
            throw "ClientSecret mode requires ClientId, TenantId, and ClientSecret (parameters or env vars)."
        }

        Write-Host "Connecting with app-only client secret (Sites.Selected)..." -ForegroundColor Yellow
        $sharePointHost = ([System.Uri]$parsed.SiteUrl).Host
        $sharePointAccessToken = Get-SharePointOAuthToken -Tenant $resolvedTenantId -AppId $resolvedClientId -AppSecret $resolvedClientSecret -SharePointHost $sharePointHost

        $escapedLibrary = $parsed.DocumentLibrary.Replace("'", "''")
        $siteInfo = Invoke-SharePointRest -Uri "$siteUrl/_api/site?`$select=Id,Url" -AccessToken $sharePointAccessToken
        $webInfo = Invoke-SharePointRest -Uri "$siteUrl/_api/web?`$select=Id" -AccessToken $sharePointAccessToken
        $listInfo = Invoke-SharePointRest -Uri "$siteUrl/_api/web/lists/GetByTitle('$escapedLibrary')?`$select=Id,Title" -AccessToken $sharePointAccessToken

        $siteIdGuid = [Guid]$siteInfo.Id
        $webIdGuid = [Guid]$webInfo.Id
        $listIdGuid = [Guid]$listInfo.Id

        $bytes = $siteIdGuid.ToByteArray() + $webIdGuid.ToByteArray() + $listIdGuid.ToByteArray()
        $driveId = "b!" + ([Convert]::ToBase64String($bytes)).Replace('/', '_').Replace('+', '-')

        $recordingServerRelativeUrl = [System.Uri]::UnescapeDataString(([System.Uri]$RecordingUrl).AbsolutePath)
        $escapedRecordingRelative = $recordingServerRelativeUrl.Replace("'", "''")
        Write-Host "Resolving recording item via server-relative URL: $recordingServerRelativeUrl" -ForegroundColor Yellow

        $fileInfo = Invoke-SharePointRest -Uri "$siteUrl/_api/web/GetFileByServerRelativeUrl('$escapedRecordingRelative')?`$select=Name,UniqueId,ServerRelativeUrl" -AccessToken $sharePointAccessToken
        if (-not $fileInfo.UniqueId) {
            throw "Recording file could not be resolved via server-relative URL."
        }

        $recordingFile = [PSCustomObject]@{
            Name = $fileInfo.Name
        }

        $itemId = $fileInfo.UniqueId
        $transcriptsRequestUrl = "$siteUrl/_api/v2.1/drives/$driveId/items/$itemId/media/transcripts"

        Write-Host "Retrieving transcript metadata..." -ForegroundColor Yellow
        $response = Invoke-SharePointRest -Uri $transcriptsRequestUrl -AccessToken $sharePointAccessToken
    }

    if (-not $response.value -or $response.value.Count -eq 0) {
        throw "No transcript entries were returned for this recording."
    }

    $headers = @{ Authorization = "Bearer $sharePointAccessToken" }

    $results = @()
    $i = 1
    foreach ($transcript in $response.value) {
        if ([string]::IsNullOrWhiteSpace($transcript.temporaryDownloadUrl)) {
            continue
        }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($recordingFile.Name)
        $targetPath = Join-Path -Path $OutputFolder -ChildPath ("{0} - {1}.vtt" -f $baseName, $i)

        if ((Test-Path -Path $targetPath) -and (-not $Force)) {
            $targetPath = Get-UniqueOutputPath -Path $targetPath
        }

        Write-Host "Downloading transcript $i -> $targetPath" -ForegroundColor Yellow
        Invoke-WebRequest -Uri $transcript.temporaryDownloadUrl -Headers $headers -OutFile $targetPath -ErrorAction Stop

        $result = [PSCustomObject]@{
            RecordingFileName = $recordingFile.Name
            RecordingUrl      = $RecordingUrl
            TranscriptIndex   = $i
            TranscriptPath    = $targetPath
            TranscriptId      = $transcript.id
            RetrievedAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
        }

        $results += $result
        $i++
    }

    if (-not $results -or $results.Count -eq 0) {
        throw "Transcript metadata was returned, but no downloadable transcript URLs were available."
    }

    Write-Host "Transcript download complete. Files: $($results.Count)" -ForegroundColor Green

    if ($PassThru) {
        $results
    }
}
catch {
    Write-Error "Failed to retrieve transcript from recording path. $($_.Exception.Message)"
    exit 1
}
