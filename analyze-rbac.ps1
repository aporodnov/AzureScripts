<#
.SYNOPSIS
Iterates through one or more management group hierarchies (recursively) and exports both permanent RBAC assignments
and PIM eligible assignments for all management groups into a single consolidated report.

.PARAMETER ParentMgId
One or more root management group IDs to start enumeration from. Can be a single string or array of strings.

.PARAMETER OutputCsv
Path to output CSV file for the consolidated report.

.EXAMPLE
.\analyze-rbac.ps1 -ParentMgId "ContosoRoot" -OutputCsv ".\RBAC_Report.csv"

.EXAMPLE
.\analyze-rbac.ps1 -ParentMgId @("ContosoRoot", "FabrikamRoot", "AdventureWorksRoot") -OutputCsv ".\Multi_MG_RBAC_Report.csv"

.EXAMPLE
.\analyze-rbac.ps1 -ParentMgId "ContosoRoot","FabrikamRoot" -OutputCsv ".\RBAC_Report.csv"
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
    [string]$OutputCsv,

    [Parameter(Mandatory = $false)]
    [switch]$IncludePIM = $true
)

# Ensure Az.Resources module loaded
if (-not (Get-Module -ListAvailable -Name Az.Resources)) {
    Write-Error "Az.Resources module not found. Please install with: Install-Module Az.Resources"
    exit 1
}
Import-Module Az.Resources -Force

Write-Host "Processing $($ParentMgId.Count) management group hierarchies: $($ParentMgId -join ', ')" -ForegroundColor Cyan
if ($IncludePIM) {
    Write-Host "Including PIM eligible assignments" -ForegroundColor Yellow
} else {
    Write-Host "Excluding PIM eligible assignments" -ForegroundColor Yellow
}

