<#
.SYNOPSIS
  Imports .rdp files from a source folder into an existing RDCMan .rdg file,
  creating/updating server entries under a dedicated group.
  Usernames (and domain, if present) are read from each .rdp file and written
  into the RDCMan logonCredentials element for each server entry.

.ENV VARIABLES
  RDCMAN_SOURCE_PATH      - Folder to scan for .rdp files. Defaults to $env:USERPROFILE\Downloads.
  RDCMAN_DESTINATION_PATH - Folder containing the .rdg file. Defaults to the user's Documents folder.
  RDCMAN_RDG_FILENAME     - RDG filename (e.g. j3msftlab.rdg).
  RDCMAN_GROUP_NAME       - Name of the group to import servers into.
#>

param(
  [string]$SourcePath      = $(if ($env:RDCMAN_SOURCE_PATH)      { $env:RDCMAN_SOURCE_PATH }      else { Join-Path $env:USERPROFILE "Downloads" }),
  [string]$DestinationPath = $(if ($env:RDCMAN_DESTINATION_PATH) { $env:RDCMAN_DESTINATION_PATH } else { [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyDocuments) }),
  [string]$RdgFileName     = $(if ($env:RDCMAN_RDG_FILENAME)     { $env:RDCMAN_RDG_FILENAME }     else { "j3msftlab.rdg" }),
  [string]$GroupName       = $(if ($env:RDCMAN_GROUP_NAME)        { $env:RDCMAN_GROUP_NAME }        else { "Imported RDPs (Downloads)" }),
  [switch]$WhatIf
)

function Get-RdpEndpoint {
  param([string]$RdpFilePath)

  $lines = Get-Content -LiteralPath $RdpFilePath -ErrorAction Stop

  # Prefer 'full address', then 'alternate full address'
  $addrLine       = ($lines | Where-Object { $_ -match '^(full address|alternate full address):s:' } | Select-Object -First 1)
  $serverPortLine = ($lines | Where-Object { $_ -match '^server port:i:' } | Select-Object -First 1)
  $usernameLine   = ($lines | Where-Object { $_ -match '^username:s:' } | Select-Object -First 1)

  $address = $null
  if ($addrLine) {
    $address = ($addrLine -replace '^(full address|alternate full address):s:', '').Trim()
  }

  $port = $null
  if ($serverPortLine) {
    $port = ($serverPortLine -replace '^server port:i:', '').Trim()
  }

  # Parse username and domain
  $parsedUser   = $null
  $parsedDomain = $null
  if ($usernameLine) {
    $raw = ($usernameLine -replace '^username:s:', '').Trim()
    if ($raw -match '^(.+)\\(.+)$') {
      # DOMAIN\user or .\user
      $parsedDomain = if ($Matches[1] -eq '.') { '' } else { $Matches[1] }
      $parsedUser   = $Matches[2]
    } else {
      $parsedUser   = $raw
      $parsedDomain = ''
    }
  }

  # IMPORTANT: do NOT use $host (reserved automatic variable). Use $targetHost instead.
  $targetHost = $address

  # Handle IPv6 like: [fe80::1]:3390
  if ($address -match '^\[(.+)\]:(\d+)$') {
    $targetHost = $Matches[1]
    $port = [int]$Matches[2]
  }
  # Handle hostname/IPv4:port (avoid naive IPv6 parsing)
  elseif ($address -match '^(.*):(\d+)$' -and $address -notmatch '^[^:]+::') {
    $targetHost = $Matches[1]
    $port = [int]$Matches[2]
  }

  if (-not $targetHost -or $targetHost -eq "") {
    throw "Could not determine host from RDP file: ${RdpFilePath}"
  }

  if (-not $port) { $port = 3389 }

  # Encode as host:port so non-default ports are preserved
  $endpoint = "$($targetHost):$port"

  [pscustomobject]@{
    Host     = $targetHost
    Port     = $port
    Endpoint = $endpoint
    Username = $parsedUser
    Domain   = $parsedDomain
  }
}

function Ensure-GroupNode {
  param(
    [xml]$Xml,
    [string]$Name
  )

  $group = @($Xml.RDCMan.file.group) | Where-Object { $_.properties.name -eq $Name } | Select-Object -First 1
  if ($group) { return $group }

  $groupNode = $Xml.CreateElement("group")
  $props     = $Xml.CreateElement("properties")
  $nameNode  = $Xml.CreateElement("name")
  $expNode   = $Xml.CreateElement("expanded")

  $nameNode.InnerText = $Name
  $expNode.InnerText  = "False"

  [void]$props.AppendChild($nameNode)
  [void]$props.AppendChild($expNode)
  [void]$groupNode.AppendChild($props)

  [void]$Xml.RDCMan.file.AppendChild($groupNode)
  return $groupNode
}

