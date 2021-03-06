
$staleThresholdInDays = Get-VstsInput -Name staleThresholdInDays -Require
$organization = Get-VstsInput -Name Organization -Require
$areaPath = Get-VstsInput -Name AreaPath -Require
$PatToken = Get-VstsInput -Name PatToken -Require

$exemptTags = @('security', 'pinned')
$witTypeSupported = "('Feature','Task','User Story', 'Bug')"
$staleTagText = "ProAct : stale"
$staleCommentText = "This work item has been automatically marked as stale (tag => $staleTagText) because there has been no activity in last $staleThresholdInDays days. This work item will be closed if tag => $staleTagText is not removed within $daysUntilClose days."

# variable reading above this line

function MarkWitAsStale {
    param (
        $organization,
        $staleWits,
        $exemptTags,
        $staleTagText,
        $staleCommentText
    )
    $updatedStaleWits = @()
    foreach ($staleWit in $staleWits) {
        # get current tags in staleWit
        [String]$staleWitId = $staleWit.fields | Select-Object -ExpandProperty System.Id
        [String]$staleWitTags = ""

        # check to verify if System.Tags is present in the staleWit.fields
        if ([bool]($staleWit.fields.PSobject.Properties.name -match "System.Tags")) {
            [String]$staleWitTags = $staleWit.fields | Select-Object -ExpandProperty System.Tags
            $staleWitTags += "; "
        }

        # We do not update a staleWit if it contains any of the exempted tags
        $exemptTagFlag = $false;
        foreach ($exemptTag in $exemptTags) {
            if ($staleWitTags -like "*$($exemptTag)*") {
                $exemptTagFlag = $true
                break;
            }
        }

        if ($exemptTagFlag) {
            continue;
        }

        # Add staleTagText if staleWitTags doesn't already contain the staleTag
        if (-Not ($staleWitTags -like "*$($staleTagText)*" )) {
            $staleWitTags += "$($staleTagText)"
            # update WIT with new tags and comment
            $ignoreOutput = az boards work-item update --id $staleWitId --fields -f System.Tags=$staleWitTags --discussion $staleCommentText --org $organization
            $updatedStaleWits += $staleWit
        }
    }

    return $updatedStaleWits
}

# region install devops extension if missing

$extensions = az extension list -o json | ConvertFrom-Json

$devopsFound = $False
foreach($extension in $extensions)
{
    if($extension.name -eq 'azure-devops'){
        $devopsFound = $True
    }
}

if ($devopsFound -eq $False){
    az extension add -n azure-devops
}

$Env:AZURE_DEVOPS_EXT_PAT = $PatToken

# end region install extension

# region mark work items as stale

$staleWitWiqlQuery = "select [System.Id], [System.WorkItemType], [System.Title], [System.AssignedTo], [System.ChangedDate], [System.State], [System.Tags] from WorkItems where [System.WorkItemType] IN $($witTypeSupported) and not [System.State] in ('Closed', 'Resolved', 'Completed', 'Cut') AND [System.Tags] NOT CONTAINS '$staleTagText' AND [System.AreaPath] = '$areaPath' AND [System.ChangedDate] < @today - $staleThresholdInDays ORDER BY [System.ChangedDate] ASC"
Write-Host "Query used"
Write-Host $staleWitWiqlQuery
$staleWits = az boards query --wiql $staleWitWiqlQuery --org $organization -o json | ConvertFrom-Json

MarkWitAsStale $organization $staleWits $exemptTags $staleTagText $staleCommentText


# endregion