function Get-AllMgmtGroups {
    param ([string]$RootMg)

    $allMGs = @()

    try {
        Write-Host "  Processing management group: $RootMg" -ForegroundColor Cyan
        $root = Get-AzManagementGroup -GroupId $RootMg -Expand -ErrorAction Stop
        $allMGs += $root
        
        Write-Host "  Found root MG: $($root.Name) with $($root.Children.Count) children" -ForegroundColor Yellow

        if ($root.Children -and $root.Children.Count -gt 0) {
            foreach ($child in $root.Children) {
                Write-Host "  Processing child: $($child.Name), Type: $($child.Type)" -ForegroundColor Gray
                
                if ($child.Type -eq "Microsoft.Management/managementGroups") {
                    Write-Host "  Recursively processing child MG: $($child.Name)" -ForegroundColor Green
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

function Get-IdentityType {
    param($ObjectType, $ObjectId)
    
    if ($ObjectType) {
        switch ($ObjectType) {
            'User' { return 'User' }
            'Group' { return 'Group' }
            'ServicePrincipal' { return 'ServicePrincipal' }
            'ForeignGroup' { return 'External Group' }
            'Application' { return 'Application' }
            default { return $ObjectType }
        }
    }
    
    if ($ObjectId -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        return 'Unknown Identity'
    }
    
    return 'Unknown'
}

function Get-AssignmentState {
    param($Assignment, $AssignmentType)
    
    $state = $AssignmentType
    
    # Check for conditional assignments
    if ($Assignment.Condition -or $Assignment.ConditionVersion) {
        $state = "$AssignmentType + Conditional"
    }
    
    # Check for time-bound assignments (PIM)
    if ($Assignment.StartDateTime -or $Assignment.EndDateTime) {
        if ($Assignment.EndDateTime) {
            try {
                $endDate = if ($Assignment.EndDateTime -is [string]) { 
                    [DateTime]::Parse($Assignment.EndDateTime) 
                } else { 
                    $Assignment.EndDateTime 
                }
                if ($endDate -lt (Get-Date)) {
                    $state = "Expired $AssignmentType"
                } else {
                    $state = "Time-bound $AssignmentType"
                }
            }
            catch {
                $state = "Time-bound $AssignmentType"
            }
        } else {
            $state = "Time-bound $AssignmentType"
        }
    }
    
    return $state
}

# Process all management groups and collect results
$allResults = @()
$processedMGs = @{}

foreach ($rootMgId in $ParentMgId) {
    Write-Host "`nProcessing hierarchy starting from: $rootMgId" -ForegroundColor Magenta
    
    try {
        $mgList = Get-AllMgmtGroups -RootMg $rootMgId | Sort-Object -Property Name -Unique

        if (-not $mgList -or $mgList.Count -eq 0) {
            Write-Warning "No management groups found under $rootMgId or access denied."
            continue
        }

        Write-Host "Found $($mgList.Count) management groups under $rootMgId" -ForegroundColor Green

        foreach ($mg in $mgList) {
            $mgId = $mg.Name
            
            if ($processedMGs.ContainsKey($mgId)) {
                Write-Host "  Skipping already processed MG: $mgId" -ForegroundColor Yellow
                continue
            }
            
            $processedMGs[$mgId] = $true
            $mgScope = "/providers/Microsoft.Management/managementGroups/$mgId"
            Write-Host "  Processing RBAC for MG: $mgId ..." -ForegroundColor Yellow

            # Get permanent role assignments
            try {
                Write-Host "    Getting permanent role assignments..." -ForegroundColor Gray
                $permanentAssignments = Get-AzRoleAssignment -Scope $mgScope -IncludeClassicAdministrators:$false -ErrorAction Stop
                Write-Host "    Found $($permanentAssignments.Count) permanent assignments" -ForegroundColor Green

                foreach ($a in $permanentAssignments) {
                    $identityName = if ($a.SignInName) { $a.SignInName } else { $a.DisplayName }
                    $identityType = Get-IdentityType -ObjectType $a.ObjectType -ObjectId $a.ObjectId
                    $scopeType = if ($a.Scope -eq $mgScope) { "Direct" } else { "Inherited" }
                    $state = Get-AssignmentState -Assignment $a -AssignmentType "Permanent"

                    $allResults += [PSCustomObject]@{
                        RootManagementGroup = $rootMgId
                        ManagementGroup = $mgId
                        ManagementGroupDisplayName = $mg.DisplayName
                        AssignmentType = "Permanent"
                        IdentityName = $identityName
                        IdentityType = $identityType
                        IdentityObjectId = $a.ObjectId
                        RoleDefinition = $a.RoleDefinitionName
                        RoleDefinitionId = $a.RoleDefinitionId
                        Scope = $scopeType
                        ScopePath = $a.Scope
                        ScopeDisplayName = $mg.DisplayName
                        State = $state
                        StartDateTime = $null
                        EndDateTime = $null
                        Status = "Active"
                        MemberType = $null
                        CreatedOn = $null
                        Condition = $a.Condition
                        ConditionVersion = $a.ConditionVersion
                        AssignmentId = $a.RoleAssignmentId
                        PrincipalEmail = $null
                        RoleDefinitionType = "Standard"
                    }
                }
            }
            catch {
                Write-Warning "Failed to get permanent role assignments for $mgId : $($_.Exception.Message)"
            }

            # Get PIM eligible assignments
            if ($IncludePIM) {
                try {
                    Write-Host "    Getting PIM eligible assignments..." -ForegroundColor Gray
                    $eligibleAssignments = Get-AzRoleEligibilityScheduleInstance -Scope $mgScope -ErrorAction Stop
                    Write-Host "    Found $($eligibleAssignments.Count) eligible assignments" -ForegroundColor Green

                    foreach ($assignment in $eligibleAssignments) {
                        $scopeType = if ($assignment.Scope -eq $mgScope) { "Direct" } else { "Inherited" }
                        $state = Get-AssignmentState -Assignment $assignment -AssignmentType "PIM Eligible"

                        $allResults += [PSCustomObject]@{
                            RootManagementGroup = $rootMgId
                            ManagementGroup = $mgId
                            ManagementGroupDisplayName = $mg.DisplayName
                            AssignmentType = "PIM Eligible"
                            IdentityName = $assignment.PrincipalDisplayName
                            IdentityType = $assignment.PrincipalType
                            IdentityObjectId = $assignment.PrincipalId
                            RoleDefinition = $assignment.RoleDefinitionDisplayName
                            RoleDefinitionId = $assignment.RoleDefinitionId
                            Scope = $scopeType
                            ScopePath = $assignment.Scope
                            ScopeDisplayName = $assignment.ScopeDisplayName
                            State = $state
                            StartDateTime = $assignment.StartDateTime
                            EndDateTime = $assignment.EndDateTime
                            Status = $assignment.Status
                            MemberType = $assignment.MemberType
                            CreatedOn = $assignment.CreatedOn
                            Condition = $assignment.Condition
                            ConditionVersion = $assignment.ConditionVersion
                            AssignmentId = $assignment.Id
                            PrincipalEmail = $assignment.PrincipalEmail
                            RoleDefinitionType = $assignment.RoleDefinitionType
                        }
                    }
                }
                catch {
                    Write-Warning "Failed to get PIM eligible assignments for $mgId : $($_.Exception.Message)"
                }
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
    
    $allResults | Sort-Object RootManagementGroup, ManagementGroup, AssignmentType, RoleDefinition | Export-Csv -Path $OutputCsv -NoTypeInformation -Force
    Write-Host "Done. Consolidated report exported successfully!" -ForegroundColor Green
    
    # Enhanced summary statistics
    Write-Host "`nSummary Statistics:" -ForegroundColor Cyan
    
    $summaryStats = $allResults | Group-Object RootManagementGroup | Select-Object Name, Count
    Write-Host "  By Root Management Group:" -ForegroundColor Yellow
    $summaryStats | ForEach-Object { Write-Host "    $($_.Name): $($_.Count) assignments" -ForegroundColor White }
    
    $typeStats = $allResults | Group-Object AssignmentType | Select-Object Name, Count
    Write-Host "  By Assignment Type:" -ForegroundColor Yellow
    $typeStats | ForEach-Object { Write-Host "    $($_.Name): $($_.Count) assignments" -ForegroundColor White }
    
    $stateStats = $allResults | Group-Object State | Select-Object Name, Count | Sort-Object Count -Descending
    Write-Host "  By Assignment State:" -ForegroundColor Yellow
    $stateStats | ForEach-Object { Write-Host "    $($_.Name): $($_.Count) assignments" -ForegroundColor White }
    
    $identityStats = $allResults | Group-Object IdentityType | Select-Object Name, Count
    Write-Host "  By Identity Type:" -ForegroundColor Yellow
    $identityStats | ForEach-Object { Write-Host "    $($_.Name): $($_.Count) assignments" -ForegroundColor White }
    
    # Show PIM-specific statistics if included
    if ($IncludePIM) {
        $permanentAssignments = $allResults | Where-Object { $_.AssignmentType -eq "Permanent" }
        $pimEligibleAssignments = $allResults | Where-Object { $_.AssignmentType -eq "PIM Eligible" }
        $timeBoundAssignments = $allResults | Where-Object { $_.EndDateTime -ne $null }
        $expiredAssignments = $allResults | Where-Object { $_.State -like "*Expired*" }
        
        Write-Host "`nPIM Statistics:" -ForegroundColor Cyan
        Write-Host "  Permanent Assignments: $($permanentAssignments.Count)" -ForegroundColor Green
        Write-Host "  PIM Eligible Assignments: $($pimEligibleAssignments.Count)" -ForegroundColor Green
        Write-Host "  Time-bound Assignments: $($timeBoundAssignments.Count)" -ForegroundColor Yellow
        if ($expiredAssignments.Count -gt 0) {
            Write-Host "  Expired Assignments: $($expiredAssignments.Count)" -ForegroundColor Red
        }
        
        # Show top management groups with PIM assignments
        if ($pimEligibleAssignments.Count -gt 0) {
            $pimByMG = $pimEligibleAssignments | Group-Object ManagementGroup | Sort-Object Count -Descending | Select-Object -First 5
            Write-Host "  Top Management Groups with PIM Eligible Assignments:" -ForegroundColor Yellow
            $pimByMG | ForEach-Object { Write-Host "    $($_.Name): $($_.Count) assignments" -ForegroundColor White }
        }
    }
}