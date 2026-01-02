# set-privatednsfallback: Full Parameter Guide

## Parameters

### `-ResourceGroupName` (Required)
**Type:** String  
**Description:** Name of the resource group containing the private DNS zones to update.

```powershell
-ResourceGroupName "my-resource-group"
```

### `-WhatIfMode` (Optional)
**Type:** Switch  
**Default:** `$false` (live mode)  
**Description:** Enable simulation mode. Shows which links would be updated without making any changes. Useful for previewing changes before applying them.

```powershell
# Enable simulation mode
-WhatIfMode

# Disable (default - makes changes)
# (omit the parameter)
```

## Full Syntax

```powershell
.\set-privatednsfallback.ps1 -ResourceGroupName <String> [-WhatIfMode]
```

## What the Script Does

1. **Validate module:** Checks if `Az.PrivateDns` module is installed
2. **Find zones:** Lists all private DNS zones in the resource group
3. **Find links:** For each zone, lists all virtual network links
4. **Check policy:** For each link, checks the current `ResolutionPolicy`
5. **Update or skip:**
   - If policy is already `NxDomainRedirect` → skip
   - If policy is `Default` or empty → update to `NxDomainRedirect` (or simulate in WhatIfMode)
6. **Log results:** Creates timestamped log file with operation details

## Output Details

### Console Output Colors

| Color | Meaning |
|-------|---------|
| **Cyan** | Script start/completion, successful updates |
| **Green** | Found zones, links updated successfully |
| **Yellow** | No zones/links found, simulation mode info, WhatIfMode active |
| **White** | Current evaluation in progress |
| **DarkGray** | Skipped (already updated) |
| **Red** | Errors or module not installed |

### Log File

Created in the same directory as the script with format: `DNSFallbackLogs-YYYYMMDD-HHMMSS.txt`

Contains:
- Script start time and parameters
- Each zone and link evaluated
- Actions taken or skipped
- Any errors encountered
- Script completion status

## Resolution Policy Explained

| Policy | Behavior |
|--------|----------|
| **Default** | NXDOMAIN returned if record not found in private DNS (no fallback) |
| **NxDomainRedirect** | Falls back to public DNS servers if record not found in private DNS |

`NxDomainRedirect` is recommended for hybrid scenarios where you want both private and public DNS resolution.
