# Networking Scripts

Network configuration, DNS, and security automation for Azure.

## Scripts in This Category

| Script | Purpose | Output |
|--------|---------|--------|
| [set-privatednsfallback](set-privatednsfallback/README.md) | Configure Private DNS fallback resolution policy for virtual network links | Console output + timestamped log file |

### When to Use

- **DNS resolution:** Enable fallback to public DNS for private DNS zones
- **Hybrid scenarios:** Configure DNS to resolve both private and public domains
- **Batch updates:** Update multiple virtual network links across zones
- **Safe deployment:** Use WhatIfMode to preview changes before applying

[→ Get started with set-privatednsfallback](set-privatednsfallback/README.md)

### How to Contribute

Want to add another networking script? Follow the [Contributing Guidelines](../CONTRIBUTING.md) to submit your script.

**Script ideas:**
- Network security group (NSG) audit
- Network topology discovery
- Firewall rule analysis
- Virtual network peering inventory
- Route table configuration audit

[→ Contributing Guidelines](../CONTRIBUTING.md)
