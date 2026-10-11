<#
.SYNOPSIS
    Phase 5: AVD host pool, hybrid join, FSLogix.

.NOTES
    This is the final, corrected version after a multi-day troubleshooting cycle.
    Summary of what actually happened, for context on why this script looks the way
    it does (full detail in docs/phase-10-troubleshooting/README.md, Issues 4-7):

    1. First vm-avd-host-0 deployment got stuck in a self-contradictory state (portal
       "Running", host pool "Shutdown") and was deleted and redeployed clean.
    2. No NAT Gateway exists in this environment -- a temporary public IP is required
       on the session host NIC, not just during setup but on an ONGOING basis, since
       the AVD agent needs continuous outbound access to Microsoft's broker/diagnostics
       URLs (Geneva monitoring), not just one-time installer downloads.
    3. FSLogix was initially left at its own defaults rather than configured
       explicitly, which produced .vhd (not .vhdx) containers in SID-first naming.
       The full Microsoft Learn "Standard" configuration example was applied
       (https://learn.microsoft.com/en-us/fslogix/concepts-configuration-examples),
       which includes VolumeType=VHDX and FlipFlopProfileDirectoryName=1.
    4. Applying FlipFlopProfileDirectoryName to an environment with EXISTING SID-first
       containers causes FSLogix to treat them as orphaned and create new, separate
       username-first containers alongside them -- exactly as Microsoft's own docs warn.
       The old SID-first containers were deleted (not just left behind) to avoid
       confusion, except one that was locked and left as a known, harmless leftover.
    5. After reconfiguration, both avduser01 and avduser02 hit a "Windows temporary
       profile" warning in the FSLogix log on first sign-in -- NOT caused by the AD
       profile path (a plausible-sounding but incorrect theory was raised and ruled
       out directly against the logs) but by genuinely CORRUPTED VHDX containers,
       visible in the portal as CORRUPT_<guid>_Profile_avduser01.VHDX files. Deleting
       the corrupted containers let FSLogix create fresh, working ones on next sign-in.
    6. Final state confirmed clean: FSLogix log shows LogonStage=5(Logon_Complete),
       correct VHDRootFilePath pointing at the real share, no temp-profile warning.
       A test file on avduser01's Desktop was confirmed to survive a genuine
       sign-out/sign-in cycle across more than 12 hours (verified both via
       Test-Path and the storage account's own LastModified timestamp).

    Run VM deployment and domain-join portions from wherever you manage Azure;
    FSLogix registry configuration, verification, and log checks run ON
    vm-avd-host-0 itself, via Bastion or RDP through the (ongoing) public IP.
#>

# ---- 0. Variables ----
$Location        = "centralindia"
$SpokeRg         = "rg-avd-prod-centralindia-001"
$HostPoolName    = "hp-avd-prod-01"
$WorkspaceName   = "ws-avd-prod"
$AppGroupName    = "ag-avd-desktop-01"
$HostVmName      = "vm-avd-host-0"
$VmSize          = "Standard_D2s_v5"   # confirmed available: DSv5 family, see quota plan
$SpokeVNetName   = "vnet-spoke-avd-prod-01"
$HostsSubnetName = "snet-avd-hosts"
$AdminUsername   = "azlabadmin"
$TimeZone        = "India Standard Time"
$ImagePublisher  = "MicrosoftWindowsDesktop"
$ImageOffer      = "windows-11"
$ImageSku        = "win11-23h2-avd"   # verify current SKU string against Microsoft docs, these change
$StorageAccountName = "stavdfslogixprod012842"

$AdminCredential = Get-Credential -UserName $AdminUsername -Message "Enter the local admin password for the session host"

# ---- 1. Host pool, application group, workspace ----
Write-Host "=== 1. Creating host pool, app group, workspace ===" -ForegroundColor Cyan

New-AzWvdHostPool -ResourceGroupName $SpokeRg -Name $HostPoolName -Location $Location `
    -HostPoolType "Pooled" -LoadBalancerType "BreadthFirst" -PreferredAppGroupType "Desktop" `
    -MaxSessionLimit 4

New-AzWvdApplicationGroup -ResourceGroupName $SpokeRg -Name $AppGroupName -Location $Location `
    -HostPoolArmPath (Get-AzWvdHostPool -ResourceGroupName $SpokeRg -Name $HostPoolName).Id `
    -ApplicationGroupType "Desktop"

New-AzWvdWorkspace -ResourceGroupName $SpokeRg -Name $WorkspaceName -Location $Location `
    -ApplicationGroupReference (Get-AzWvdApplicationGroup -ResourceGroupName $SpokeRg -Name $AppGroupName).Id

# ---- 2. Registration token ----
$regInfo = New-AzWvdRegistrationInfo -ResourceGroupName $SpokeRg -HostPoolName $HostPoolName `
    -ExpirationTime (Get-Date).AddDays(1)
Write-Host "Registration token (expires in 1 day): $($regInfo.Token)" -ForegroundColor Yellow

# ---- 3. NIC with a public IP -- KEPT ONGOING, not removed after setup ----
# See .NOTES item 2: the AVD agent needs continuous outbound access to Microsoft's
# broker/Geneva endpoints, not just one-time installer downloads. A NAT Gateway is
# the architecturally cleaner permanent fix and is planned as a separate, deliberate
# deployment later -- not swapped in under deadline pressure.
Write-Host "`n=== 3. Creating NIC with public IP (kept attached on an ongoing basis) ===" -ForegroundColor Cyan

$pip = New-AzPublicIpAddress -ResourceGroupName $SpokeRg -Name "pip-avd-host-0-temp" `
    -Location $Location -AllocationMethod Static -Sku Standard

$vnet = Get-AzVirtualNetwork -ResourceGroupName $SpokeRg -Name $SpokeVNetName
$hostsSubnet = $vnet.Subnets | Where-Object { $_.Name -eq $HostsSubnetName }

$hostNic = New-AzNetworkInterface -Name "$HostVmName-nic" -ResourceGroupName $SpokeRg `
    -Location $Location -SubnetId $hostsSubnet.Id -PublicIpAddressId $pip.Id

# ---- 4. Deploy the session host VM ----
Write-Host "`n=== 4. Deploying session host VM ===" -ForegroundColor Cyan

$hostVmConfig = New-AzVMConfig -VMName $HostVmName -VMSize $VmSize |
    Set-AzVMOperatingSystem -Windows -ComputerName $HostVmName -Credential $AdminCredential -TimeZone $TimeZone |
    Set-AzVMSourceImage -PublisherName $ImagePublisher -Offer $ImageOffer -Skus $ImageSku -Version latest |
    Add-AzVMNetworkInterface -Id $hostNic.Id

New-AzVM -ResourceGroupName $SpokeRg -Location $Location -VM $hostVmConfig

Write-Host "Session host VM deployed with a public IP attached. Connect via RDP/Bastion using that IP." -ForegroundColor Green

# ---- 5. Manual -- inside the session host, after it boots ----
# Add-Computer -DomainName "contoso.local" -OUPath "OU=AVD_Hosts,DC=contoso,DC=local" -Credential $AdminCredential -Restart
# Install the AVD Agent and Boot Loader using the registration token from step 2.
# Confirm hybrid join: dsregcmd /status

# ---- 6. FSLogix FULL "Standard" configuration (run ON vm-avd-host-0) ----
# Source: https://learn.microsoft.com/en-us/fslogix/concepts-configuration-examples
# This is the complete Standard tier config, not just the minimum Enabled/VHDLocations
# pair used in earlier drafts of this script.
<#
$fslogixRegPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
New-Item -Path $fslogixRegPath -Force

# Required
Set-ItemProperty -Path $fslogixRegPath -Name "Enabled" -Value 1 -Type DWord

# Recommended
Set-ItemProperty -Path $fslogixRegPath -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -Type DWord
Set-ItemProperty -Path $fslogixRegPath -Name "FlipFlopProfileDirectoryName" -Value 1 -Type DWord
Set-ItemProperty -Path $fslogixRegPath -Name "LockedRetryCount" -Value 3 -Type DWord
Set-ItemProperty -Path $fslogixRegPath -Name "LockedRetryInterval" -Value 15 -Type DWord
Set-ItemProperty -Path $fslogixRegPath -Name "ReAttachIntervalSeconds" -Value 15 -Type DWord
Set-ItemProperty -Path $fslogixRegPath -Name "ReAttachRetryCount" -Value 3 -Type DWord
Set-ItemProperty -Path $fslogixRegPath -Name "VolumeType" -Value "VHDX" -Type String

# Default (set explicitly, not left implicit)
Set-ItemProperty -Path $fslogixRegPath -Name "ProfileType" -Value 0 -Type DWord
Set-ItemProperty -Path $fslogixRegPath -Name "SizeInMBs" -Value 30000 -Type DWord

# Environment-specific
Set-ItemProperty -Path $fslogixRegPath -Name "VHDLocations" -Value "\\stavdfslogixprod012842.file.core.windows.net\profiles" -Type MultiString

# Confirm every value took
Get-ItemProperty -Path $fslogixRegPath
#>

# ---- 7. Create grp-avd-hosts and add the session host computer account (run from the DC) ----
<#
New-ADGroup -Name "grp-avd-hosts" -GroupScope Global -Path "OU=AVD_Hosts,DC=contoso,DC=local"
Add-ADGroupMember -Identity "grp-avd-hosts" -Members "vm-avd-host-0$"
Get-ADGroup -Identity "grp-avd-hosts" -Properties ObjectGUID | Select-Object Name, ObjectGUID
#>

# ---- 8. Assign users to the application group ----
<#
New-AzRoleAssignment -SignInName "avduser01@contoso.onmicrosoft.com" `
    -RoleDefinitionName "Desktop Virtualization User" `
    -ResourceName $AppGroupName -ResourceGroupName $SpokeRg -ResourceType "Microsoft.DesktopVirtualization/applicationgroups"
New-AzRoleAssignment -SignInName "avduser02@contoso.onmicrosoft.com" `
    -RoleDefinitionName "Desktop Virtualization User" `
    -ResourceName $AppGroupName -ResourceGroupName $SpokeRg -ResourceType "Microsoft.DesktopVirtualization/applicationgroups"
#>

# ---- 9. Verify Available status ----
Write-Host "`n=== 9. Verify session host status ===" -ForegroundColor Cyan
Get-AzWvdSessionHost -ResourceGroupName $SpokeRg -HostPoolName $HostPoolName | Select-Object Name, Status
Write-Host "NOTE: 'NeedsAssistance' with a Geneva URL error can appear even when the host" -ForegroundColor Yellow
Write-Host "works fine for real sign-ins -- confirmed via Test-NetConnection to the broker" -ForegroundColor Yellow
Write-Host "URL and a successful live sign-in, not just this status field alone." -ForegroundColor Yellow

# ---- 10. IF reconfiguring FSLogix on an environment with EXISTING containers ----
# (only relevant if you change VolumeType or FlipFlopProfileDirectoryName after
# containers already exist -- see .NOTES item 4)
<#
$ctx = (Get-AzStorageAccount -ResourceGroupName $SpokeRg -Name $StorageAccountName).Context
$oldFolders = @(
    "S-1-5-21-<domain-sid>_avduser01",
    "S-1-5-21-<domain-sid>_avduser02"
)
foreach ($folder in $oldFolders) {
    $files = Get-AzStorageFile -ShareName "profiles" -Context $ctx | Where-Object { $_.Name -eq $folder }
    # List actual contents and delete the real file(s) by name before removing the folder --
    # Get-AzStorageFile -Path <folder> can echo the folder itself rather than its children
    # on some module versions, so confirm the real filename first:
    Get-AzStorageFile -ShareName "profiles" -Path $folder -Context $ctx
    # Remove-AzStorageFile -ShareName "profiles" -Path "$folder/<real-filename>" -Context $ctx
    # Remove-AzStorageDirectory -ShareName "profiles" -Path $folder -Context $ctx
}
#>

# ---- 11. Post-sign-in verification: check for corrupted containers ----
# If a user hits a "temporary profile" warning after a clean reconfiguration, check
# the share for CORRUPT_*.VHDX files in the portal before assuming a config problem --
# this was the actual root cause found in this environment, not a registry/AD setting.
<#
$ctx = (Get-AzStorageAccount -ResourceGroupName $SpokeRg -Name $StorageAccountName).Context
Get-AzStorageFile -ShareName "profiles" -Context $ctx | Where-Object { $_.Name -like "*CORRUPT*" }
# If found, delete them (via portal or Remove-AzStorageFile) and have the user sign in
# again -- a fresh container will be created automatically.
#>

Write-Host "`nPhase 5 script complete through VM deployment. Steps 5-8 are manual." -ForegroundColor Cyan
Write-Host "Step 6 uses the FULL Microsoft Learn Standard FSLogix config, not just" -ForegroundColor Cyan
Write-Host "Enabled/VHDLocations. See docs/phase-10-troubleshooting/README.md for the" -ForegroundColor Cyan
Write-Host "full story if you hit a temporary-profile warning or corrupted containers." -ForegroundColor Cyan

# ============================================================
# EVIDENCE CAPTURE -- run ON vm-avd-host-0, after a confirmed clean sign-in
# ============================================================
<#
dsregcmd /status | Out-File -FilePath "C:\dsregcmd-status.txt" -Encoding UTF8
Get-Content "C:\dsregcmd-status.txt" | Select-String "AzureAdJoined|DomainJoined|DeviceId|TenantId"

$outputFile = "C:\phase5-fslogix-clean-attach-evidence.txt"
$report = @()
$report += "FSLogix clean attach verification -- captured $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$report += "hostname: $(hostname)"
$report += "whoami: $(whoami)"
$report += (Get-Content "C:\ProgramData\FSLogix\Logs\Profile\Profile-*.log" -Tail 60 |
    Select-String "Attached|temporary profile|FSLogix|VHDRootFilePath|LogonStage" | Out-String)
$report | Out-File -FilePath $outputFile -Encoding UTF8
Get-Content $outputFile

# Persistence proof: create a test file, sign out, sign back in (ideally after a real
# gap, not the same session), then:
Test-Path "C:\Users\avduser01\Desktop\<your-test-file>.txt"
#>
