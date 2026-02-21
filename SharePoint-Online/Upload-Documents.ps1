# PowerShell script to upload documents to specified SharePoint sites and libraries using an input array

# Prerequisites:
# - Install-Module -Name PnP.PowerShell
# - You must have permission to upload to the SharePoint sites

# Example input array
$documents = get-childitem -Path "C:\temp\output"

$siteUrl = "https://m365cpi89108028.sharepoint.com/sites/DemoData"
$library = "Movies"

Connect-PnPOnline -Url $siteUrl `
            -ClientId $env.SHAREPOINT_ONLINE_CLIENT_ID `
            -Tenant $env.SHAREPOINT_ONLINE_TENANT `
            -CertificatePath $env.SHAREPOINT_ONLINE_CERTIFICATE_PATH

foreach ($doc in $documents) {
    $filePath = $doc.FullName


    if (Test-Path $filePath) {
        Write-Host "Uploading $filePath to $siteUrl/$library..."

        # Upload the file to the specified library
        Add-PnPFile -Path $filePath -Folder $library

        
    } else {
        Write-Host "Skipping $filePath--file does not exist."
    }
}

# Disconnect after upload
        Disconnect-PnPOnline