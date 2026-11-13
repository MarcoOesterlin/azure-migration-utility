# Azure migration utility with defaults for non-coders
# It keeps prompts short and accepts Enter for the default answers.

$ErrorActionPreference = "Stop"

function Ask-Defaulted {
    param(
        [string]$Prompt,
        [string]$DefaultValue
    )

    $value = Read-Host "$Prompt [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultValue }
    return $value
}

function Get-SubscriptionChoice {
    param(
        [string]$Prompt,
        [string]$DefaultValue = ""
    )

    $subscriptions = Get-AzSubscription | Sort-Object Name
    if (-not $subscriptions) {
        throw "No Azure subscriptions were found for this account."
    }

    Write-Host ""
    Write-Host "Available subscriptions:"
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        $sub = $subscriptions[$i]
        Write-Host ("[{0}] {1} ({2})" -f $i, $sub.Name, $sub.Id)
    }

    if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
        $input = Read-Host $Prompt
    }
    else {
        $input = Read-Host "$Prompt [$DefaultValue]"
    }

    if ([string]::IsNullOrWhiteSpace($input)) {
        if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
            throw "A subscription selection is required."
        }
        return $DefaultValue
    }

    if ($input -match '^\d+$') {
        $index = [int]$input
        if ($index -ge 0 -and $index -lt $subscriptions.Count) {
            return $subscriptions[$index].Id
        }
    }

    $match = $subscriptions | Where-Object { $_.Name -eq $input -or $_.Id -eq $input }
    if ($match) {
        return $match[0].Id
    }

    throw "Subscription '$input' was not found. Use a number from the list or an exact subscription name/ID."
}

Write-Host "Azure Migration Utility (defaults mode)"
Write-Host "--------------------------------------"

if (-not (Get-AzContext)) { Connect-AzAccount }

$SourceSub = Get-SubscriptionChoice -Prompt "Select source subscription" -DefaultValue "<source-subscription-id>"
$SourceRG  = Ask-Defaulted "Source resource group" "<source-resource-group>"
$DestSub   = Get-SubscriptionChoice -Prompt "Select destination subscription" -DefaultValue "<destination-subscription-id>"
$DestRG    = Ask-Defaulted "Destination resource group" "<destination-resource-group>"
$Mode      = Ask-Defaulted "Move mode [All/Selected/Preview]" "All"

Write-Host ""
Write-Host "Source:      $SourceSub / $SourceRG"
Write-Host "Destination: $DestSub / $DestRG"
Write-Host "Mode:        $Mode"
Write-Host ""

if (-not (Get-AzContext)) { Connect-AzAccount }
Set-AzContext -SubscriptionId $SourceSub | Out-Null

$resources = Get-AzResource -ResourceGroupName $SourceRG -ErrorAction Stop

if ($Mode -eq "Preview" -or $Mode -eq "preview") {
    $resources | Select-Object Name, ResourceType, Location | Format-Table -AutoSize
    Write-Host "Preview only. Nothing was moved."
    exit 0
}

if ($Mode -eq "All" -or $Mode -eq "all") {
    $toMove = $resources
} elseif ($Mode -eq "Selected" -or $Mode -eq "selected") {
    $selected = Read-Host "Comma-separated resource numbers to move (example: 0,2,5)"
    $numbers = $selected.Split(',') | ForEach-Object { $_.Trim() }
    $toMove = @()
    foreach ($n in $numbers) {
        if ($n -match '^\d+$') {
            $idx = [int]$n
            if ($idx -ge 0 -and $idx -lt $resources.Count) {
                $toMove += $resources[$idx]
            }
        }
    }
} else {
    throw "Unsupported mode: $Mode"
}

if (-not $toMove) {
    throw "No resources selected for move."
}

$moveNow = Read-Host "Move these resources now? [Y/N]"
if ($moveNow -notmatch '^(Y|y|YES|yes)$') {
    Write-Host "Stopped before moving resources."
    exit 0
}

Move-AzResource -DestinationSubscriptionId $DestSub -DestinationResourceGroupName $DestRG -ResourceId ($toMove | ForEach-Object { $_.ResourceId }) -Force

$deleteRG = Read-Host "Delete old RG '$SourceRG'? [Y/N]"
if ($deleteRG -match '^(Y|y|YES|yes)$') {
    Remove-AzResourceGroup -Name $SourceRG -Force
    Write-Host "Old resource group deleted."
}
