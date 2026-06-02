# Function to load .env file if environment variables are not set
function Import-DotEnv {
    param(
        [string]$Path = (Join-Path (Get-Location).Path ".env")
    )
    
    if (Test-Path $Path) {
        Get-Content $Path | ForEach-Object {
            if ($_ -match '^([^#][^=]+)=(.*)$') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                # Remove quotes if present
                $value = $value -replace '^["'']|["'']$', ''
                [Environment]::SetEnvironmentVariable($name, $value, [EnvironmentVariableTarget]::Process)
            }
        }
        Write-Host "Loaded environment variables from .env file" -ForegroundColor Green
    } else {
        Write-Warning ".env file not found at $Path"
    }
}

# If script is run directly (not dot-sourced), execute the function
if ($MyInvocation.InvocationName -ne '.') {
    Import-DotEnv
}
