param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter()]
    [switch]$WhatIfMode  # Simulation mode (read-only)
)

# Determine script directory
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Create timestamped log file name
$timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$LogFile = Join-Path $ScriptDirectory "DNSFallbackLogs-$timestamp.txt"

# Function to log both to console and file
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = $null
    )

    # Write to console
    if ($Color) {
        Write-Host $Message -ForegroundColor $Color
    }
    else {
        Write-Host $Message
    }

    # Always write to log file
    Add-Content -Path $LogFile -Value $Message
}

Write-Log ""
Write-Log "Starting Private DNS Fallback script" Cyan
Write-Log "Log file: $LogFile"
Write-Log "Resource Group: $ResourceGroupName"
Write-Log "WhatIfMode: $WhatIfMode"
Write-Log ""

# Ensure Az.PrivateDns module is loaded
if (-not (Get-Module -ListAvailable -Name Az.PrivateDns)) {
    Write-Log "Az.PrivateDns module is not installed. Run: Install-Module Az -Scope CurrentUser" Red
    exit
}

# Get all private DNS zones in the RG
$zones = Get-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName

if ($zones.Count -eq 0) {
    Write-Log "No Private DNS zones found in this resource group." Yellow
    exit
}

foreach ($zone in $zones) {

    Write-Log ""
    Write-Log "Found Private DNS Zone: $($zone.Name)" Green

    # Get all VNet links for the zone
    $links = Get-AzPrivateDnsVirtualNetworkLink `
                -ResourceGroupName $ResourceGroupName `
                -ZoneName $zone.Name

    if ($links.Count -eq 0) {
        Write-Log "  No virtual network links found." Yellow
        continue
    }

    foreach ($link in $links) {

        Write-Log "  Evaluating VNet Link: $($link.Name)" White

        $currentPolicy = $link.ResolutionPolicy

        if ($WhatIfMode) {
            # READ-ONLY MODE: Only show links needing update
            if ($currentPolicy -eq "Default" -or [string]::IsNullOrEmpty($currentPolicy)) {
                Write-Log "    [SIMULATION] Link uses Default policy and would be updated." Yellow
                Write-Log "      Current ResolutionPolicy: $currentPolicy"
                Write-Log "      Would run:"
                Write-Log "        Set-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $ResourceGroupName -ZoneName $($zone.Name) -Name $($link.Name) -ResolutionPolicy NxDomainRedirect -Force"
            }
            else {
                Write-Log "    [SIMULATION] Skipping: ResolutionPolicy already NxDomainRedirect." DarkGray
            }

            continue
        }

        # LIVE MODE: Skip links already updated
        if ($currentPolicy -eq "NxDomainRedirect") {
            Write-Log "    Skipping: ResolutionPolicy already NxDomainRedirect." DarkGray
            continue
        }

        # LIVE MODE: Update links
        try {
            Set-AzPrivateDnsVirtualNetworkLink `
                -ResourceGroupName $ResourceGroupName `
                -ZoneName $zone.Name `
                -Name $link.Name `
                -ResolutionPolicy "NxDomainRedirect" `
                -Force

            Write-Log "    Updated ResolutionPolicy to NxDomainRedirect" Cyan
        }
        catch {
            Write-Log "    Failed to update link: $($link.Name)" Red
            Write-Log "      Error: $($_.Exception.Message)"
        }

    } # end foreach link

} # end foreach zone

if ($WhatIfMode) {
    Write-Log ""
    Write-Log "Simulation completed. No changes were made." Yellow
}
else {
    Write-Log ""
    Write-Log "Completed updating all applicable Private DNS VNet links." Green
}

Write-Log ""
Write-Log "Script finished."
