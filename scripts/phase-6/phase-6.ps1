<#
.SYNOPSIS
    Phase 6: Profile migration and user cutover.
.NOTES
    No new VMs in this phase — no quota impact.
    frx.exe ships with the FSLogix agent, already installed on the session host in Phase 5.
    Most of this phase runs on vm-onprem-dc01 (source) or vm-avd-host-0 (destination mount test).
#>

# ---- 1. Look up the SID for the folder naming requirement ----
# Run on the DC (or any machine with the AD module)
$targetUser = "avduser01"
$sid = (Get-ADUser $targetUser -Properties SID).SID.Value
$destinationFolderName = "${sid}_${targetUser}"
Write-Host "FSLogix destination folder must be named exactly: $destinationFolderName" -ForegroundColor Yellow

# ---- 2. frx copy-profile — run on the session host or any machine with FSLogix installed ----
# Source is the legacy roaming profile path from Phase 1.
# Destination is the profiles share, in the exact SID_username folder name from step 1.
<#
$frxPath = "C:\Program Files\FSLogix\Apps\frx.exe"
$sourceProfilePath = "\\vm-onprem-dc01\legacy-profiles\avduser01.V2"
$destinationVhdPath = "\\stavdfslogixprod012842.file.core.windows.net\profiles\$destinationFolderName\Profile_$targetUser.vhdx"

& $frxPath copy-profile -filename $destinationVhdPath -sid $sid -username "contoso\$targetUser" -src-dir $sourceProfilePath
#>

# ---- 3. Verify the container landed correctly ----
<#
Test-Path "\\stavdfslogixprod012842.file.core.windows.net\profiles\$destinationFolderName"
#>

# ---- 4. Parallel run: confirm avduser02 works cleanly on AVD before touching avduser01 ----
# Manual: sign in as avduser02 through the Windows App, confirm a fresh profile container
# is created without issue, before proceeding to cut over avduser01.

# ---- 5. Cutover: remove avduser01's legacy RDS access ----
# On vm-onprem-rds01, run in an elevated PowerShell session:
<#
# Remove avduser01 from whichever group grants RDS logon rights, e.g.:
Remove-ADGroupMember -Identity "Remote Desktop Users" -Members "avduser01" -Confirm:$false
#>

# ---- 6. Sign in as avduser01 through AVD and confirm the migrated data is present ----
# Manual: use the Windows App, confirm the Phase 1 test files/desktop changes appear.

Write-Host "Phase 6 is largely manual verification. Steps 2, 3, 5 need the exact paths and SIDs from your environment substituted in before running." -ForegroundColor Cyan
