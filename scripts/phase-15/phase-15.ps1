<#
.SYNOPSIS
    Phase 10: Troubleshooting helper commands.
.NOTES
    This is a diagnostic toolbox, not a deployment script. Run individual blocks as
    needed when investigating an issue. Copy the relevant output into
    docs/phase-10-troubleshooting/README.md under the matching issue entry, and into
    evidence/phase10-<issue-slug>-raw-output.txt.
#>

# ---- Network path: effective routes on a NIC ----
<#
Get-AzNetworkInterface -ResourceGroupName "<RG>" -Name "<NIC-NAME>" |
    Get-AzEffectiveRouteTable | Format-Table -AutoSize
#>

# ---- Network path: effective NSG rules on a NIC ----
<#
Get-AzNetworkInterface -ResourceGroupName "<RG>" -Name "<NIC-NAME>" |
    Get-AzEffectiveNetworkSecurityGroup | Format-Table -AutoSize
#>

# ---- Network path: IP flow verify (requires Network Watcher enabled in the region) ----
<#
Test-AzNetworkWatcherIPFlow -NetworkWatcher (Get-AzNetworkWatcher -Location "centralindia") `
    -TargetResourceId "<VM-RESOURCE-ID>" -Direction Inbound -Protocol TCP `
    -LocalIPAddress "<LOCAL-IP>" -LocalPort 443 -RemoteIPAddress "<REMOTE-IP>" -RemotePort 443
#>

# ---- Identity: confirm hybrid join state ----
# Run inside the session host:
<#
dsregcmd /status
#>

# ---- Identity: Kerberos ticket check for Azure Files ----
# Run inside a domain-joined VM after attempting to mount the share:
<#
klist
#>

# ---- Identity: force a sync cycle on the DC (if sync errors are suspected) ----
<#
Start-ADSyncSyncCycle -PolicyType Delta
Get-ADSyncScheduler
#>

# ---- FSLogix: check the profile attach log ----
<#
Get-Content "C:\ProgramData\FSLogix\Logs\Profile\Profile-*.log" -Tail 100
#>

# ---- Storage: confirm AD-based auth is actually active ----
<#
Get-AzStorageAccount -ResourceGroupName "<RG>" -Name "<STORAGE-ACCOUNT>" |
    Select-Object -ExpandProperty AzureFilesIdentityBasedAuthentication
#>

# ---- Quota: re-check current usage if a deployment fails with a quota error ----
$Location = "centralindia"
$QuotaPatterns = "standardBSv2Family|standardDSv6Family|standardDSv5Family|standardDv5Family|cores"
Get-AzVMUsage -Location $Location |
    Where-Object { $_.Name.Value -match $QuotaPatterns } |
    Select-Object @{N="Quota Name"; E={$_.Name.LocalizedValue}},
                  @{N="Current Usage"; E={$_.CurrentValue}},
                  @{N="Limit"; E={$_.Limit}},
                  @{N="Available"; E={$_.Limit - $_.CurrentValue}} |
    Format-Table -AutoSize

Write-Host "Diagnostic toolbox loaded. Uncomment and fill in the block relevant to your specific issue." -ForegroundColor Cyan