function Upsert-ServerNode {
  param(
    [xml]$Xml,
    [System.Xml.XmlElement]$Group,
    [string]$DisplayName,
    [string]$Endpoint,
    [string]$Username,
    [string]$Domain
  )

  $existing = @($Group.server) | Where-Object { $_.properties.displayName -eq $DisplayName } | Select-Object -First 1

  if ($existing) {
    $existing.properties.name = $Endpoint
    Set-LogonCredentials -Xml $Xml -ServerNode $existing -Username $Username -Domain $Domain
    return "Updated"
  }

  $serverNode  = $Xml.CreateElement("server")
  $props       = $Xml.CreateElement("properties")
  $nameNode    = $Xml.CreateElement("name")
  $displayNode = $Xml.CreateElement("displayName")

  $nameNode.InnerText    = $Endpoint
  $displayNode.InnerText = $DisplayName

  [void]$props.AppendChild($nameNode)
  [void]$props.AppendChild($displayNode)
  [void]$serverNode.AppendChild($props)

  [void]$Group.AppendChild($serverNode)
  Set-LogonCredentials -Xml $Xml -ServerNode $serverNode -Username $Username -Domain $Domain
  return "Created"
}

function Set-LogonCredentials {
  param(
    [xml]$Xml,
    [System.Xml.XmlElement]$ServerNode,
    [string]$Username,
    [string]$Domain
  )

  if ([string]::IsNullOrWhiteSpace($Username)) { return }

  # Remove any existing logonCredentials node
  $existing = $ServerNode.SelectSingleNode("logonCredentials")
  if ($existing) { [void]$ServerNode.RemoveChild($existing) }

  $credsNode   = $Xml.CreateElement("logonCredentials")
  $credsNode.SetAttribute("inherit", "None")

  $profileNode = $Xml.CreateElement("profileName")
  $profileNode.SetAttribute("scope", "Local")
  $profileNode.InnerText = "Custom"

  $userNode    = $Xml.CreateElement("userName")
  $userNode.InnerText = $Username

  $domainNode  = $Xml.CreateElement("domain")
  $domainNode.InnerText = $Domain

  $passNode    = $Xml.CreateElement("password")
  $passNode.SetAttribute("storeAsClearText", "False")

  [void]$credsNode.AppendChild($profileNode)
  [void]$credsNode.AppendChild($userNode)
  [void]$credsNode.AppendChild($domainNode)
  [void]$credsNode.AppendChild($passNode)
  [void]$ServerNode.AppendChild($credsNode)
}

# ----- Main -----

if (-not (Test-Path -LiteralPath $SourcePath)) {
  throw "Source path not found: ${SourcePath}"
}

if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
  throw "Failed to determine destination folder path."
}

$RdgPath = Join-Path $DestinationPath $RdgFileName

if (-not (Test-Path -LiteralPath $RdgPath)) {
  throw "RDG file not found: ${RdgPath}"
}

$rdpFiles = Get-ChildItem -LiteralPath $SourcePath -Filter *.rdp -File -ErrorAction Stop

if (-not $rdpFiles -or $rdpFiles.Count -eq 0) {
  Write-Host "No .rdp files found in: ${SourcePath}"
  return
}

Write-Host "Found $($rdpFiles.Count) .rdp file(s) in ${SourcePath}:"
$rdpFiles | ForEach-Object { Write-Host " - $($_.Name)" }

# Backup RDG before modifying
$backupPath = $RdgPath -replace '\.rdg$', (" (backup {0}).rdg" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))
Copy-Item -LiteralPath $RdgPath -Destination $backupPath -Force
Write-Host "Backup created: ${backupPath}"

# Load RDG XML
[xml]$xml = Get-Content -LiteralPath $RdgPath -Raw

# Ensure destination group exists
$groupNode = Ensure-GroupNode -Xml $xml -Name $GroupName

# Import each RDP file
$report = foreach ($f in $rdpFiles) {
  $displayName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  $endpointObj = Get-RdpEndpoint -RdpFilePath $f.FullName

  $action = Upsert-ServerNode -Xml $xml -Group $groupNode -DisplayName $displayName -Endpoint $endpointObj.Endpoint -Username $endpointObj.Username -Domain $endpointObj.Domain

  [pscustomobject]@{
    RdpFile      = $f.Name
    DisplayName  = $displayName
    Host         = $endpointObj.Host
    Port         = $endpointObj.Port
    RdgEndpoint  = $endpointObj.Endpoint
    Username     = $endpointObj.Username
    Domain       = $endpointObj.Domain
    Action       = $action
  }
}

Write-Host "`nPlanned changes:"
$report | Format-Table -AutoSize

if ($WhatIf) {
  Write-Host "`nWhatIf specified — not saving RDG."
  return
}

$xml.Save($RdgPath)
Write-Host "`nSaved updates to: ${RdgPath}"