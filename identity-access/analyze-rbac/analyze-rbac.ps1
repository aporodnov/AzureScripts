<#
.SYNOPSIS
Iterates through one or more management group hierarchies (recursively) and exports both permanent RBAC assignments
and PIM eligible assignments for all management groups, optionally subscriptions, and optionally resource groups into a single consolidated report.

.PARAMETER ParentMgId
One or more root management group IDs to start enumeration from. Can be a single string or array of strings.

.PARAMETER OutputCsv
Path to output CSV file for the consolidated report.

.PARAMETER IncludeSubscriptions
Include subscriptions in the RBAC analysis. When enabled, the script will also analyze RBAC assignments at subscription level.

.PARAMETER IncludeRG
Include resource groups in the RBAC analysis. When enabled, the script will also analyze RBAC assignments at resource group level.
Note: This parameter requires IncludeSubscriptions to be enabled as resource groups exist within subscriptions.

.EXAMPLE
.\analyze-rbac.ps1 -ParentMgId "ContosoRoot" -OutputCsv ".\RBAC_Report.csv"

.EXAMPLE
.\analyze-rbac.ps1 -ParentMgId "ContosoRoot" -OutputCsv ".\RBAC_Report.csv" -IncludeSubscriptions

.EXAMPLE
.\analyze-rbac.ps1 -ParentMgId "ContosoRoot" -OutputCsv ".\RBAC_Report.csv" -IncludeSubscriptions -IncludeRG

.EXAMPLE
.\analyze-rbac.ps1 -ParentMgId @("ContosoRoot", "FabrikamRoot") -OutputCsv ".\Multi_MG_RBAC_Report.csv" -IncludeSubscriptions -IncludeRG -IncludePIM:$false
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
    [switch]$IncludePIM = $true,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSubscriptions = $false,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeRG = $false
)

# Validate parameter dependencies
if ($IncludeRG -and -not $IncludeSubscriptions) {
    throw "The -IncludeRG parameter requires -IncludeSubscriptions to be enabled, as resource groups exist within subscriptions."
}

# Check if connected to Azure
try {
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) {
        throw "Not connected to Azure"
    }
    Write-Host "Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
}
catch {
    Write-Error "Please connect to Azure using Connect-AzAccount before running this script."
    exit 1
}

Write-Host "Processing $($ParentMgId.Count) management group hierarchies: $($ParentMgId -join ', ')" -ForegroundColor Cyan
if ($IncludePIM) {
    Write-Host "Including PIM eligible assignments" -ForegroundColor Yellow
} else {
    Write-Host "Excluding PIM eligible assignments" -ForegroundColor Yellow
}

if ($IncludeSubscriptions) {
    Write-Host "Including subscriptions in RBAC analysis" -ForegroundColor Green
    if ($IncludeRG) {
        Write-Host "Including resource groups in RBAC analysis" -ForegroundColor Green
    } else {
        Write-Host "Excluding resource groups from analysis" -ForegroundColor Yellow
    }
} else {
    Write-Host "Excluding subscriptions from analysis" -ForegroundColor Yellow
}

# Helper function to determine identity type
function Get-IdentityType {
    param (
        [string]$ObjectType,
        [string]$ObjectId
    )
    
    switch ($ObjectType) {
        "User" { return "User" }
        "Group" { return "Group" }
        "ServicePrincipal" { return "ServicePrincipal" }
        "MSI" { return "ManagedIdentity" }
        "Unknown" { 
            if ($ObjectId -match "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$") {
                return "Unknown"
            }
            return "Unknown"
        }
        default { return $ObjectType }
    }
}

# Helper function to determine assignment state
function Get-AssignmentState {
    param (
        $Assignment,
        [string]$AssignmentType
    )
    
    if ($AssignmentType -eq "Permanent") {
        return "Active"
    }
    
    if ($Assignment.Status) {
        return $Assignment.Status
    }
    
    if ($Assignment.EndDateTime) {
        $now = Get-Date
        if ($Assignment.EndDateTime -lt $now) {
            return "Expired"
        } elseif ($Assignment.StartDateTime -and $Assignment.StartDateTime -gt $now) {
            return "NotYetActive"
        } else {
            return "Active"
        }
    }
    
    return "Active"
}

