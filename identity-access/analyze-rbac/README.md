# analyze-rbac

Comprehensive Azure RBAC and PIM assignment auditor for hierarchical Azure environments.

## What It Does

Scans one or more management groups and recursively inventories all permanent RBAC and PIM (Privileged Identity Management) eligible assignments. Captures assignment types, identity details, scope inheritance, and generates a detailed CSV report with extensive statistics across scopes.

## Quick Start

```powershell
# 1. Connect to Azure
Connect-AzAccount

# 2. Run the script (analyze one management group with PIM)
.\analyze-rbac.ps1 -ParentMgId "contoso-root" -OutputCsv "rbac-report.csv"

# 3. Open the report
.\rbac-report.csv
```

## Key Features

- ✓ Inventory permanent RBAC assignments and PIM eligible roles
- ✓ Multi-level scope analysis (management groups → subscriptions → resource groups)
- ✓ Track assignment state (Active, Expired, NotYetActive)
- ✓ Inheritance detection (direct vs. inherited)
- ✓ Identity type classification (User, Group, ServicePrincipal, ManagedIdentity)
- ✓ Conditional access constraint tracking
- ✓ Summary statistics by multiple dimensions

## What You'll Get

**CSV columns:** RootManagementGroup, ManagementGroup, SubscriptionId, IdentityName, RoleDefinition, AssignmentType, State, StartDateTime, EndDateTime, etc.

**Summary section:** Breakdown by scope level, assignment type, state, identity type, top subscriptions, top resource groups.

## Requirements

- PowerShell 5.0+
- [Setup prerequisites](../../docs/SETUP.md)
- Reader access to IAM/RBAC at management group level
- View PIM Assignments permission (if analyzing PIM)

## Next Steps

- [→ Full Parameters Guide](USAGE.md)
- [→ Copy-Paste Examples](EXAMPLES.md)
- [→ Understanding Output](../../docs/OUTPUT-GUIDE.md)
