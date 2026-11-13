# Fabric capacity rename utility
# Use this if you want to rename a Fabric capacity in a tenant.

$ErrorActionPreference = "Stop"

Write-Host "Fabric Capacity Rename Utility"
Write-Host "----------------------------"

$CurrentName = Read-Host "Enter current capacity name"
$NewName = Read-Host "Enter new capacity name"

Write-Host ""
Write-Host "Planned rename: '$CurrentName' -> '$NewName'"
Write-Host "This is usually done in the Fabric Admin portal or via the supported Fabric admin API."
Write-Host "Do not assume the resource name in Azure matches the Fabric capacity name exactly."
Write-Host "Check your tenant's admin experience before finalizing the rename."
