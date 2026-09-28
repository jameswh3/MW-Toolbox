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

        # Get current state of the Fabric capacity
        try {
            Import-Module Az.Fabric -ErrorAction Stop
            $currentCapacity = Get-AzFabricCapacity -CapacityName $FabricName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        }
        catch {
            throw "Unable to retrieve Fabric capacity '$FabricName' in resource group '$ResourceGroupName': $($_.Exception.Message)"
        }

        $currentState = $currentCapacity.State

        Write-Host "Current Fabric capacity state: $currentState"

        # Check if we need to make a change
        if ($State -eq "Active" -and $currentState -eq "Active") {
            Write-Host "Fabric capacity is already active. No action needed."
        }
        elseif ($State -eq "Paused" -and $currentState -eq "Paused") {
            Write-Host "Fabric capacity is already paused. No action needed."
        }
        elseif ($State -eq "Active" -and $currentState -eq "Paused") {
            Write-Host "Resuming Fabric capacity..."
            Resume-AzFabricCapacity -CapacityName $FabricName -ResourceGroupName $ResourceGroupName
            Write-Host "Fabric capacity resumed successfully."
        }
        elseif ($State -eq "Paused" -and $currentState -eq "Active") {
            Write-Host "Suspending Fabric capacity..."
            Suspend-AzFabricCapacity -CapacityName $FabricName -ResourceGroupName $ResourceGroupName
            Write-Host "Fabric capacity suspended successfully."
        }
        else {
            Write-Host "Unexpected state: $currentState. Please check the capacity manually."
        }
    }