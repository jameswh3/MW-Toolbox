    function Set-FabricCapacityState {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [string]$FabricName,
            
            [Parameter(Mandatory = $true)]
            [string]$ResourceGroupName,
            
            [Parameter(Mandatory = $false)]
            [ValidateSet("Active", "Paused")]
            [string]$State
        )

        # If state is not provided, prompt user for desired state
        if (-not $State) {
            Write-Host "Select Fabric capacity state:"
            Write-Host "1. Active (Resume capacity) [Default]"
            Write-Host "2. Paused (Suspend capacity)"
            $choice = Read-Host "Enter your choice (1 or 2, press Enter for default)"

            # Set default to Active if no input provided
            if ([string]::IsNullOrWhiteSpace($choice)) {
                $choice = "1"
            }

            $State = if ($choice -eq "1") { "Active" } else { "Paused" }
        }

        if (-not (Get-Module -ListAvailable -Name Az.Fabric)) {
            Write-Host "Az.Fabric is not installed. Installing it for the current user..."
            try {
                Install-Module -Name Az.Fabric `
                    -Repository PSGallery `
                    -Scope CurrentUser `
                    -Force `
                    -AllowClobber `
                    -AcceptLicense `
                    -ErrorAction Stop
            }
            catch {
                throw "Unable to install the required Az.Fabric module: $($_.Exception.Message)"
            }
        }

        if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
            Write-Host "Az.Accounts is not installed. Installing it for the current user..."
            try {
                Install-Module -Name Az.Accounts `
                    -Repository PSGallery `
                    -Scope CurrentUser `
                    -Force `
                    -AllowClobber `
                    -AcceptLicense `
                    -ErrorAction Stop
            }
            catch {
                throw "Unable to install the required Az.Accounts module: $($_.Exception.Message)"
            }
        }

        $accountsImported = $false
        $accountsImportErrors = [System.Collections.Generic.List[string]]::new()
        $accountsVersions = Get-Module -ListAvailable -Name Az.Accounts |
            Sort-Object Version -Descending -Unique

        foreach ($accountsModule in $accountsVersions) {
            $missingAssemblies = @(
                foreach ($requiredAssembly in $accountsModule.RequiredAssemblies) {
                    $assemblyPath = if ([IO.Path]::IsPathRooted($requiredAssembly)) {
                        $requiredAssembly
                    }
                    else {
                        Join-Path $accountsModule.ModuleBase $requiredAssembly
                    }

                    if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
                        $requiredAssembly
                    }
                }
            )

            if ($missingAssemblies.Count -gt 0) {
                $accountsImportErrors.Add("$($accountsModule.Version): missing $($missingAssemblies -join ', ')")
                continue
            }

            try {
                Import-Module -FullyQualifiedName @{
                    ModuleName      = "Az.Accounts"
                    RequiredVersion = $accountsModule.Version
                } -ErrorAction Stop
                $accountsImported = $true
                break
            }
            catch {
                $accountsImportErrors.Add("$($accountsModule.Version): $($_.Exception.Message)")
            }
        }

        if (-not $accountsImported) {
            throw "Unable to import any installed Az.Accounts version. $($accountsImportErrors -join ' | ')"
        }

        try {
            Import-Module Az.Fabric -ErrorAction Stop
        }
        catch {
            throw "Unable to import the required Az.Fabric module: $($_.Exception.Message)"
        }

        try {
            $currentCapacity = Get-AzFabricCapacity -CapacityName $FabricName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
            $currentState = $currentCapacity.State
        }
        catch {
            throw "Unable to retrieve Fabric capacity '$FabricName' in resource group '$ResourceGroupName': $($_.Exception.Message)"
        }

        Write-Host "Current Fabric capacity state: $currentState"

        if ($State -eq "Active" -and $currentState -eq "Active") {
            Write-Host "Fabric capacity is already active. No action needed."
            return
        }

        if ($State -eq "Paused" -and $currentState -eq "Paused") {
            Write-Host "Fabric capacity is already paused. No action needed."
            return
        }

        if ($currentState -notin "Active", "Paused") {
            throw "Fabric capacity '$FabricName' returned unexpected state '$currentState'. Check the capacity in the Azure portal."
        }

        $operation = if ($State -eq "Active") { "resume" } else { "suspend" }
        $operationLabel = if ($State -eq "Active") { "Resuming" } else { "Suspending" }
        Write-Host "$operationLabel Fabric capacity..."

        try {
            if ($State -eq "Active") {
                Resume-AzFabricCapacity -CapacityName $FabricName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
            }
            else {
                Suspend-AzFabricCapacity -CapacityName $FabricName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
            }
        }
        catch {
            throw "Unable to $operation Fabric capacity '$FabricName' in resource group '$ResourceGroupName': $($_.Exception.Message)"
        }

        $completedAction = if ($State -eq "Active") { "resume requested" } else { "suspension requested" }
        Write-Host "Fabric capacity $completedAction successfully."
    }
