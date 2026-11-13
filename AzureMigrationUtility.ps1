# Azure Resource Group Move + Cleanup Utility
# Run in Azure Cloud Shell or PowerShell with Az modules installed.
# This script does NOT delete anything without confirmation.

$ErrorActionPreference = "Stop"

function Confirm-Action {
    param([string]$Message)
    $answer = Read-Host "$Message (y/N)"
    return $answer -match '^(y|yes)$'
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

function Get-ModeSelection {
    param([string]$SourceRG, [string]$SourceSub)

    Write-Host ""
    Write-Host "Source subscription: $SourceSub"
    Write-Host "Source resource group: $SourceRG"
    Write-Host ""

    $items = Get-AzResource -ResourceGroupName $SourceRG -ErrorAction Stop | Sort-Object Name
    if (-not $items) {
        throw "No resources found in resource group '$SourceRG'."
    }

    Write-Host "Available resources:"
    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        Write-Host ("[{0}] {1} ({2})" -f $i, $item.Name, $item.ResourceType)
    }

    Write-Host ""
    Write-Host "Choose move mode:"
    Write-Host "  1 = All resources"
    Write-Host "  2 = Selected resources"
    Write-Host "  3 = Preview only"
    $mode = Read-Host "Enter 1, 2, or 3"

    switch ($mode) {
        "1" { return @("ALL") }
        "2" {
            $selection = Read-Host "Enter comma-separated numbers to move (example: 0,2,5)"
            if ([string]::IsNullOrWhiteSpace($selection)) {
                throw "No selection entered."
            }
            $selected = @()
            $numbers = $selection.Split(',') | ForEach-Object { $_.Trim() }
            foreach ($n in $numbers) {
                if ($n -match '^\d+$') {
                    $idx = [int]$n
                    if ($idx -ge 0 -and $idx -lt $items.Count) {
                        $selected += $items[$idx]
                    } else {
                        throw "Invalid index: $n"
                    }
                } else {
                    throw "Invalid selection: $n"
                }
            }
            return $selected
        }
        "3" {
            return @("PREVIEW")
        }
        default {
            throw "Invalid mode selected."
        }
    }
}

function Move-Resources {
    param(
        [string]$DestinationSub,
        [string]$DestinationRG,
        [object[]]$Resources
    )

    if ($Resources.Count -eq 0) {
        throw "No resources selected for move."
    }

    $resourceIds = $Resources | ForEach-Object { $_.ResourceId }

    Write-Host ""
    Write-Host "Moving resources to subscription '$DestinationSub' / RG '$DestinationRG'..."
    foreach ($rid in $resourceIds) {
        Write-Host " - $rid"
    }

    Move-AzResource `
        -DestinationSubscriptionId $DestinationSub `
        -DestinationResourceGroupName $DestinationRG `
        -ResourceId $resourceIds `
        -Force

    Write-Host "Move completed."
}

Write-Host "Azure Resource Location Migration Utility"
Write-Host "--------------------------------------"

if (-not (Get-AzContext)) {
    Connect-AzAccount
}

$SourceSub = Get-SubscriptionChoice -Prompt "Select SOURCE subscription"
$SourceRG  = Read-Host "Enter SOURCE resource group name"
$DestSub   = Get-SubscriptionChoice -Prompt "Select DESTINATION subscription"
$DestRG    = Read-Host "Enter DESTINATION resource group name"

Set-AzContext -SubscriptionId $SourceSub | Out-Null

$selection = Get-ModeSelection -SourceRG $SourceRG -SourceSub $SourceSub

if ($selection[0] -eq "PREVIEW") {
    $previewResources = Get-AzResource -ResourceGroupName $SourceRG | Sort-Object Name
    $previewResources | Select-Object Name, ResourceType, ResourceGroupName, Location | Format-Table -AutoSize
    Write-Host ""
    Write-Host "Preview only. No resources were moved."
    exit 0
}

if ($selection[0] -eq "ALL") {
    $resourcesToMove = Get-AzResource -ResourceGroupName $SourceRG | Sort-Object Name
} else {
    $resourcesToMove = @($selection)
}

Write-Host ""
Write-Host "This will move the following resources:"
$resourcesToMove | Select-Object Name, ResourceType | Format-Table -AutoSize

if (-not (Confirm-Action "Proceed with the move?")) {
    Write-Host "Stopped before moving resources."
    exit 0
}

Move-Resources -DestinationSub $DestSub -DestinationRG $DestRG -Resources $resourcesToMove

if (Confirm-Action "Delete the old resource group '$SourceRG' after the move?") {
    $remaining = Get-AzResource -ResourceGroupName $SourceRG -ErrorAction SilentlyContinue
    if ($remaining) {
        Write-Host "Old RG still contains resources. Delete them first or move them."
        $remaining | Select-Object Name, ResourceType | Format-Table -AutoSize
        exit 1
    }

    if (-not (Confirm-Action "Final confirmation: delete RG '$SourceRG'?")) {
        Write-Host "RG deletion cancelled."
        exit 0
    }

    Remove-AzResourceGroup -Name $SourceRG -Force
    Write-Host "Resource group '$SourceRG' deleted."
}

if (Confirm-Action "Delete the old subscription '$SourceSub'?") {
    Write-Host ""
    Write-Host "IMPORTANT: Azure subscription deletion is a final step and should be done only after the RG is empty and no locks/policies remain."
    Write-Host "For safety, use the Azure Portal or the CLI command below:"
    Write-Host "  az account set --subscription '$SourceSub'"
    Write-Host "  az account delete"
    Write-Host "If a direct deletion fails, the portal will usually tell you why (resource leftovers, locks, billing, policies, etc.)."
}

if (Confirm-Action "Rename a Fabric capacity?") {
    Write-Host ""
    Write-Host "Fabric capacity renames are usually done in the Fabric Admin portal or via the supported Fabric admin API."
    Write-Host "This script keeps that step separate because rename behavior differs by tenant and API version."
    $FabricCapacityName = Read-Host "Enter current Fabric capacity name"
    $NewFabricCapacityName = Read-Host "Enter new Fabric capacity name"
    Write-Host "Planned rename: '$FabricCapacityName' -> '$NewFabricCapacityName'"
    Write-Host "Use Fabric Admin Portal or the correct Fabric REST endpoint for your tenant."
}
