# set-privatednsfallback: Ready-to-Use Examples

Copy, paste, and run. Update resource group names for your environment.

## Example 1: Simulation Mode (Preview Changes)

```powershell
Connect-AzAccount
.\set-privatednsfallback.ps1 -ResourceGroupName "my-rg" -WhatIfMode
```

Use this first to see what would change before applying updates.

## Example 2: Apply Changes to Single Resource Group

```powershell
Connect-AzAccount
.\set-privatednsfallback.ps1 -ResourceGroupName "my-rg"
Write-Host "Update completed. Check DNSFallbackLogs-*.txt for details."
```

## Example 3: Update Multiple Resource Groups

```powershell
Connect-AzAccount

$resourceGroups = @("network-rg", "dns-rg", "infrastructure-rg")

foreach ($rg in $resourceGroups) {
    Write-Host "Processing $rg..." -ForegroundColor Cyan
    .\set-privatednsfallback.ps1 -ResourceGroupName $rg
    Write-Host "Completed $rg`n" -ForegroundColor Green
}
```

## Example 4: Automated Batch Processing with Logging

```powershell
Connect-AzAccount

$resourceGroups = @("network-rg", "dns-rg")
$summaryLog = "C:\Reports\DNSFallback-Summary-$(Get-Date -f 'yyyy-MM-dd').txt"

foreach ($rg in $resourceGroups) {
    Write-Host "Processing $rg..." -ForegroundColor Cyan
    .\set-privatednsfallback.ps1 -ResourceGroupName $rg
}

Write-Host "All updates completed. Check logs in script directory." -ForegroundColor Green
```

## Example 5: Service Principal Authentication (for Automation)

```powershell
# Authenticate as service principal
$credential = New-Object -TypeName System.Management.Automation.PSCredential `
  -ArgumentList "YOUR_APP_ID", (ConvertTo-SecureString "YOUR_SECRET" -AsPlainText -Force)

Connect-AzAccount -ServicePrincipal -Credential $credential -TenantId "YOUR_TENANT_ID"

# Run the script
.\set-privatednsfallback.ps1 -ResourceGroupName "my-rg"
```

## Example 6: Audit Current Resolution Policies

```powershell
Connect-AzAccount

$resourceGroupName = "my-rg"
$zones = Get-AzPrivateDnsZone -ResourceGroupName $resourceGroupName

foreach ($zone in $zones) {
    Write-Host "Zone: $($zone.Name)" -ForegroundColor Cyan
    
    $links = Get-AzPrivateDnsVirtualNetworkLink `
        -ResourceGroupName $resourceGroupName `
        -ZoneName $zone.Name
    
    foreach ($link in $links) {
        $status = if ($link.ResolutionPolicy -eq "NxDomainRedirect") { "✓ Updated" } else { "✗ Needs Update" }
        Write-Host "  [$status] $($link.Name) - Policy: $($link.ResolutionPolicy)"
    }
}
```

## Interpreting the Output

### Simulation Output Example

```
Starting Private DNS Fallback script
Log file: C:\...\DNSFallbackLogs-20260102-143022.txt

Found Private DNS Zone: corp.local
  Evaluating VNet Link: vnet-link-1
    [SIMULATION] Link uses Default policy and would be updated.
      Current ResolutionPolicy: Default
      Would run: Set-AzPrivateDnsVirtualNetworkLink...
  
  Evaluating VNet Link: vnet-link-2
    [SIMULATION] Skipping: ResolutionPolicy already NxDomainRedirect.

Simulation completed. No changes were made.
```

### Live Mode Output Example

```
Starting Private DNS Fallback script
Found Private DNS Zone: corp.local
  Evaluating VNet Link: vnet-link-1
    Updated ResolutionPolicy to NxDomainRedirect
  
  Evaluating VNet Link: vnet-link-2
    Skipping: ResolutionPolicy already NxDomainRedirect.

Completed updating all applicable Private DNS VNet links.
```

## Troubleshooting

### Error: "Az.PrivateDns module is not installed"

```powershell
Install-Module Az.PrivateDns -Force
```

### Error: "No Private DNS zones found"

- Verify the resource group name is correct
- Check the resource group contains private DNS zones
- Verify you have Reader access to the resource group

### Log File Not Created

- Check you have write permissions to the script directory
- Verify disk space is available
- Run the script from a directory you own (not Program Files)
