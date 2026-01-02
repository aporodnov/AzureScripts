# Azure Scripts

Automation solutions for Azure resource analysis, governance, and auditing.

## 🎯 Quick Find

**What do you need?**

| Need | Category | Example Use Cases |
|------|----------|-------------------|
| 📋 **Audit policies & compliance** | [Governance](governance/README.md) | Policy assignments, enforcement modes, inheritance tracking |
| 🔐 **Review access & roles** | [Identity & Access](identity-access/README.md) | RBAC inventory, PIM tracking, privilege audits |
| 🌐 **Configure DNS & networking** | [Networking](networking/README.md) | DNS resolution, private zone fallback, network setup |

## All Scripts

| Category | Script | Purpose | Setup Time |
|----------|--------|---------|-----------|
| **Governance** | [analyze-policy](governance/analyze-policy/README.md) | Audit Azure policies across management group hierarchies | ~5 min |
| **Identity & Access** | [analyze-rbac](identity-access/analyze-rbac/README.md) | Analyze RBAC and PIM assignments organization-wide | ~5 min |
| **Networking** | [set-privatednsfallback](networking/set-privatednsfallback/README.md) | Configure Private DNS fallback resolution policy | ~2 min |

## ✅ Before You Start

Make sure you have:

- [ ] PowerShell 5.0+ installed ([check version](docs/SETUP.md#install-powershell-if-needed))
- [ ] Azure subscription with appropriate permissions
- [ ] Azure modules installed (`Az.Accounts`, `Az.Resources`, and script-specific modules)

[→ Full Setup Guide](docs/SETUP.md)

## 🚀 How to Use Any Script

1. **Find your script** using the "Quick Find" table above or browse by [category](governance/README.md)
2. **Read the script's README** for overview and quick start
3. **Check USAGE.md** for full parameters and options
4. **Copy an example** from EXAMPLES.md (ready-to-paste code)
5. **Run it** - most scripts export to CSV or include logging

## 📚 Documentation

- [Setup Instructions](docs/SETUP.md) - Prerequisites and Azure module installation
- [Understanding Output](docs/OUTPUT-GUIDE.md) - How to read CSV reports and filter data
- [Contributing Guidelines](CONTRIBUTING.md) - Add new scripts to this repository

---

**Last Updated:** January 2, 2026
