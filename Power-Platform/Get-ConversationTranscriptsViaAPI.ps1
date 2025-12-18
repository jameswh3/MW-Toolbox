function Get-ConversationTranscriptsViaAPI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0, HelpMessage="Enter the Azure AD application client ID")]
        [string]$ClientId,
        
        [Parameter(Mandatory=$true, Position=1, HelpMessage="Enter the client secret for authentication")]
        [string]$ClientSecret,
        
        [Parameter(Mandatory=$true, Position=2, HelpMessage="Enter your Dynamics 365 organization URL (e.g., contoso.crm.dynamics.com)")]
        [string]$OrgUrl,
        
        [Parameter(Mandatory=$true, Position=3, HelpMessage="Enter your tenant domain (e.g., contoso.onmicrosoft.com)")]
        [string]$TenantDomain,
        
        [Parameter(Mandatory=$false, HelpMessage="Specify specific fields to retrieve. If not specified, all fields are returned.")]
        [string[]]$FieldList,

        [Parameter(Mandatory=$false, HelpMessage="Start date for filtering conversation transcripts (format: yyyy-MM-dd)")]
        [datetime]$StartDate,

        [Parameter(Mandatory=$false, HelpMessage="End date for filtering conversation transcripts (format: yyyy-MM-dd)")]
        [datetime]$EndDate
    )
    BEGIN {
        $tokenUrl = "https://login.microsoftonline.com/$TenantDomain/oauth2/v2.0/token"
        $token = Invoke-RestMethod -Uri $tokenUrl `
            -Method Post `
            -Body @{grant_type="client_credentials"; client_id="$ClientId"; client_secret="$ClientSecret"; scope="https://$OrgUrl/.default"} `
            -ContentType 'application/x-www-form-urlencoded'
    }
    PROCESS {
        # Build the base URI
        $baseUri = "https://$OrgUrl/api/data/v9.2/conversationtranscripts"
        
        # Build query parameters
        $queryParams = @()
        
        # Add field selection if specified
        if ($FieldList -and $FieldList.Count -gt 0) {
            $fieldsString = $FieldList -join ','
            $queryParams += "`$select=$fieldsString"
        }
        
        # Add date filter if specified
        if ($StartDate -and $EndDate) {
            $queryParams += "`$filter=createdon ge $($StartDate.ToString("yyyy-MM-dd")) and createdon le $($EndDate.ToString("yyyy-MM-dd"))"
        }
        
        # Construct full URI
        if ($queryParams.Count -gt 0) {
            $uri = "$baseUri`?$($queryParams -join '&')"
        } else {
            $uri = $baseUri
        }
        
        # Get list of conversation transcripts
        $response = Invoke-RestMethod -Uri $uri -Headers @{Authorization = "Bearer $($token.access_token)"}
    }
    END {
        return $response.value
    }
}