function Get-AllMgmtGroups {
    param (
        [string]$RootMg,
        [bool]$IncludeSubscriptions = $false
    )

    $allMGs = @()

    try {
        $root = Get-AzManagementGroup -GroupId $RootMg -Expand -ErrorAction Stop
        $allMGs += $root

        if ($root.Children -and $root.Children.Count -gt 0) {
            foreach ($child in $root.Children) {
                if ($child.Type -eq "Microsoft.Management/managementGroups") {
                    $childMGs = Get-AllMgmtGroups -RootMg $child.Name -IncludeSubscriptions $IncludeSubscriptions
                    if ($childMGs -and $childMGs.Count -gt 0) {
                        $allMGs += $childMGs
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Unable to retrieve management group $RootMg : $($_.Exception.Message)"
    }

    return $allMGs
}

function Get-SubscriptionsWithContext {
    param ([string]$RootMg)

    $subscriptionsWithContext = @()

    try {
        $root = Get-AzManagementGroup -GroupId $RootMg -Expand -Recurse -ErrorAction Stop
        
        function Extract-SubscriptionsWithParent {
            param ($MgNode, $RootMgId)
            
            $subscriptions = @()
            
            if ($MgNode.Children) {
                foreach ($child in $MgNode.Children) {
                    if ($child.Type -eq "/subscriptions") {
                        $subWithContext = [PSCustomObject]@{
                            Name = $child.Name
                            DisplayName = $child.DisplayName
                            RootManagementGroupId = $RootMgId
                            ParentManagementGroupId = $MgNode.Name
                            ParentManagementGroupDisplayName = $MgNode.DisplayName
                        }
                        $subscriptions += $subWithContext
                    } elseif ($child.Type -eq "Microsoft.Management/managementGroups") {
                        $childSubs = Extract-SubscriptionsWithParent -MgNode $child -RootMgId $RootMgId
                        if ($childSubs -and $childSubs.Count -gt 0) {
                            $subscriptions += $childSubs
                        }
                    }
                }
            }
            
            return $subscriptions
        }
        
        $subscriptionsWithContext = Extract-SubscriptionsWithParent -MgNode $root -RootMgId $RootMg
    }
    catch {
        Write-Warning "Unable to retrieve subscriptions under management group $RootMg : $($_.Exception.Message)"
    }

    return $subscriptionsWithContext
}

function Get-AllResourceGroups {
    param (
        [string]$SubscriptionId,
        [string]$SubscriptionName
    )

    $resourceGroups = @()

    try {
        $resourceGroups = Get-AzResourceGroup -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to retrieve resource groups in subscription $SubscriptionName ($SubscriptionId): $($_.Exception.Message)"
    }

    return $resourceGroups
}

function Process-ResourceGroupRBAC {
    param (
        [string]$ResourceGroupName,
        [string]$SubscriptionId,
        [string]$SubscriptionName,
        [string]$RootMgId,
        [string]$ParentMgId,
        [string]$ParentMgDisplayName,
        [bool]$IncludePIM,
        [int]$CurrentRG,
        [int]$TotalRGs,
        [int]$CurrentSub,
        [int]$TotalSubs
    )

    $rgResults = @()
    $rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
    
    # Update subscription progress with RG details
    $subProgressStatus = "Processing subscription $CurrentSub/$TotalSubs - Resource Group: $ResourceGroupName ($CurrentRG/$TotalRGs)"
    Write-Progress -Id 2 -Activity "Processing Subscriptions" -Status $subProgressStatus -PercentComplete ([math]::Round(($CurrentSub / $TotalSubs) * 100, 1))

    # Get permanent role assignments for resource group
    try {
        $permanentAssignments = Get-AzRoleAssignment -ResourceGroupName $ResourceGroupName -IncludeClassicAdministrators:$false -ErrorAction Stop

        foreach ($a in $permanentAssignments) {
            $identityName = if ($a.SignInName) { $a.SignInName } else { $a.DisplayName }
            $identityType = Get-IdentityType -ObjectType $a.ObjectType -ObjectId $a.ObjectId
            $scopeType = if ($a.Scope -eq $rgScope) { "Direct" } else { "Inherited" }
            $state = Get-AssignmentState -Assignment $a -AssignmentType "Permanent"

            # Determine actual scope level based on assignment path
            $actualScopeLevel = "ResourceGroup"
            if ($a.Scope -match "^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/") {
                $actualScopeLevel = "Resource"
            }

            $rgResults += [PSCustomObject]@{
                RootManagementGroup = $RootMgId
                ManagementGroup = $ParentMgId
                ManagementGroupDisplayName = $ParentMgDisplayName
                SubscriptionId = $SubscriptionId
                SubscriptionName = $SubscriptionName
                ResourceGroupName = $ResourceGroupName
                ScopeLevel = $actualScopeLevel
                AssignmentType = "Permanent"
                IdentityName = $identityName
                IdentityType = $identityType
                IdentityObjectId = $a.ObjectId
                RoleDefinition = $a.RoleDefinitionName
                RoleDefinitionId = $a.RoleDefinitionId
                Scope = $scopeType
                ScopePath = $a.Scope
                ScopeDisplayName = if ($actualScopeLevel -eq "Resource") { Split-Path $a.Scope -Leaf } else { $ResourceGroupName }
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
        Write-Warning "Failed to get permanent role assignments for resource group $ResourceGroupName : $($_.Exception.Message)"
    }

    # Get PIM eligible assignments for resource group
    if ($IncludePIM) {
        try {
            $eligibleAssignments = Get-AzRoleEligibilityScheduleInstance -Scope $rgScope -ErrorAction Stop

            foreach ($assignment in $eligibleAssignments) {
                $scopeType = if ($assignment.Scope -eq $rgScope) { "Direct" } else { "Inherited" }
                $state = Get-AssignmentState -Assignment $assignment -AssignmentType "PIM Eligible"

                # Determine actual scope level based on assignment path
                $actualScopeLevel = "ResourceGroup"
                if ($assignment.Scope -match "^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/") {
                    $actualScopeLevel = "Resource"
                }

                $rgResults += [PSCustomObject]@{
                    RootManagementGroup = $RootMgId
                    ManagementGroup = $ParentMgId
                    ManagementGroupDisplayName = $ParentMgDisplayName
                    SubscriptionId = $SubscriptionId
                    SubscriptionName = $SubscriptionName
                    ResourceGroupName = $ResourceGroupName
                    ScopeLevel = $actualScopeLevel
                    AssignmentType = "PIM Eligible"
                    IdentityName = $assignment.PrincipalDisplayName
                    IdentityType = $assignment.PrincipalType
                    IdentityObjectId = $assignment.PrincipalId
                    RoleDefinition = $assignment.RoleDefinitionDisplayName
                    RoleDefinitionId = $assignment.RoleDefinitionId
                    Scope = $scopeType
                    ScopePath = $assignment.Scope
                    ScopeDisplayName = if ($actualScopeLevel -eq "Resource") { $assignment.ScopeDisplayName } else { $assignment.ScopeDisplayName }
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
            Write-Warning "Failed to get PIM eligible assignments for resource group $ResourceGroupName : $($_.Exception.Message)"
        }
    }

    return $rgResults
}

function Process-SubscriptionRBAC {
    param (
        [string]$SubscriptionId,
        [string]$SubscriptionName,
        [string]$RootMgId,
        [string]$ParentMgId,
        [string]$ParentMgDisplayName,
        [bool]$IncludePIM,
        [bool]$IncludeRG,
        [int]$CurrentSub,
        [int]$TotalSubs
    )

    $subscriptionResults = @()
    $subscriptionScope = "/subscriptions/$SubscriptionId"
    
    # Update subscription progress
    $subProgressStatus = "Processing subscription $CurrentSub/$TotalSubs - $SubscriptionName"
    Write-Progress -Id 2 -Activity "Processing Subscriptions" -Status $subProgressStatus -PercentComplete ([math]::Round(($CurrentSub / $TotalSubs) * 100, 1))

    # Get permanent role assignments for subscription
    try {
        $permanentAssignments = Get-AzRoleAssignment -Scope $subscriptionScope -IncludeClassicAdministrators:$false -ErrorAction Stop

        foreach ($a in $permanentAssignments) {
            $identityName = if ($a.SignInName) { $a.SignInName } else { $a.DisplayName }
            $identityType = Get-IdentityType -ObjectType $a.ObjectType -ObjectId $a.ObjectId
            $scopeType = if ($a.Scope -eq $subscriptionScope) { "Direct" } else { "Inherited" }
            $state = Get-AssignmentState -Assignment $a -AssignmentType "Permanent"

            $subscriptionResults += [PSCustomObject]@{
                RootManagementGroup = $RootMgId
                ManagementGroup = $ParentMgId
                ManagementGroupDisplayName = $ParentMgDisplayName
                SubscriptionId = $SubscriptionId
                SubscriptionName = $SubscriptionName
                ResourceGroupName = $null
                ScopeLevel = "Subscription"
                AssignmentType = "Permanent"
                IdentityName = $identityName
                IdentityType = $identityType
                IdentityObjectId = $a.ObjectId
                RoleDefinition = $a.RoleDefinitionName
                RoleDefinitionId = $a.RoleDefinitionId
                Scope = $scopeType
                ScopePath = $a.Scope
                ScopeDisplayName = $SubscriptionName
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
        Write-Warning "Failed to get permanent role assignments for subscription $SubscriptionName : $($_.Exception.Message)"
    }

    # Get PIM eligible assignments for subscription
    if ($IncludePIM) {
        try {
            $eligibleAssignments = Get-AzRoleEligibilityScheduleInstance -Scope $subscriptionScope -ErrorAction Stop

            foreach ($assignment in $eligibleAssignments) {
                $scopeType = if ($assignment.Scope -eq $subscriptionScope) { "Direct" } else { "Inherited" }
                $state = Get-AssignmentState -Assignment $assignment -AssignmentType "PIM Eligible"

                $subscriptionResults += [PSCustomObject]@{
                    RootManagementGroup = $RootMgId
                    ManagementGroup = $ParentMgId
                    ManagementGroupDisplayName = $ParentMgDisplayName
                    SubscriptionId = $SubscriptionId
                    SubscriptionName = $SubscriptionName
                    ResourceGroupName = $null
                    ScopeLevel = "Subscription"
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
            Write-Warning "Failed to get PIM eligible assignments for subscription $SubscriptionName : $($_.Exception.Message)"
        }
    }

    # Process resource groups if requested
    if ($IncludeRG) {
        try {
            $resourceGroups = Get-AllResourceGroups -SubscriptionId $SubscriptionId -SubscriptionName $SubscriptionName
            
            if ($resourceGroups -and $resourceGroups.Count -gt 0) {
                $rgCounter = 0
                foreach ($rg in $resourceGroups) {
                    $rgCounter++
                    $rgResults = Process-ResourceGroupRBAC -ResourceGroupName $rg.ResourceGroupName -SubscriptionId $SubscriptionId -SubscriptionName $SubscriptionName -RootMgId $RootMgId -ParentMgId $ParentMgId -ParentMgDisplayName $ParentMgDisplayName -IncludePIM $IncludePIM -CurrentRG $rgCounter -TotalRGs $resourceGroups.Count -CurrentSub $CurrentSub -TotalSubs $TotalSubs
                    $subscriptionResults += $rgResults
                }
            }
        }
        catch {
            Write-Warning "Failed to process resource groups in subscription $SubscriptionName : $($_.Exception.Message)"
        }
    }

    return $subscriptionResults
}

# Process all management groups and collect results
$allResults = @()
$processedMGs = @{}
$processedSubscriptions = @{}

# First, collect all management groups to get total count
Write-Host "`nDiscovering management group hierarchy..." -ForegroundColor Cyan
$allMgList = @()
foreach ($rootMgId in $ParentMgId) {
    $mgList = Get-AllMgmtGroups -RootMg $rootMgId -IncludeSubscriptions $IncludeSubscriptions.IsPresent
    if ($mgList) {
        $allMgList += $mgList
    }
}
$allMgList = $allMgList | Sort-Object -Property Name -Unique
$totalMGs = $allMgList.Count

# Collect all subscriptions with context if needed
$allSubList = @()
if ($IncludeSubscriptions) {
    Write-Host "Discovering subscriptions..." -ForegroundColor Cyan
    foreach ($rootMgId in $ParentMgId) {
        $subList = Get-SubscriptionsWithContext -RootMg $rootMgId
        if ($subList) {
            $allSubList += $subList
        }
    }
    $allSubList = $allSubList | Sort-Object -Property Name -Unique
}
$totalSubs = $allSubList.Count

Write-Host "Found $totalMGs management groups" -ForegroundColor Green
if ($IncludeSubscriptions) {
    Write-Host "Found $totalSubs subscriptions" -ForegroundColor Green
}
Write-Host ""

# Process management groups with progress bar
$mgCounter = 0
foreach ($mg in $allMgList) {
    $mgId = $mg.Name
    $mgCounter++
    
    if ($processedMGs.ContainsKey($mgId)) {
        continue
    }
    
    $processedMGs[$mgId] = $true
    $mgScope = "/providers/Microsoft.Management/managementGroups/$mgId"
    
    # Update management group progress
    $mgProgressStatus = "Processing management group $mgCounter/$totalMGs - $($mg.DisplayName)"
    Write-Progress -Id 1 -Activity "Processing Management Groups" -Status $mgProgressStatus -PercentComplete ([math]::Round(($mgCounter / $totalMGs) * 100, 1))

    # Find the root management group for this MG
    $rootMgForThisMG = $ParentMgId | Where-Object { 
        $allMgList | Where-Object { $_.Name -eq $mgId -and $_.Name -eq $_ } 
    }
    if (-not $rootMgForThisMG) {
        $rootMgForThisMG = $ParentMgId[0]  # Default to first root if not found
    }

    # Get permanent role assignments for management group
    try {
        $permanentAssignments = Get-AzRoleAssignment -Scope $mgScope -IncludeClassicAdministrators:$false -ErrorAction Stop

        foreach ($a in $permanentAssignments) {
            $identityName = if ($a.SignInName) { $a.SignInName } else { $a.DisplayName }
            $identityType = Get-IdentityType -ObjectType $a.ObjectType -ObjectId $a.ObjectId
            $scopeType = if ($a.Scope -eq $mgScope) { "Direct" } else { "Inherited" }
            $state = Get-AssignmentState -Assignment $a -AssignmentType "Permanent"

            $allResults += [PSCustomObject]@{
                RootManagementGroup = $rootMgForThisMG
                ManagementGroup = $mgId
                ManagementGroupDisplayName = $mg.DisplayName
                SubscriptionId = $null
                SubscriptionName = $null
                ResourceGroupName = $null
                ScopeLevel = "ManagementGroup"
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

    # Get PIM eligible assignments for management group
    if ($IncludePIM) {
        try {
            $eligibleAssignments = Get-AzRoleEligibilityScheduleInstance -Scope $mgScope -ErrorAction Stop

            foreach ($assignment in $eligibleAssignments) {
                $scopeType = if ($assignment.Scope -eq $mgScope) { "Direct" } else { "Inherited" }
                $state = Get-AssignmentState -Assignment $assignment -AssignmentType "PIM Eligible"

                $allResults += [PSCustomObject]@{
                    RootManagementGroup = $rootMgForThisMG
                    ManagementGroup = $mgId
                    ManagementGroupDisplayName = $mg.DisplayName
                    SubscriptionId = $null
                    SubscriptionName = $null
                    ResourceGroupName = $null
                    ScopeLevel = "ManagementGroup"
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

# Complete management group progress
Write-Progress -Id 1 -Activity "Processing Management Groups" -Status "Completed" -PercentComplete 100

# Process subscriptions if requested
if ($IncludeSubscriptions) {
    $subCounter = 0
    foreach ($subscription in $allSubList) {
        $subId = $subscription.Name
        $subName = $subscription.DisplayName
        $rootMgId = $subscription.RootManagementGroupId
        $parentMgId = $subscription.ParentManagementGroupId
        $parentMgDisplayName = $subscription.ParentManagementGroupDisplayName
        $subCounter++
        
        if ($processedSubscriptions.ContainsKey($subId)) {
            continue
        }
        
        $processedSubscriptions[$subId] = $true
        
        # Set the subscription context before processing
        try {
            Set-AzContext -SubscriptionId $subId -ErrorAction Stop -WarningAction Ignore | Out-Null
            $subscriptionResults = Process-SubscriptionRBAC -SubscriptionId $subId -SubscriptionName $subName -RootMgId $rootMgId -ParentMgId $parentMgId -ParentMgDisplayName $parentMgDisplayName -IncludePIM $IncludePIM.IsPresent -IncludeRG $IncludeRG.IsPresent -CurrentSub $subCounter -TotalSubs $totalSubs
            $allResults += $subscriptionResults
        }
        catch {
            Write-Warning "Failed to set context or process subscription $subName ($subId): $($_.Exception.Message)"
        }
    }
    
    # Complete subscription progress
    Write-Progress -Id 2 -Activity "Processing Subscriptions" -Status "Completed" -PercentComplete 100
}

# Complete all progress bars
Write-Progress -Id 1 -Activity "Processing Management Groups" -Completed
Write-Progress -Id 2 -Activity "Processing Subscriptions" -Completed

# Generate consolidated report
if ($allResults.Count -eq 0) {
    Write-Warning "No RBAC assignments found across all specified management groups: $($ParentMgId -join ', ')"
} else {
    Write-Host "`nGenerating consolidated CSV report..." -ForegroundColor Cyan
    Write-Host "Total management groups processed: $($processedMGs.Keys.Count)" -ForegroundColor Green
    if ($IncludeSubscriptions) {
        Write-Host "Total subscriptions processed: $($processedSubscriptions.Keys.Count)" -ForegroundColor Green
    }
    if ($IncludeRG) {
        $rgAssignments = $allResults | Where-Object { $_.ScopeLevel -eq "ResourceGroup" -or $_.ScopeLevel -eq "Resource" }
        $uniqueRGs = $rgAssignments | Select-Object -Property ResourceGroupName, SubscriptionId -Unique
        Write-Host "Total resource groups processed: $($uniqueRGs.Count)" -ForegroundColor Green
        
        $resourceAssignments = $allResults | Where-Object { $_.ScopeLevel -eq "Resource" }
        if ($resourceAssignments.Count -gt 0) {
            Write-Host "Resource-level assignments found: $($resourceAssignments.Count)" -ForegroundColor Yellow
        }
    }
    Write-Host "Total RBAC assignments found: $($allResults.Count)" -ForegroundColor Green
    Write-Host "Writing consolidated report to: $OutputCsv" -ForegroundColor Cyan
    
    $allResults | Sort-Object RootManagementGroup, ScopeLevel, ManagementGroup, SubscriptionName, ResourceGroupName, AssignmentType, RoleDefinition | Export-Csv -Path $OutputCsv -NoTypeInformation -Force
    Write-Host "Done. Consolidated report exported successfully!" -ForegroundColor Green
    
    # Enhanced summary statistics
    Write-Host "`nSummary Statistics:" -ForegroundColor Cyan
    
    $summaryStats = $allResults | Group-Object RootManagementGroup | Select-Object Name, Count
    Write-Host "  By Root Management Group:" -ForegroundColor Yellow
    $summaryStats | ForEach-Object { Write-Host "    $($_.Name): $($_.Count) assignments" -ForegroundColor White }
    
    $scopeLevelStats = $allResults | Group-Object ScopeLevel | Select-Object Name, Count
    Write-Host "  By Scope Level:" -ForegroundColor Yellow
    $scopeLevelStats | ForEach-Object { Write-Host "    $($_.Name): $($_.Count) assignments" -ForegroundColor White }
    
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
        
        # Show top scopes with PIM assignments
        if ($pimEligibleAssignments.Count -gt 0) {
            $pimByScope = $pimEligibleAssignments | Group-Object ScopeLevel | Select-Object Name, Count
            Write-Host "  PIM Eligible Assignments by Scope Level:" -ForegroundColor Yellow
            $pimByScope | ForEach-Object { Write-Host "    $($_.Name): $($_.Count) assignments" -ForegroundColor White }
        }
    }
    
    # Show scope-specific statistics
    if ($IncludeSubscriptions -or $IncludeRG) {
        $mgAssignments = $allResults | Where-Object { $_.ScopeLevel -eq "ManagementGroup" }
        
        Write-Host "`nScope Level Statistics:" -ForegroundColor Cyan
        Write-Host "  Management Group Assignments: $($mgAssignments.Count)" -ForegroundColor Green
        
        if ($IncludeSubscriptions) {
            $subAssignments = $allResults | Where-Object { $_.ScopeLevel -eq "Subscription" }
            Write-Host "  Subscription Assignments: $($subAssignments.Count)" -ForegroundColor Green
            
            if ($subAssignments.Count -gt 0) {
                $topSubs = $subAssignments | Group-Object SubscriptionName | Sort-Object Count -Descending | Select-Object -First 5
                Write-Host "  Top Subscriptions by Assignment Count:" -ForegroundColor Yellow
                $topSubs | ForEach-Object { Write-Host "    $($_.Name): $($_.Count) assignments" -ForegroundColor White }
            }
        }
        
        if ($IncludeRG) {
            $rgAssignments = $allResults | Where-Object { $_.ScopeLevel -eq "ResourceGroup" }
            $resourceAssignments = $allResults | Where-Object { $_.ScopeLevel -eq "Resource" }
            Write-Host "  Resource Group Assignments: $($rgAssignments.Count)" -ForegroundColor Green
            Write-Host "  Resource-Level Assignments: $($resourceAssignments.Count)" -ForegroundColor Green
            
            if ($rgAssignments.Count -gt 0) {
                $topRGs = $rgAssignments | Group-Object ResourceGroupName | Sort-Object Count -Descending | Select-Object -First 5
                Write-Host "  Top Resource Groups by Assignment Count:" -ForegroundColor Yellow
                $topRGs | ForEach-Object { Write-Host "    $($_.Name): $($_.Count) assignments" -ForegroundColor White }
            }
        }
    }
}