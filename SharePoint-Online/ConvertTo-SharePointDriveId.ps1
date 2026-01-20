
function ConvertTo-SharePointDriveId {
    param (
        [Parameter(Mandatory=$true)]
        [string]$siteId,
        [Parameter(Mandatory=$true)]
        [string]$webId,
        [Parameter(Mandatory=$true)]
        [string]$listId
    )
    
    $siteIdGuid = [Guid]$siteId
    $webIdGuid = [Guid]$webId
    $listIdGuid = [Guid]$listId
    
    $bytes = $siteIdGuid.ToByteArray() + $webIdGuid.ToByteArray() + $listIdGuid.ToByteArray()
    $driveId = "b!" + ([Convert]::ToBase64String($bytes)).Replace('/','_').Replace('+','-') 
    
    return $driveId
}