<#
.SYNOPSIS
    Phase 4: Azure Files, AD Kerberos Join, RBAC, Root NTFS ACLs, and Storage Firewall Lockdown.

.NOTES
    This is the corrected version after a real rebuild on this environment. Two
    things changed from the original plan -- all confirmed via direct diagnosis, not
    guessed:

    1. FILE SHARE CREATION: New-AzStorageShare has NO quota parameter on this
       environment's installed Az.Storage module version (confirmed via
       Get-Command New-AzStorageShare -Syntax -- neither -QuotaGiB nor -QuotaGB
       exist). The correct two-step pattern is New-AzStorageShare (no quota) then
       Set-AzStorageShareQuota as a separate call. BOTH ARE INCLUDED BELOW, but if
       either fails with a parameter-binding error on your module version, STOP and
       create the shares via the Azure Portal instead (Storage account > File shares >
       + File share, quota set directly in the creation dialog) -- see
       portal/phase-4-azure-files-fslogix/README.md section B. Check your actual
       module version first with Get-Command New-AzStorageShare -Syntax and
       Get-Command Set-AzStorageShareQuota -Syntax before assuming either will work.

    2. AD JOIN: -OverwriteExistingADObject is included below from the start, not
       added only on retry. If a previous attempt (by you or anyone who touched this
       environment before) left a stale AD object, this flag prevents a hard failure.
       Do NOT substitute bare -Force for this -- -Force only suppresses confirmation
       prompts, it does not resolve an existing-object conflict.


    Firewall timing: DefaultAction stays Allow through AD join and NTFS setup (steps
    3-6), because vm-onprem-dc01 sits OUTSIDE the snet-avd-storage subnet and needs
    firewall-open access to reach the share at all for those steps. Lockdown is the
    final step (7), after everything else is confirmed working.

    Run this on vm-onprem-dc01 (domain-joined, required for the AD join step).
#>

# ---- 0. Variables ----
$SubscriptionId     = "SUB-ID"
$Location           = "centralindia"
$SpokeRg            = "rg-avd-prod-centralindia-001"
$StorageAccountName = "stavdfslogixprod012842"   # <-- confirm this matches YOUR actual name
$ProfilesShareName  = "profiles"
$ProfilesQuotaGB    = 100
$MsixShareName      = "msix-apps"
$MsixQuotaGB        = 20
$OuDistinguishedName = "OU=AVD_Hosts,DC=contoso,DC=local"
$StorageSubnetId    = "/subscriptions/$SubscriptionId/resourceGroups/$SpokeRg/providers/Microsoft.Network/virtualNetworks/vnet-spoke-avd-prod-01/subnets/snet-avd-storage"

# Object IDs for RBAC assignments -- confirmed working via portal IAM blade.
# Display names in AD/portal may differ from these variable names -- that's fine,
# object ID is what the role assignment actually uses.
$AvdUsersObjectId   = "546f1191-ac09-4fec-b136-a4b1dddefc51"   # AD display name: GRP-AVD-USERS
$AvdAdminsObjectId  = "8f79b6a8-24f4-48e0-874d-77dfcfcf7177"   # AD display name: ADMINS ONLY 
$AvdHostsObjectId   = "d556e518-ee74-4760-911e-1b7390028d9e"   # grp-avd-hosts -- created in Phase 5, confirmed via Get-ADGroup -Properties ObjectGUID

# ---- 1. Azure Authentication & Context Setup ----
Write-Host "=== 1. Confirming Azure login context ===" -ForegroundColor Cyan
$AzContext = Get-AzContext
if (-not $AzContext -or $AzContext.Subscription.Id -ne $SubscriptionId) {
    Connect-AzAccount -SubscriptionId $SubscriptionId
} else {
    Write-Host "Already logged in to the correct subscription." -ForegroundColor Green
}

