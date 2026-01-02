<#
.SYNOPSIS
Iterates through one or more management group hierarchies (recursively) and exports Azure Policy assignments
for all management groups and subscriptions into a single consolidated report.

.PARAMETER ParentMgId
One or more root management group IDs to start enumeration from. Can be a single string or array of strings.

.PARAMETER OutputCsv
Path to output CSV file for the consolidated report.

.PARAMETER IncludeSubscriptions
Include subscription-level policy assignments in addition to management group assignments.

.EXAMPLE
.\analyze-policy.ps1 -ParentMgId "ContosoRoot" -OutputCsv ".\Policy_Report.csv"

.EXAMPLE
.\analyze-policy.ps1 -ParentMgId @("ContosoRoot", "FabrikamRoot") -OutputCsv ".\Multi_Policy_Report.csv" -IncludeSubscriptions

.EXAMPLE
.\analyze-policy.ps1 -ParentMgId "ContosoRoot","FabrikamRoot" -OutputCsv ".\Policy_Report.csv" -IncludeSubscriptions
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
    [switch]$IncludeSubscriptions
)

# Ensure Az.Resources module loaded
if (-not (Get-Module -ListAvailable -Name Az.Resources)) {
    Write-Error "Az.Resources module not found. Please install with: Install-Module Az.Resources"
    exit 1
}
Import-Module Az.Resources -Force

Write-Host "Processing $($ParentMgId.Count) management group hierarchies: $($ParentMgId -join ', ')" -ForegroundColor Cyan
if ($IncludeSubscriptions) {
    Write-Host "Including subscription-level policy assignments" -ForegroundColor Yellow
}

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
                
                # Process management group children recursively
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

function Get-SubscriptionsFromMG {
    param ([string]$MgId)
    
    $subscriptions = @()
    
    try {
        $mg = Get-AzManagementGroup -GroupId $MgId -Expand -ErrorAction Stop
        
        # Get direct subscription children
        if ($mg.Children) {
            foreach ($child in $mg.Children) {
                if ($child.Type -eq "Microsoft.Resources/subscriptions") {
                    $subscriptions += [PSCustomObject]@{
                        SubscriptionId = $child.Name
                        DisplayName = $child.DisplayName
                        ParentMG = $MgId
                    }
                }
            }
        }
        
        # Recursively get subscriptions from child management groups
        if ($mg.Children) {
            foreach ($child in $mg.Children) {
                if ($child.Type -eq "Microsoft.Management/managementGroups") {
                    $childSubs = Get-SubscriptionsFromMG -MgId $child.Name
                    $subscriptions += $childSubs
                }
            }
        }
    }
    catch {
        Write-Warning "Unable to retrieve subscriptions from management group $MgId : $($_.Exception.Message)"
    }
    
    return $subscriptions
}

