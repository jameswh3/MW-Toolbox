<#
.SYNOPSIS
    Creates a self-signed certificate for Entra (Azure AD) app registration authentication.

.DESCRIPTION
    This script generates a self-signed certificate that can be used for certificate-based 
    authentication with Entra (Azure AD) app registrations. The certificate can be exported 
    to files and optionally installed in the local machine's certificate store.

.PARAMETER SubjectName
    The subject name for the certificate (e.g., "CN=MyAppName").
    Default: "CN=EntraAppCertificate"

.PARAMETER ValidityYears
    Number of years the certificate should be valid.
    Default: 2

.PARAMETER ExportPath
    Path where certificate files will be exported.
    Default: Current directory

.PARAMETER CertificateName
    Base name for the exported certificate files.
    Default: "EntraAppCert"

.PARAMETER InstallToStore
    Switch to install the certificate to the certificate store.
    Default: False

.PARAMETER StoreLocation
    Certificate store location (CurrentUser or LocalMachine).
    Default: CurrentUser

.PARAMETER Password
    Password to protect the .pfx file. If not provided, a secure password will be generated.

.EXAMPLE
    .\New-EntraAppCertificate.ps1
    Creates a certificate with default settings and exports to current directory.

.EXAMPLE
    .\New-EntraAppCertificate.ps1 -SubjectName "CN=MyApp" -ValidityYears 3 -InstallToStore
    Creates a certificate with custom subject name, 3-year validity, and installs to CurrentUser store.

.EXAMPLE
    .\New-EntraAppCertificate.ps1 -InstallToStore -StoreLocation LocalMachine
    Creates a certificate and installs it to LocalMachine store (requires admin rights).

.NOTES
    Author: MW-Toolbox
    Date: 2026-02-21
    
    Installing to LocalMachine store requires administrative privileges.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$SubjectName = "CN=EntraAppCertificate",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$ValidityYears = 2,

    [Parameter(Mandatory = $false)]
    [string]$ExportPath = "C:\temp",

    [Parameter(Mandatory = $false)]
    [string]$CertificateName = "EntraAppCert",

    [Parameter(Mandatory = $false)]
    [switch]$InstallToStore,

    [Parameter(Mandatory = $false)]
    [ValidateSet("CurrentUser", "LocalMachine")]
    [string]$StoreLocation = "CurrentUser",

    [Parameter(Mandatory = $false)]
    [securestring]$Password
)

# Function to generate a random password
function New-RandomPassword {
    param (
        [int]$Length = 16
    )
    $characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()'
    $password = -join ((1..$Length) | ForEach-Object { $characters[(Get-Random -Maximum $characters.Length)] })
    return $password
}

# Check if running as administrator when LocalMachine is specified
if ($StoreLocation -eq "LocalMachine" -and $InstallToStore) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "Installing to LocalMachine certificate store requires administrative privileges. Please run PowerShell as Administrator or use -StoreLocation CurrentUser."
        exit 1
    }
}

try {
    Write-Host "Creating self-signed certificate for Entra app registration..." -ForegroundColor Cyan
    
    # Calculate expiration date
    $expirationDate = (Get-Date).AddYears($ValidityYears)
    
    # Create the certificate
    $certParams = @{
        Subject           = $SubjectName
        CertStoreLocation = "Cert:\CurrentUser\My"
        KeyExportPolicy   = "Exportable"
        KeySpec           = "Signature"
        KeyLength         = 2048
        KeyAlgorithm      = "RSA"
        HashAlgorithm     = "SHA256"
        NotAfter          = $expirationDate
        Type              = "Custom"
        KeyUsage          = "DigitalSignature"
        TextExtension     = @("2.5.29.37={text}1.3.6.1.5.5.7.3.2") # Client Authentication
    }
    
    $cert = New-SelfSignedCertificate @certParams
    
    Write-Host "✓ Certificate created successfully" -ForegroundColor Green
    Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
    Write-Host "  Subject: $($cert.Subject)" -ForegroundColor Gray
    Write-Host "  Valid From: $($cert.NotBefore)" -ForegroundColor Gray
    Write-Host "  Valid To: $($cert.NotAfter)" -ForegroundColor Gray
    
    # Generate password if not provided
    if (-not $Password) {
        $generatedPassword = New-RandomPassword
        $Password = ConvertTo-SecureString -String $generatedPassword -Force -AsPlainText
        $showPassword = $true
    } else {
        $showPassword = $false
    }
    
    # Ensure export path exists
    if (-not (Test-Path $ExportPath)) {
        New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
    }
    
    # Export paths
    $pfxPath = Join-Path $ExportPath "$CertificateName.pfx"
    $cerPath = Join-Path $ExportPath "$CertificateName.cer"
    
    # Export the certificate with private key (.pfx)
    Write-Host "`nExporting certificate files..." -ForegroundColor Cyan
    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $Password | Out-Null
    Write-Host "✓ Private key exported to: $pfxPath" -ForegroundColor Green
    
    # Export the public key (.cer)
    Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null
    Write-Host "✓ Public key exported to: $cerPath" -ForegroundColor Green
    
    # Display password if it was generated
    if ($showPassword) {
        Write-Host "`n⚠ PFX Password (save this securely): $generatedPassword" -ForegroundColor Yellow
    }
    
    # Install to certificate store if requested
    if ($InstallToStore) {
        Write-Host "`nInstalling certificate to $StoreLocation store..." -ForegroundColor Cyan
        
        if ($StoreLocation -eq "LocalMachine") {
            # Import to LocalMachine
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
            $store.Open("ReadWrite")
            $store.Add($cert)
            $store.Close()
            Write-Host "✓ Certificate installed to LocalMachine\My store" -ForegroundColor Green
        } else {
            # Already in CurrentUser\My from creation
            Write-Host "✓ Certificate already available in CurrentUser\My store" -ForegroundColor Green
        }
    } else {
        Write-Host "`nℹ Certificate was created in CurrentUser\My store but not moved to persistent location." -ForegroundColor Yellow
        Write-Host "  To install later, import the .pfx file using Certificate Manager (certmgr.msc)" -ForegroundColor Gray
    }
    
    Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
    Write-Host "NEXT STEPS FOR ENTRA APP REGISTRATION:" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "1. Go to Azure Portal > Microsoft Entra ID > App registrations" -ForegroundColor White
    Write-Host "2. Select your app registration" -ForegroundColor White
    Write-Host "3. Navigate to 'Certificates & secrets'" -ForegroundColor White
    Write-Host "4. Click 'Upload certificate'" -ForegroundColor White
    Write-Host "5. Upload the .cer file: $cerPath" -ForegroundColor White
    Write-Host "6. Use the certificate thumbprint in your application: $($cert.Thumbprint)" -ForegroundColor White
    Write-Host ("=" * 80) -ForegroundColor Cyan
    
} catch {
    Write-Error "Failed to create certificate: $_"
    exit 1
} finally {
    # Clean up certificate from CurrentUser\My if not installing to store
    if (-not $InstallToStore -and $cert) {
        try {
            Get-ChildItem "Cert:\CurrentUser\My\$($cert.Thumbprint)" -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
        } catch {
            # Ignore cleanup errors
        }
    }
}
