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

try {
    Import-Module PnP.PowerShell -ErrorAction Stop

    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $importDotEnvPath = Join-Path $repoRoot "Shared\Import-DotEnv.ps1"
    $dotEnvPath = Join-Path $repoRoot ".env"

    if ((-not $env:SHAREPOINT_ONLINE_CLIENT_ID) -and (Test-Path -Path $importDotEnvPath) -and (Test-Path -Path $dotEnvPath)) {
        . $importDotEnvPath
        Import-DotEnv -Path $dotEnvPath
    }

    $resolvedClientId = $ClientId
    if ([string]::IsNullOrWhiteSpace($resolvedClientId)) {
        $resolvedClientId = $env:SHAREPOINT_ONLINE_CLIENT_ID
    }
    if ([string]::IsNullOrWhiteSpace($resolvedClientId)) {
        $resolvedClientId = $env:CLIENT_ID
    }

    $parsed = Parse-RecordingUrl -Url $RecordingUrl

    if (-not (Test-Path -Path $OutputFolder)) {
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    }

    $connection = $PnPWebConnection
    if (-not $connection) {
        Write-Host "Connecting to SharePoint site: $($parsed.SiteUrl)" -ForegroundColor Yellow

        if ([string]::IsNullOrWhiteSpace($resolvedClientId)) {
            throw "ClientId is required for Connect-PnPOnline in this tenant. Provide -ClientId or set SHAREPOINT_ONLINE_CLIENT_ID in .env."
        }

        $connectArgs = @{
            Url              = $parsed.SiteUrl
            Interactive      = $true
            ReturnConnection = $true
            ClientId         = $resolvedClientId
        }
        if ($ForceAuthentication) {
            $connectArgs.ForceAuthentication = $true
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

    if (-not $response.value -or $response.value.Count -eq 0) {
        throw "No transcript entries were returned for this recording."
    }

    $token = Get-PnPAccessToken -ResourceTypeName SharePoint -Connection $connection
    $headers = @{ Authorization = "Bearer $token" }

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
