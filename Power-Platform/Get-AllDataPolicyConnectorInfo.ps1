$module = Get-Module -ListAvailable Microsoft.PowerApps.Administration.PowerShell |
    Sort-Object Version -Descending |
    Select-Object -First 1
Import-Module $module.Path -UseWindowsPowerShell

function Get-AllDataPolicyConnectorInfo {
    BEGIN {
        Add-PowerAppsAccount -Endpoint prod
        $environments=get-AdminPowerAppEnvironment
        $dataPolicies=Get-AdminDlpPolicy
        $dataPolicyData=@()
    }
    PROCESS {
        foreach ($dp in $dataPolicies) {
            #capture DisplayName, PolicyName, Constraints, and Environments
            $dataPolicyName = $dp.DisplayName
            $dataPolicyId = $dp.PolicyName

            #foreach environment in the policy, get the environment name and id
            $environments = ($dp.Environments.Name) -join ","

            #foreach connector in businessdatagroups, get the connector name and id and flag as business data group
            foreach ($dg in $dp.BusinessDataGroup) {
                $dataPolicyDatum= New-Object PSObject
                $dataPolicyDatum | Add-Member NoteProperty PolicyName($dataPolicyName)
                $dataPolicyDatum | Add-Member NoteProperty PolicyId($dataPolicyId)
                $dataPolicyDatum | Add-Member NoteProperty Environments($environments)
                $dataPolicyDatum | Add-Member NoteProperty ConnectorName($dg.Name)
                $dataPolicyDatum | Add-Member NoteProperty ConnectorId($dg.Id)
                $dataPolicyDatum | Add-Member NoteProperty DataGroup("Business Data Group")
                $dataPolicyData+=$dataPolicyDatum
            }
            #foreach connector in non-businessdatagroup, get the connector name and id and flag as business data group
            foreach ($dg in $dp.NonBusinessDataGroup) {
                $dataPolicyDatum= New-Object PSObject
                $dataPolicyDatum | Add-Member NoteProperty PolicyName($dataPolicyName)
                $dataPolicyDatum | Add-Member NoteProperty PolicyId($dataPolicyId)
                $dataPolicyDatum | Add-Member NoteProperty Environments($environments)
                $dataPolicyDatum | Add-Member NoteProperty ConnectorName($dg.Name)
                $dataPolicyDatum | Add-Member NoteProperty ConnectorId($dg.Id)
                $dataPolicyDatum | Add-Member NoteProperty DataGroup("Non Business Data Group")
                $dataPolicyData+=$dataPolicyDatum
            }
            #foreach connector in businessdatagroups, get the connector name and id and flag as business data group
            foreach ($dg in $dp.BlockedGroup) {
                $dataPolicyDatum= New-Object PSObject
                $dataPolicyDatum | Add-Member NoteProperty PolicyName($dataPolicyName)
                $dataPolicyDatum | Add-Member NoteProperty PolicyId($dataPolicyId)
                $dataPolicyDatum | Add-Member NoteProperty Environments($environments)
                $dataPolicyDatum | Add-Member NoteProperty ConnectorName($dg.Name)
                $dataPolicyDatum | Add-Member NoteProperty ConnectorId($dg.Id)
                $dataPolicyDatum | Add-Member NoteProperty DataGroup("Blocked")
                $dataPolicyData+=$dataPolicyDatum
            }
        }
    }
    END {
        return $dataPolicyData
    }
}