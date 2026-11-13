# Azure Migration Utility

A simple PowerShell tool for moving Azure resources from one resource group to another, optionally deleting the old resource group and subscription after confirmation.

## Files
- `AzureMigrationUtility.ps1` — interactive Azure migration utility

## Usage

Run in Azure Cloud Shell or PowerShell:

```powershell
./AzureMigrationUtility.ps1
```

## Features
- Prompt-driven source/destination subscription and resource group selection
- Move all resources or selected resources
- Preview mode before changing anything
- Confirmation before delete actions
- Separate reminder for Fabric capacity rename

## Notes
- This script is intentionally conservative and requires confirmation before destructive actions.
- Test it in a non-production environment first.
