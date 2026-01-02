# analyze-policy

Comprehensive Azure Policy assignment auditor for management group hierarchies.

## What It Does

Scans one or more management groups and recursively inventories all policy assignments. Captures enforcement modes, inheritance status, managed identity info, and generates a detailed CSV report with summary statistics.

## Quick Start

```powershell
# 1. Connect to Azure
Connect-AzAccount

# 2. Run the script (analyze one management group)
.\analyze-policy.ps1 -ParentMgId "contoso-root" -OutputCsv "policy-report.csv"

# 3. Open the report
.\policy-report.csv
```

## Key Features

- ✓ Recursive management group scanning
- ✓ Inheritance detection (direct vs. inherited assignments)
- ✓ Managed identity tracking
- ✓ Enforcement mode reporting
- ✓ Summary statistics by scope and assignment type

## What You'll Get

**CSV columns:** Scope, ScopeName, AssignmentName, EnforcementMode, Inherited, ManagedIdentityId, IdentityType, etc.

**Summary section:** Policy count by scope, inheritance breakdown, managed identity usage stats.

## Requirements

- PowerShell 5.0+
- [Setup prerequisites](../../docs/SETUP.md)
- Reader access to policy at management group level

## Next Steps

- [→ Full Parameters Guide](USAGE.md)
- [→ Copy-Paste Examples](EXAMPLES.md)
- [→ Understanding Output](../../docs/OUTPUT-GUIDE.md)