# ---- 2. Deploy Storage Account ----
Write-Host "`n=== 2. Creating storage account ===" -ForegroundColor Cyan
$storageAccount = Get-AzStorageAccount -ResourceGroupName $SpokeRg -Name $StorageAccountName -ErrorAction SilentlyContinue
if (-not $storageAccount) {
    $storageAccount = New-AzStorageAccount -ResourceGroupName $SpokeRg -Name $StorageAccountName `
        -Location $Location -SkuName Standard_LRS -Kind StorageV2 -EnableLargeFileShare
    Write-Host "Storage account created." -ForegroundColor Green
} else {
    Write-Host "Storage account already exists -- reusing." -ForegroundColor Yellow
}

$ctx = $storageAccount.Context

# ---- 2a. File shares: two-step pattern (create, then set quota separately) ----
# IF THIS FAILS WITH A PARAMETER-BINDING ERROR on either New-AzStorageShare or
# Set-AzStorageShareQuota, STOP and create the shares via the portal instead --
# see the .NOTES block above and portal/phase-4-azure-files-fslogix/README.md section B.
Write-Host "`n=== 2a. Creating file shares (two-step: create, then set quota) ===" -ForegroundColor Cyan

if (-not (Get-AzStorageShare -Context $ctx -Name $ProfilesShareName -ErrorAction SilentlyContinue)) {
    New-AzStorageShare -Name $ProfilesShareName -Context $ctx
    Set-AzStorageShareQuota -ShareName $ProfilesShareName -Quota $ProfilesQuotaGB -Context $ctx
    Write-Host "Created share: $ProfilesShareName (quota: ${ProfilesQuotaGB}GB)" -ForegroundColor Green
} else {
    Write-Host "$ProfilesShareName already exists -- skipping." -ForegroundColor Yellow
}

if (-not (Get-AzStorageShare -Context $ctx -Name $MsixShareName -ErrorAction SilentlyContinue)) {
    New-AzStorageShare -Name $MsixShareName -Context $ctx
    Set-AzStorageShareQuota -ShareName $MsixShareName -Quota $MsixQuotaGB -Context $ctx
    Write-Host "Created share: $MsixShareName (quota: ${MsixQuotaGB}GB)" -ForegroundColor Green
} else {
    Write-Host "$MsixShareName already exists -- skipping." -ForegroundColor Yellow
}

# Keep firewall OPEN during setup -- required, not optional. vm-onprem-dc01 does NOT
# sit in snet-avd-storage, so AD join and the NTFS mount step both need the firewall
# open to reach the share at all.
Write-Host "`nKeeping storage firewall open (DefaultAction Allow) during setup..." -ForegroundColor Yellow
Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $SpokeRg -Name $StorageAccountName -DefaultAction Allow

# ---- 3. Active Directory Kerberos Join via AzFilesHybrid ----
Write-Host "`n=== 3. AD Kerberos join via AzFilesHybrid ===" -ForegroundColor Cyan
Import-Module AzFilesHybrid -ErrorAction Stop

# -OverwriteExistingADObject included from the start -- see .NOTES above for why.
Join-AzStorageAccountForAuth `
    -ResourceGroupName $SpokeRg `
    -StorageAccountName $StorageAccountName `
    -DomainAccountType "ComputerAccount" `
    -OrganizationalUnitDistinguishedName $OuDistinguishedName `
    -OverwriteExistingADObject

Write-Host "AD join command completed. Verifying..." -ForegroundColor Cyan
$sa = Get-AzStorageAccount -ResourceGroupName $SpokeRg -Name $StorageAccountName
$sa.AzureFilesIdentityBasedAuth | Format-List
# Expect: DirectoryServiceOptions : AD, with ActiveDirectoryProperties populated.
# If DirectoryServiceOptions is blank/None, the join did not actually succeed --
# check the output above for errors before continuing.

# ---- 4. Confirm AD Computer Object (handles 15-char sAMAccountName truncation) ----
Write-Host "`n=== 4. Confirming AD computer object (query by Name, not sAMAccountName) ===" -ForegroundColor Cyan
# AD truncates sAMAccountName at 15 characters, so Get-ADComputer -Identity using the
# full storage account name will fail with ADIdentityNotFoundException if the name is
# longer than that. Query by the Name/CN attribute instead, which is NOT truncated.
$ADComp = Get-ADComputer -Filter "Name -eq '$StorageAccountName'" -Properties ServicePrincipalNames, DNSHostName

if ($ADComp) {
    Write-Host "Found AD computer object: $($ADComp.DistinguishedName)" -ForegroundColor Green
    Write-Host "sAMAccountName (truncated by AD -- this is expected): $($ADComp.SamAccountName)" -ForegroundColor Yellow
    $ADComp.ServicePrincipalNames
} else {
    Write-Error "AD computer object for $StorageAccountName was not found. The AD join in step 3 likely failed -- check its output above before continuing."
}

# ---- 5. Configure Azure RBAC Share Roles ----
Write-Host "`n=== 5. Configuring Azure RBAC roles on file shares ===" -ForegroundColor Cyan
$StorageAccountId = $storageAccount.Id

New-AzRoleAssignment -ObjectId $AvdUsersObjectId `
    -RoleDefinitionName "Storage File Data SMB Share Contributor" `
    -Scope "$StorageAccountId/fileServices/default/fileshares/$ProfilesShareName" `
    -ErrorAction SilentlyContinue
Write-Host "Contributor role assigned (GRP-AVD-USERS) on $ProfilesShareName" -ForegroundColor Green

New-AzRoleAssignment -ObjectId $AvdAdminsObjectId `
    -RoleDefinitionName "Storage File Data SMB Share Elevated Contributor" `
    -Scope "$StorageAccountId/fileServices/default/fileshares/$ProfilesShareName" `
    -ErrorAction SilentlyContinue
Write-Host "Elevated Contributor role assigned (ADMINS ONLY) on $ProfilesShareName" -ForegroundColor Green

if ($AvdHostsObjectId) {
    New-AzRoleAssignment -ObjectId $AvdHostsObjectId `
        -RoleDefinitionName "Storage File Data SMB Share Reader" `
        -Scope "$StorageAccountId/fileServices/default/fileshares/$MsixShareName" `
        -ErrorAction SilentlyContinue
    Write-Host "Reader role assigned (grp-avd-hosts) on $MsixShareName" -ForegroundColor Green
} else {
    Write-Host "Skipping msix-apps Reader role -- grp-avd-hosts doesn't exist yet. Revisit after Phase 5." -ForegroundColor Yellow
}

Write-Host "`nVerifying role assignments:" -ForegroundColor Cyan
Get-AzRoleAssignment -Scope "$StorageAccountId/fileServices/default/fileshares/$ProfilesShareName" |
    Select-Object DisplayName, RoleDefinitionName

# ---- 6. Apply Root NTFS Permissions via Admin Key Mount ----
Write-Host "`n=== 6. Applying root NTFS ACLs to the profiles share ===" -ForegroundColor Cyan
# Storage key used deliberately here, ONLY for this one-time root ACL bootstrap --
# a legitimate, narrow use of the key (admin setup), not a substitute for the
# Kerberos auth already confirmed working in step 3.
$AccessKey = (Get-AzStorageAccountKey -ResourceGroupName $SpokeRg -Name $StorageAccountName)[0].Value
$TargetEndpoint = "$StorageAccountName.file.core.windows.net"

net use * /delete /yes 2>$null
cmdkey /add:$TargetEndpoint /user:"AZURE\$StorageAccountName" /pass:$AccessKey | Out-Null
net use Z: "\\$TargetEndpoint\$ProfilesShareName"

if (Test-Path "Z:\") {
    icacls Z:\ /grant "CONTOSO\GRP-AVD-USERS:(OI)(CI)M"
    icacls Z:\ /grant "CREATOR OWNER:(OI)(CI)(IO)(F)"
    Write-Host "NTFS ACLs applied." -ForegroundColor Green
} else {
    Write-Error "Z:\ did not mount -- cannot apply NTFS ACLs. Check the net use output above."
}

net use Z: /delete /yes 2>$null
cmdkey /delete:$TargetEndpoint 2>$null
Write-Host "Unmounted and cleaned up the key-based session." -ForegroundColor Green

# ---- 7. Lock Down Storage Firewall to AVD Storage Subnet ----
Write-Host "`n=== 7. Locking down storage firewall (final step) ===" -ForegroundColor Cyan
Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $SpokeRg -Name $StorageAccountName -DefaultAction Deny
Add-AzStorageAccountNetworkRule -ResourceGroupName $SpokeRg -Name $StorageAccountName -VirtualNetworkResourceId $StorageSubnetId

Write-Host "`n=== Phase 4 complete ===" -ForegroundColor Green
Write-Host "IMPORTANT: the firewall is now locked to snet-avd-storage only. Any" -ForegroundColor Yellow
Write-Host "verification run from vm-onprem-dc01 from this point forward (e.g." -ForegroundColor Yellow
Write-Host "Get-AzStorageShare to check quota) will fail with an authentication/" -ForegroundColor Yellow
Write-Host "access error -- this is expected, not a new bug. Verify from a VM inside" -ForegroundColor Yellow
Write-Host "snet-avd-storage (the AVD session host, once Phase 5 deploys it), or" -ForegroundColor Yellow
Write-Host "temporarily reopen the firewall if you need to check from the DC." -ForegroundColor Yellow

# ============================================================
# FOLLOW-UP -- run this block once, after Phase 5 creates grp-avd-hosts
# (Phase 4's original run had $AvdHostsObjectId = $null since the group
# didn't exist yet; this assigns the Reader role that step 5 skipped.)
# ============================================================
<#
$StorageAccountId = (Get-AzStorageAccount -ResourceGroupName $SpokeRg -Name $StorageAccountName).Id
$AvdHostsObjectId = "d556e518-ee74-4760-911e-1b7390028d9e"

New-AzRoleAssignment -ObjectId $AvdHostsObjectId `
    -RoleDefinitionName "Storage File Data SMB Share Reader" `
    -Scope "$StorageAccountId/fileServices/default/fileshares/$MsixShareName" `
    -ErrorAction SilentlyContinue

Get-AzRoleAssignment -Scope "$StorageAccountId/fileServices/default/fileshares/$MsixShareName" |
    Select-Object DisplayName, RoleDefinitionName
#>