function Get-PolicyAssignments {
    param($CurrentScope)
    
    $allAssignments = @()
    
    Write-Host "    Getting policy assignments for $CurrentScope..." -ForegroundColor Gray
    
    try {
        # Get all policy assignments that apply to this scope
        $assignments = Get-AzPolicyAssignment -Scope $CurrentScope -ErrorAction SilentlyContinue
        
        if ($assignments) {
            foreach ($assignment in $assignments) {
                $allAssignments += $assignment
            }
            Write-Host "      Found $($allAssignments.Count) policy assignments" -ForegroundColor Gray
        } else {
            Write-Host "      No policy assignments found" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "Failed to get policy assignments for $CurrentScope : $($_.Exception.Message)"
    }
    
    return $allAssignments
}

function Get-InheritanceStatus {
    param(
        [string]$ScopeName,
        [string]$AssignmentScope,
        [string]$CurrentScopeType
    )
    
    # Extract the management group name or subscription ID from the assignment scope
    if ($AssignmentScope -like "*/managementGroups/*") {
        $assignmentScopeName = ($AssignmentScope -split '/')[-1]
        # For management groups, compare the scope names directly
        if ($CurrentScopeType -eq "Management Group") {
            return ($ScopeName -ne $assignmentScopeName).ToString().ToLower()
        } else {
            # For subscriptions, if assigned to a management group, it's always inherited
            return "true"
        }
    } elseif ($AssignmentScope -like "/subscriptions/*") {
        $assignmentScopeName = ($AssignmentScope -split '/')[-1]
        # For subscriptions, compare the scope names directly
        return ($ScopeName -ne $assignmentScopeName).ToString().ToLower()
    } else {
        # Unknown scope format, assume inherited
        return "true"
    }
}

function Get-ManagedIdentityInfo {
    param($Assignment)
    
    try {
        # Based on the actual Azure Policy assignment structure, check the root-level identity properties
        if ($Assignment.IdentityType) {
            if ($Assignment.IdentityType -eq "SystemAssigned") {
                return @{
                    HasManagedIdentity = "Yes"
                    ManagedIdentityId = $Assignment.IdentityPrincipalId
                    IdentityType = "System Assigned"
                }
            } elseif ($Assignment.IdentityType -eq "UserAssigned") {
                # For user-assigned identities, the IDs might be in IdentityUserAssignedIdentity
                $userAssignedIds = @()
                if ($Assignment.IdentityUserAssignedIdentity) {
                    # Try to extract user-assigned identity IDs
                    if ($Assignment.IdentityUserAssignedIdentity.PSObject.Properties) {
                        $userAssignedIds = $Assignment.IdentityUserAssignedIdentity.PSObject.Properties.Name
                    }
                }
                
                # If no user-assigned IDs found, use the PrincipalId as fallback
                if ($userAssignedIds.Count -eq 0 -and $Assignment.IdentityPrincipalId) {
                    $userAssignedIds = @($Assignment.IdentityPrincipalId)
                }
                
                return @{
                    HasManagedIdentity = "Yes"
                    ManagedIdentityId = ($userAssignedIds -join '; ')
                    IdentityType = "User Assigned"
                }
            } else {
                # Unknown identity type
                return @{
                    HasManagedIdentity = "Yes"
                    ManagedIdentityId = if ($Assignment.IdentityPrincipalId) { $Assignment.IdentityPrincipalId } else { "Unknown" }
                    IdentityType = $Assignment.IdentityType
                }
            }
        }
        
        # Fallback: Check if IdentityPrincipalId exists without IdentityType
        if ($Assignment.IdentityPrincipalId -and -not $Assignment.IdentityType) {
            return @{
                HasManagedIdentity = "Yes"
                ManagedIdentityId = $Assignment.IdentityPrincipalId
                IdentityType = "Unknown Type"
            }
        }
        
        # No managed identity found
        return @{
            HasManagedIdentity = "No"
            ManagedIdentityId = "N/A"
            IdentityType = "None"
        }
    }
    catch {
        Write-Verbose "Error getting managed identity info for assignment $($Assignment.Name): $($_.Exception.Message)"
        return @{
            HasManagedIdentity = "Error"
            ManagedIdentityId = "Error: $($_.Exception.Message)"
            IdentityType = "Error"
        }
    }
}

# Process all management groups and collect results
$allResults = @()
$processedMGs = @{}  # Track processed MGs to avoid duplicates
$processedSubs = @{}  # Track processed subscriptions to avoid duplicates

foreach ($rootMgId in $ParentMgId) {
    Write-Host "`nProcessing hierarchy starting from: $rootMgId" -ForegroundColor Magenta
    
    try {
        $mgList = Get-AllMgmtGroups -RootMg $rootMgId | Sort-Object -Property Name -Unique

        if (-not $mgList -or $mgList.Count -eq 0) {
            Write-Warning "No management groups found under $rootMgId or access denied."
            continue
        }

        Write-Host "Found $($mgList.Count) management groups under $rootMgId" -ForegroundColor Green

        # Process Policy assignments for each management group
        foreach ($mg in $mgList) {
            $mgId = $mg.Name
            
            # Skip if already processed (in case of overlapping hierarchies)
            if ($processedMGs.ContainsKey($mgId)) {
                Write-Host "  Skipping already processed MG: $mgId" -ForegroundColor Yellow
                continue
            }
            
            $processedMGs[$mgId] = $true
            $mgScope = "/providers/Microsoft.Management/managementGroups/$mgId"
            Write-Host "  Processing Policy assignments for MG: $mgId ..." -ForegroundColor Yellow

            try {
                # Get policy assignments
                $assignments = Get-PolicyAssignments -CurrentScope $mgScope

                foreach ($assignment in $assignments) {
                    
                    # Get proper display name - try multiple property paths
                    $displayName = $null
                    
                    # Try different possible paths for DisplayName
                    if ($assignment.DisplayName -and -not [string]::IsNullOrWhiteSpace($assignment.DisplayName)) {
                        $displayName = $assignment.DisplayName
                    } elseif ($assignment.Properties.DisplayName -and -not [string]::IsNullOrWhiteSpace($assignment.Properties.DisplayName)) {
                        $displayName = $assignment.Properties.DisplayName
                    } elseif ($assignment.Properties.displayName -and -not [string]::IsNullOrWhiteSpace($assignment.Properties.displayName)) {
                        $displayName = $assignment.Properties.displayName
                    }
                    
                    # If no display name found or it's the same as the name, use the name as fallback
                    if ([string]::IsNullOrWhiteSpace($displayName) -or $displayName -eq $assignment.Name) {
                        $displayName = $assignment.Name
                    }

                    # Get assignment scope - try multiple properties to ensure we get the value
                    $assignmentScope = if ($assignment.Properties.Scope) {
                        $assignment.Properties.Scope
                    } elseif ($assignment.Scope) {
                        $assignment.Scope
                    } elseif ($assignment.ResourceId) {
                        # Extract scope from ResourceId if needed
                        $parts = $assignment.ResourceId -split '/providers/Microsoft.Authorization/policyAssignments/'
                        if ($parts.Count -gt 1) { $parts[0] } else { $assignment.ResourceId }
                    } else {
                        "Unknown"
                    }

                    # Get enforcement mode - try multiple property paths
                    $enforcementMode = if ($assignment.Properties.EnforcementMode) {
                        $assignment.Properties.EnforcementMode
                    } elseif ($assignment.EnforcementMode) {
                        $assignment.EnforcementMode
                    } else {
                        "Default"
                    }

                    # Determine inheritance status
                    $inherited = Get-InheritanceStatus -ScopeName $mgId -AssignmentScope $assignmentScope -CurrentScopeType "Management Group"

                    # Get managed identity information
                    $identityInfo = Get-ManagedIdentityInfo -Assignment $assignment

                    $allResults += [PSCustomObject]@{
                        Scope                = "Management Group"
                        ScopeName            = $mgId
                        ScopeDisplayName     = $mg.DisplayName
                        AssignmentName       = $assignment.Name
                        AssignmentDisplayName = $displayName
                        EnforcementMode      = $enforcementMode
                        AssignmentScope      = $assignmentScope
                        Inherited            = $inherited
                        HasManagedIdentity   = $identityInfo.HasManagedIdentity
                        ManagedIdentityId    = $identityInfo.ManagedIdentityId
                        IdentityType         = $identityInfo.IdentityType
                    }
                }

                Write-Host "    Found $($assignments.Count) policy assignments" -ForegroundColor Green
            }
            catch {
                Write-Warning ("Failed to get policy assignments for scope {0}: {1}" -f $mgScope, $_.Exception.Message)
            }
        }

        # Process subscription-level policy assignments if requested
        if ($IncludeSubscriptions) {
            Write-Host "`nProcessing subscription-level policy assignments..." -ForegroundColor Cyan
            
            $allSubscriptions = Get-SubscriptionsFromMG -MgId $rootMgId
            Write-Host "Found $($allSubscriptions.Count) subscriptions under $rootMgId" -ForegroundColor Green

            foreach ($sub in $allSubscriptions) {
                $subId = $sub.SubscriptionId
                
                # Skip if already processed
                if ($processedSubs.ContainsKey($subId)) {
                    Write-Host "  Skipping already processed subscription: $subId" -ForegroundColor Yellow
                    continue
                }
                
                $processedSubs[$subId] = $true
                Write-Host "  Processing Policy assignments for Subscription: $($sub.DisplayName) ($subId) ..." -ForegroundColor Yellow

                try {
                    # Set subscription context
                    $null = Set-AzContext -SubscriptionId $subId -ErrorAction Stop
                    
                    # Get policy assignments for this subscription
                    $subScope = "/subscriptions/$subId"
                    $assignments = Get-PolicyAssignments -CurrentScope $subScope

                    foreach ($assignment in $assignments) {
                        
                        # Get proper display name - try multiple property paths
                        $displayName = $null
                        
                        # Try different possible paths for DisplayName
                        if ($assignment.DisplayName -and -not [string]::IsNullOrWhiteSpace($assignment.DisplayName)) {
                            $displayName = $assignment.DisplayName
                        } elseif ($assignment.Properties.DisplayName -and -not [string]::IsNullOrWhiteSpace($assignment.Properties.DisplayName)) {
                            $displayName = $assignment.Properties.DisplayName
                        } elseif ($assignment.Properties.displayName -and -not [string]::IsNullOrWhiteSpace($assignment.Properties.displayName)) {
                            $displayName = $assignment.Properties.displayName
                        }
                        
                        # If no display name found or it's the same as the name, use the name as fallback
                        if ([string]::IsNullOrWhiteSpace($displayName) -or $displayName -eq $assignment.Name) {
                            $displayName = $assignment.Name
                        }

                        # Get assignment scope - try multiple properties to ensure we get the value
                        $assignmentScope = if ($assignment.Properties.Scope) {
                            $assignment.Properties.Scope
                        } elseif ($assignment.Scope) {
                            $assignment.Scope
                        } elseif ($assignment.ResourceId) {
                            # Extract scope from ResourceId if needed
                            $parts = $assignment.ResourceId -split '/providers/Microsoft.Authorization/policyAssignments/'
                            if ($parts.Count -gt 1) { $parts[0] } else { $assignment.ResourceId }
                        } else {
                            "Unknown"
                        }

                        # Get enforcement mode - try multiple property paths
                        $enforcementMode = if ($assignment.Properties.EnforcementMode) {
                            $assignment.Properties.EnforcementMode
                        } elseif ($assignment.EnforcementMode) {
                            $assignment.EnforcementMode
                        } else {
                            "Default"
                        }

                        # Determine inheritance status
                        $inherited = Get-InheritanceStatus -ScopeName $subId -AssignmentScope $assignmentScope -CurrentScopeType "Subscription"

                        # Get managed identity information
                        $identityInfo = Get-ManagedIdentityInfo -Assignment $assignment

                        $allResults += [PSCustomObject]@{
                            Scope                = "Subscription"
                            ScopeName            = $subId
                            ScopeDisplayName     = $sub.DisplayName
                            AssignmentName       = $assignment.Name
                            AssignmentDisplayName = $displayName
                            EnforcementMode      = $enforcementMode
                            AssignmentScope      = $assignmentScope
                            Inherited            = $inherited
                            HasManagedIdentity   = $identityInfo.HasManagedIdentity
                            ManagedIdentityId    = $identityInfo.ManagedIdentityId
                            IdentityType         = $identityInfo.IdentityType
                        }
                    }

                    Write-Host "    Found $($assignments.Count) policy assignments" -ForegroundColor Green
                }
                catch {
                    Write-Warning ("Failed to get policy assignments for subscription {0}: {1}" -f $subId, $_.Exception.Message)
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
    Write-Warning "No policy assignments found across all specified management groups: $($ParentMgId -join ', ')"
} else {
    Write-Host "`nGenerating consolidated CSV report..." -ForegroundColor Cyan
    Write-Host "Total management groups processed: $($processedMGs.Keys.Count)" -ForegroundColor Green
    if ($IncludeSubscriptions) {
        Write-Host "Total subscriptions processed: $($processedSubs.Keys.Count)" -ForegroundColor Green
    }
    Write-Host "Total policy assignments found: $($allResults.Count)" -ForegroundColor Green
    Write-Host "Writing consolidated report to: $OutputCsv" -ForegroundColor Cyan
    
    $allResults | Sort-Object Scope, ScopeName | Export-Csv -Path $OutputCsv -NoTypeInformation -Force
    Write-Host "Done. Consolidated report exported successfully!" -ForegroundColor Green
    
    # Summary statistics
    $summaryStats = $allResults | Group-Object Scope | Select-Object Name, Count
    Write-Host "`nSummary by Scope:" -ForegroundColor Cyan
    $summaryStats | ForEach-Object { 
        Write-Host "  $($_.Name): $($_.Count) assignments" -ForegroundColor White 
    }
    
    # Inheritance statistics
    $inheritanceStats = $allResults | Group-Object Inherited | Select-Object Name, Count
    Write-Host "`nInheritance Breakdown:" -ForegroundColor Cyan
    $inheritanceStats | ForEach-Object { 
        $inheritanceLabel = if ($_.Name -eq "true") { "Inherited" } else { "Direct" }
        Write-Host "  ${inheritanceLabel}: $($_.Count) assignments" -ForegroundColor White 
    }
    
    # Managed Identity statistics
    $identityStats = $allResults | Group-Object HasManagedIdentity | Select-Object Name, Count
    Write-Host "`nManaged Identity Breakdown:" -ForegroundColor Cyan
    $identityStats | ForEach-Object { 
        Write-Host "  $($_.Name): $($_.Count) assignments" -ForegroundColor White 
    }
}