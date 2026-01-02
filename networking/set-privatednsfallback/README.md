# set-privatednsfallback

Configure Private DNS fallback resolution policy for virtual network links.

## What It Does

Scans private DNS zones in a resource group and updates virtual network links to use `NxDomainRedirect` resolution policy. This enables DNS queries to fall back to public DNS when a record isn't found in the private zone, instead of returning NXDOMAIN.

Includes a simulation mode (`-WhatIfMode`) to preview changes before applying them.

## Quick Start

```powershell
# 1. Connect to Azure
Connect-AzAccount

# 2. Simulate changes (read-only preview)
.\set-privatednsfallback.ps1 -ResourceGroupName "my-rg" -WhatIfMode

# 3. Apply changes
.\set-privatednsfallback.ps1 -ResourceGroupName "my-rg"
```

## Key Features

- ✓ Batch update virtual network links across all private DNS zones
- ✓ Simulation mode (WhatIfMode) to preview changes safely
- ✓ Timestamped logging of all operations
- ✓ Color-coded console output for easy reading
- ✓ Automatic skip of already-updated links
- ✓ Detailed error reporting

## What You'll Get

**Console output:** Real-time color-coded status of each zone and link update

**Log file:** Timestamped text file (`DNSFallbackLogs-YYYYMMDD-HHMMSS.txt`) with complete operation history

## Requirements

- PowerShell 5.0+
- [Setup prerequisites](../../docs/SETUP.md) including `Az.PrivateDns` module
- Contributor access to private DNS zones in the resource group

## Next Steps

- [→ Full Parameters Guide](USAGE.md)
- [→ Copy-Paste Examples](EXAMPLES.md)
- [→ Understanding Output](../../docs/OUTPUT-GUIDE.md)
