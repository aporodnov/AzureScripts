# Contributing Guidelines

Thank you for contributing automation scripts to Azure Scripts! Follow these guidelines to ensure consistency and maintain high quality.

## Repository Structure

Scripts are organized by category. Each category folder contains scripts grouped by function.

```
category/
├── README.md              # Category overview
└── script-name/
    ├── script-name.ps1    # The automation script
    ├── README.md          # Purpose + quick start
    ├── USAGE.md           # Full parameter guide
    └── EXAMPLES.md        # Copy-paste ready examples
```

## Adding a New Script

### 1. Choose or Create a Category

- **Existing categories:** `governance/`, `identity-access/`, `networking/`
- **New category:** Create a new folder if your script doesn't fit existing categories

### 2. Create Script Directory

```powershell
mkdir category/script-name
```

### 3. Create Required Files

#### `script-name.ps1`
- Add comprehensive inline documentation (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`)
- Include error handling and progress indicators
- Add header comments explaining the script's purpose
- Format output to CSV when reporting data

#### `README.md` (in script folder)
- **What It Does:** 1-2 sentence overview
- **Quick Start:** 3-4 line copy-paste code to run
- **Key Features:** Bullet-point highlights (3-5 items)
- **What You'll Get:** What the CSV/output contains
- **Requirements:** Minimum PowerShell version, required modules, permissions
- **Next Steps:** Links to USAGE.md, EXAMPLES.md, and relevant docs/

See `governance/analyze-policy/README.md` for template.

#### `USAGE.md` (in script folder)
- Document all parameters with type, description, required/optional, and examples
- Include full syntax line
- Document all output columns with descriptions

See `governance/analyze-policy/USAGE.md` for template.

#### `EXAMPLES.md` (in script folder)
- Provide 3-5 real-world examples
- Each example should be copy-paste ready
- Update values (management group IDs, paths, etc.) to be obviously user-replaceable
- Include description of what each example does

See `governance/analyze-policy/EXAMPLES.md` for template.

### 4. Update Category README

Add an entry to `category/README.md` listing the new script with one-line purpose and link to script README.

### 5. Update Root README

Add new category to root [README.md](README.md) quick navigation table if creating a new category.

## Code Standards

- **PowerShell Version:** Target PowerShell 5.0+ for compatibility
- **Module Dependencies:** List all required Az modules in script header comments
- **Error Handling:** Use try-catch blocks for critical operations
- **Progress Feedback:** Use `Write-Progress` for long-running operations
- **Comments:** Add inline comments for complex logic
- **Output:** Default to CSV export for data reports; include summary statistics
- **Authentication:** Assume user runs `Connect-AzAccount` before script execution

## Documentation Standards

- **Clarity:** Write for users unfamiliar with the script—be explicit
- **Examples:** Every parameter should have a usage example in USAGE.md
- **Links:** Use relative links for cross-document navigation
- **Formatting:** Use markdown consistently; tables for parameter lists

## Testing

Before submitting:
1. Test script against real Azure environment
2. Verify all parameters work as documented
3. Check CSV output is well-formatted and complete
4. Validate all markdown files render correctly
5. Test all example code blocks (copy-paste test)

## Submission Process

1. Create a new branch: `feature/add-script-name`
2. Add your script and documentation
3. Test thoroughly
4. Submit a pull request with description of what the script does and which category it belongs to

---

**Questions?** Review existing scripts in `governance/` and `identity-access/` for reference implementations.
