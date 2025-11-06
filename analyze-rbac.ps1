<#
.SYNOPSIS
Iterates through one or more management group hierarchies (recursively) and exports RBAC assignments
for all management groups (excluding subscriptions) into a single consolidated report.

.PARAMETER ParentMgId
One or more root management group IDs to start enumeration from. Can be a single string or array of strings.

.PARAMETER OutputCsv
Path to output CSV file for the consolidated report.

.EXAMPLE
.\Analyze-RBAC-MG.ps1 -ParentMgId "ContosoRoot" -OutputCsv ".\RBAC_Report.csv"

.EXAMPLE
.\Analyze-RBAC-MG.ps1 -ParentMgId @("ContosoRoot", "FabrikamRoot", "AdventureWorksRoot") -OutputCsv ".\Multi_MG_RBAC_Report.csv"

.EXAMPLE
.\Analyze-RBAC-MG.ps1 -ParentMgId "ContosoRoot","FabrikamRoot" -OutputCsv ".\RBAC_Report.csv"
#>

param (
    [Parameter(Mandatory = $true)]
    [string[]]$ParentMgId,

    [Parameter(Mandatory = $true)]
    [ValidateScript({
        $directory = Split-Path $_ -Parent
        if (-not (Test-Path $directory)) {
            throw "Directory does not exist: $directory"
        }
        return $true
    })]
    [string]$OutputCsv
)

# Ensure Az.Resources module loaded (same as original script)
if (-not (Get-Module -ListAvailable -Name Az.Resources)) {
    Write-Error "Az.Resources module not found. Please install with: Install-Module Az.Resources"
    exit
}
Import-Module Az.Resources -Force

Write-Host "Processing $($ParentMgId.Count) management group hierarchies: $($ParentMgId -join ', ')" -ForegroundColor Cyan

function Get-AllMgmtGroups {
    param ([string]$RootMg)

    $allMGs = @()

    try {
        # Get the root management group with -Expand to get immediate children
        Write-Host "  Processing management group: $RootMg" -ForegroundColor Cyan
        $root = Get-AzManagementGroup -GroupId $RootMg -Expand -ErrorAction Stop
        $allMGs += $root
        
        Write-Host "  Found root MG: $($root.Name) with $($root.Children.Count) children" -ForegroundColor Yellow

        # Recursively process children management groups
        if ($root.Children -and $root.Children.Count -gt 0) {
            foreach ($child in $root.Children) {
                Write-Host "  Processing child: $($child.Name), Type: $($child.Type)" -ForegroundColor Gray
                
                # Correct type comparison
                if ($child.Type -eq "Microsoft.Management/managementGroups") {
                    Write-Host "  Recursively processing child MG: $($child.Name)" -ForegroundColor Green
                    # Recursively get child management groups
                    $childMGs = Get-AllMgmtGroups -RootMg $child.Name
                    if ($childMGs -and $childMGs.Count -gt 0) {
                        $allMGs += $childMGs
                        Write-Host "  Added $($childMGs.Count) child MGs from $($child.Name)" -ForegroundColor Green
                    }
                } else {
                    Write-Host "  Skipping non-MG child: $($child.Name) (Type: $($child.Type))" -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "  No children found for MG: $RootMg" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Unable to retrieve management group $RootMg : $($_.Exception.Message)"
    }

    Write-Host "  Returning $($allMGs.Count) management groups from $RootMg" -ForegroundColor Magenta
    return $allMGs
}

# Simplified identity type function (removed unnecessary AD lookups)
function Get-IdentityType {
    param($ObjectType, $ObjectId)
    
    # Use ObjectType if available, otherwise return generic type
    if ($ObjectType) {
        switch ($ObjectType) {
            'User' { return 'User' }
            'Group' { return 'Group' }
            'ServicePrincipal' { return 'ServicePrincipal' }
            default { return $ObjectType }
        }
    }
    
    # Fallback for older PowerShell versions or missing ObjectType
    if ($ObjectId -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        return 'Unknown Identity'
    }
    
    return 'Unknown'
}

# Process all management groups and collect results
$allResults = @()
$processedMGs = @{}  # Track processed MGs to avoid duplicates

foreach ($rootMgId in $ParentMgId) {
    Write-Host "`nProcessing hierarchy starting from: $rootMgId" -ForegroundColor Magenta
    
    try {
        $mgList = Get-AllMgmtGroups -RootMg $rootMgId | Sort-Object -Property Name -Unique

        if (-not $mgList -or $mgList.Count -eq 0) {
            Write-Warning "No management groups found under $rootMgId or access denied."
            continue
        }

        Write-Host "Found $($mgList.Count) management groups under $rootMgId" -ForegroundColor Green

        # Process RBAC for each management group
        foreach ($mg in $mgList) {
            $mgId = $mg.Name
            
            # Skip if already processed (in case of overlapping hierarchies)
            if ($processedMGs.ContainsKey($mgId)) {
                Write-Host "  Skipping already processed MG: $mgId" -ForegroundColor Yellow
                continue
            }
            
            $processedMGs[$mgId] = $true
            $mgScope = "/providers/Microsoft.Management/managementGroups/$mgId"
            Write-Host "  Processing RBAC for MG: $mgId ..." -ForegroundColor Yellow

            try {
                $assignments = Get-AzRoleAssignment -Scope $mgScope -IncludeClassicAdministrators:$false -ErrorAction Stop

                foreach ($a in $assignments) {
                    # Use available properties without complex AD lookups
                    $identityName = if ($a.SignInName) { $a.SignInName } else { $a.DisplayName }
                    $identityType = Get-IdentityType -ObjectType $a.ObjectType -ObjectId $a.ObjectId

                    $allResults += [PSCustomObject]@{
                        RootManagementGroup = $rootMgId
                        ManagementGroup     = $mgId
                        IdentityName        = $identityName
                        IdentityType        = $identityType
                        IdentityObjectId    = $a.ObjectId
                        RoleDefinition      = $a.RoleDefinitionName
                        Scope               = if ($a.Scope -eq $mgScope) { "This Resource" } else { "Inherited" }
                        State               = if ($a.ConditionVersion -or $a.Condition) { "Eligible/Conditional" } else { "Permanent" }
                    }
                }
            }
            catch {
                Write-Warning ("Failed to get role assignments for scope {0}: {1}" -f $mgScope, $_.Exception.Message)
            }
        }
    }
    catch {
        Write-Error "Failed to process management group hierarchy $rootMgId : $($_.Exception.Message)"
    }
}

# Generate consolidated report
if ($allResults.Count -eq 0) {
    Write-Warning "No RBAC assignments found across all specified management groups: $($ParentMgId -join ', ')"
} else {
    Write-Host "`nGenerating consolidated CSV report..." -ForegroundColor Cyan
    Write-Host "Total management groups processed: $($processedMGs.Keys.Count)" -ForegroundColor Green
    Write-Host "Total RBAC assignments found: $($allResults.Count)" -ForegroundColor Green
    Write-Host "Writing consolidated report to: $OutputCsv" -ForegroundColor Cyan
    
    $allResults | Sort-Object RootManagementGroup, ManagementGroup, RoleDefinition | Export-Csv -Path $OutputCsv -NoTypeInformation -Force
    Write-Host "Done. Consolidated report exported successfully!" -ForegroundColor Green
    
    # Summary statistics
    $summaryStats = $allResults | Group-Object RootManagementGroup | Select-Object Name, Count
    Write-Host "`nSummary by Root Management Group:" -ForegroundColor Cyan
    $summaryStats | ForEach-Object { Write-Host "  $($_.Name): $($_.Count) assignments" -ForegroundColor White }
}