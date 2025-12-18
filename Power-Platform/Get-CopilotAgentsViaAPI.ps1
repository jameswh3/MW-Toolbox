
function Get-CopilotAgentsViaAPI {
    [CmdletBinding(DefaultParameterSetName='SingleOrg')]
    param (
        [Parameter(Mandatory=$true, Position=0, HelpMessage="Enter the Azure AD application client ID")]
        [string]$ClientId,
        
        [Parameter(Mandatory=$true, Position=1, HelpMessage="Enter the client secret for authentication")]
        [string]$ClientSecret,
        
        [Parameter(Mandatory=$true, Position=2, ParameterSetName='SingleOrg', HelpMessage="Enter your Dynamics 365 organization URL (e.g., contoso.crm.dynamics.com)")]
        [string]$OrgUrl,
        
        [Parameter(Mandatory=$true, Position=3, HelpMessage="Enter your tenant domain (e.g., contoso.onmicrosoft.com)")]
        [string]$TenantDomain,
        
        [Parameter(Mandatory=$false, HelpMessage="Specify additional fields to retrieve")]
        [string[]]$FieldList="botid,applicationmanifestinformation,componentidunique,name,configuration,createdon,publishedon,_ownerid_value,_createdby_value,solutionid,modifiedon,_owninguser_value,schemaname,_modifiedby_value,_publishedby_value,authenticationmode,synchronizationstatus,ismanaged",
        
        [Parameter(Mandatory=$true, ParameterSetName='AllOrgs', HelpMessage="Process all Power Platform environments")]
        [switch]$AllEnvironments
    )
    BEGIN {
        $allResults = @()
        
        if ($AllEnvironments) {
            Write-Host "Retrieving all Power Platform environments..." -ForegroundColor Cyan
            $environments = Get-AdminPowerAppEnvironment
            $orgUrls = @()
            
            foreach ($env in $environments) {
                $envOrgUrl = $env.Internal.properties.linkedEnvironmentMetadata.instanceUrl
                if ($envOrgUrl) {
                    $envOrgUrl = $envOrgUrl -replace "https://", "" -replace "/", ""
                    $orgUrls += @{
                        Url = $envOrgUrl
                        Name = $env.DisplayName
                    }
                }
            }
            
            Write-Host "Found $($orgUrls.Count) environment(s) to process" -ForegroundColor Green
        } else {
            $orgUrls = @(@{Url = $OrgUrl; Name = $null})
        }
    }
    PROCESS {
        foreach ($envInfo in $orgUrls) {
            $currentOrgUrl = $envInfo.Url
            $envName = $envInfo.Name
            
            if ($currentOrgUrl.StartsWith("https://")) {
                $currentOrgUrl = $currentOrgUrl.Substring(8)
            }
            
            if ($envName) {
                Write-Host "`nConnecting to environment: $envName (https://$currentOrgUrl)" -ForegroundColor Cyan
            } else {
                Write-Host "`nConnecting to environment: https://$currentOrgUrl" -ForegroundColor Cyan
            }
            Write-Host "Authenticating with tenant: $TenantDomain" -ForegroundColor Cyan
            
            try {
                $tokenUrl = "https://login.microsoftonline.com/$TenantDomain/oauth2/v2.0/token"
                $token = Invoke-RestMethod -Uri $tokenUrl `
                    -Method Post `
                    -Body @{grant_type="client_credentials"; client_id="$ClientId"; client_secret="$ClientSecret"; scope="https://$currentOrgUrl/.default"} `
                    -ContentType 'application/x-www-form-urlencoded'
                
                Write-Host "Authentication successful" -ForegroundColor Green
                
                if ($envName) {
                    Write-Host "Processing bots in environment: $envName (https://$currentOrgUrl)" -ForegroundColor Cyan
                } else {
                    Write-Host "Processing bots in environment: https://$currentOrgUrl" -ForegroundColor Cyan
                }
                
                #get list of agents/copilots/bots
                <#
                $response=Invoke-RestMethod -Uri "https://$currentOrgUrl/api/data/v9.2/bots?`$select=$FieldList" `
                    -Headers @{Authorization = "Bearer $($token.access_token)"}
                #>
                $response=Invoke-RestMethod -Uri "https://$currentOrgUrl/api/data/v9.2/bots" `
                    -Headers @{Authorization = "Bearer $($token.access_token)"}
                
                Write-Host "Found $($response.value.Count) bot(s)" -ForegroundColor Green
                $allResults += $response.value
            }
            catch {
                if ($envName) {
                    Write-Host "Error processing environment $envName (https://$currentOrgUrl): $_" -ForegroundColor Red
                } else {
                    Write-Host "Error processing environment https://$currentOrgUrl : $_" -ForegroundColor Red
                }
            }
        }
    }
    END {
        Write-Host "`nFinished processing all environments. Total bots found: $($allResults.Count)" -ForegroundColor Cyan
        return $allResults
    }
}