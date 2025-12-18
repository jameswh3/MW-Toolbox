#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Get-PowerPlatformAppsAndConnections {
    BEGIN {
        Add-PowerAppsAccount -Endpoint prod
        $environments=Get-AdminPowerAppEnvironment
        $powerAppsData=@()
    }
    PROCESS {
        foreach ($e in $environments) {
            $powerapps = Get-AdminPowerApp -EnvironmentName $e.EnvironmentName
            foreach ($pa in $powerapps) {
                $powerAppDatum = New-Object PSObject
                $powerAppDatum | Add-Member NoteProperty AppId($pa.AppName)
                $powerAppDatum | Add-Member NoteProperty AppName($pa.DisplayName)
                $powerAppDatum | Add-Member NoteProperty EnvironmentName($pa.EnvironmentName)
                $powerAppDatum | Add-Member NoteProperty LastModified($pa.LastModifiedTime)
                $powerAppDatum | Add-Member NoteProperty AppType($pa.Internal.appType)
                $powerAppDatum | Add-Member NoteProperty CreatedTime($pa.Internal.properties.createdTime)
                $powerAppDatum | Add-Member NoteProperty AppOwner($pa.Internal.properties.owner)
                $powerAppDatum | Add-Member NoteProperty AppVersion($pa.Internal.properties.appVersion)
                $powerAppDatum | Add-Member NoteProperty CanConsumeAppPass($pa.Internal.properties.canConsumeAppPass)
                $powerAppDatum | Add-Member NoteProperty AppPlanClassification($pa.Internal.properties.appPlanClassification)
                $powerAppDatum | Add-Member NoteProperty UsesPremiumApi($pa.Internal.properties.usesPremiumApi)
                $powerAppDatum | Add-Member NoteProperty UsesCustomApi($pa.Internal.properties.usesCustomApi)
                $powerAppDatum | Add-Member NoteProperty UsesOnPremiseGateway($pa.Internal.properties.usesOnPremiseGateway)
                $connectionReferenceNames=@()
                foreach ($cr in $pa.Internal.properties.connectionReferences) {
                    foreach ($conId in ($cr | Get-Member -MemberType NoteProperty).Name) {
                        $conDetails = $($cr.$conId)
                        $connectionReferenceNames+=$conDetails.displayName
                    } #foreach connection id in connection reference
                } #foreach connection reference
                $powerAppDatum | Add-Member NoteProperty connectionReferenceNames($connectionReferenceNames -join ",")
                $powerAppsData+=$powerAppDatum
            } #foreach powerapp
        } #foreach environment
    }
    END {
        return $powerAppsData
    }
}