function Get-BillingPlansViaAPI {
    <#
    .SYNOPSIS
        Retrieves billing plans for a Power Platform tenant via the Power Platform Licensing API.
    .DESCRIPTION
        Uses the Power Platform Licensing REST API to list all billing plans for the tenant.
        Handles pagination automatically via @odata.nextLink.
        Reference: https://learn.microsoft.com/en-us/rest/api/power-platform/licensing/billing-policy/list-billing-policies

        REQUIRED PERMISSIONS:
        The app registration must be assigned one of the following roles in Power Platform Admin Center:
          - Power Platform Administrator
          - Dynamics 365 Administrator
          - Global Administrator
        The app registration also needs admin-consented application permissions for
        https://api.powerplatform.com (scope: https://api.powerplatform.com/.default).
    .PARAMETER ClientId
        The Azure AD application (client) ID used for authentication.
    .PARAMETER ClientSecret
        The client secret for the Azure AD application.
    .PARAMETER TenantDomain
        The tenant domain (e.g., contoso.onmicrosoft.com) used to obtain the access token.
    .PARAMETER Top
        Optional. Maximum number of billing plans to return per page.
    .EXAMPLE
        Get-BillingPlansViaAPI -ClientId "your-client-id" -ClientSecret "your-secret" -TenantDomain "contoso.onmicrosoft.com"
    .EXAMPLE
        Get-BillingPlansViaAPI -ClientId "your-client-id" -ClientSecret "your-secret" -TenantDomain "contoso.onmicrosoft.com" -Top 10
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Enter the Azure AD application client ID")]
        [string]$ClientId,

        [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Enter the client secret for authentication")]
        [string]$ClientSecret,

        [Parameter(Mandatory = $true, Position = 2, HelpMessage = "Enter your tenant domain (e.g., contoso.onmicrosoft.com)")]
        [string]$TenantDomain,

        [Parameter(Mandatory = $false, HelpMessage = "Maximum number of billing plans to return per page")]
        [int]$Top
    )
    BEGIN {
        $apiVersion = "2022-03-01-preview"
        $baseUrl = "https://api.powerplatform.com/licensing/billingPolicies"
        $allResults = @()

        Write-Host "Authenticating with tenant: $TenantDomain" -ForegroundColor Cyan

        try {
            $tokenUrl = "https://login.microsoftonline.com/$TenantDomain/oauth2/v2.0/token"
            $token = Invoke-RestMethod -Uri $tokenUrl `
                -Method Post `
                -Body @{
                    grant_type    = "client_credentials"
                    client_id     = $ClientId
                    client_secret = $ClientSecret
                    scope         = "https://api.powerplatform.com/.default"
                } `
                -ContentType 'application/x-www-form-urlencoded'

            Write-Host "Authentication successful" -ForegroundColor Green
        }
        catch {
            Write-Host "Authentication failed: $_" -ForegroundColor Red
            return
        }
    }
    PROCESS {
        try {
            # Build initial request URI
            $queryParams = "api-version=$apiVersion"
            if ($Top -gt 0) {
                $queryParams += "&`$top=$Top"
            }
            $nextLink = "$baseUrl`?$queryParams"

            # Paginate through all results
            do {
                Write-Host "Retrieving billing plans from: $nextLink" -ForegroundColor Cyan

                $response = Invoke-RestMethod -Uri $nextLink `
                    -Method Get `
                    -Headers @{ Authorization = "Bearer $($token.access_token)" } `
                    -ContentType 'application/json'

                if ($response.value) {
                    Write-Host "Retrieved $($response.value.Count) billing plan(s)" -ForegroundColor Green
                    $allResults += $response.value
                }

                $nextLink = $response.'@odata.nextLink'
            } while ($nextLink)
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq 403) {
                Write-Host "Error retrieving billing plans: 403 Forbidden." -ForegroundColor Red
                Write-Host "The app registration may lack the required permissions. Ensure the service principal has been assigned the 'Power Platform Administrator', 'Dynamics 365 Administrator', or 'Global Administrator' role in the Power Platform Admin Center, and that admin consent has been granted for the https://api.powerplatform.com scope in Azure AD." -ForegroundColor Yellow
            }
            else {
                Write-Host "Error retrieving billing plans: $_" -ForegroundColor Red
            }
        }
    }
    END {
        Write-Host "`nFinished retrieving billing plans. Total found: $($allResults.Count)" -ForegroundColor Cyan
        return $allResults
    }
}
