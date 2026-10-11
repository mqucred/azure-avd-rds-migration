<#
.SYNOPSIS
    Phase 7: App Attach (current Microsoft feature name — "MSIX App Attach" was
    deprecated June 1, 2025 and removed from Microsoft's documentation).

.NOTES
    Every command and recommendation in this script is sourced directly from
    Microsoft Learn, fetched live during this project (not from memory), on
    2026-10-03:
      - https://learn.microsoft.com/en-us/azure/virtual-desktop/app-attach-overview
      - https://learn.microsoft.com/en-us/azure/virtual-desktop/app-attach-create-msix-image
      - https://learn.microsoft.com/en-us/azure/virtual-desktop/app-attach-setup

    KEY CORRECTIONS vs. older guidance / earlier drafts of this script:
    1. Image format: CimFS (.cim) is Microsoft's current RECOMMENDED format, not
       VHDX. "We recommend using CIM for best performance, particularly with
       Windows 11... We don't recommend using VHD; use VHDX instead [if not CIM]."
       Only use CimFS if session hosts run Windows 11 (yours do).
    2. msixmgr syntax uses -fileType cim and -rootDirectory apps, not the older
       -vhdSize/-create-only VHDX-era flags.
    3. A CIM image is MULTIPLE FILES, not one: a .cim metadata file plus
       objectid_* and region_* data files with no extension. All of them must be
       copied to the share together -- copying only the .cim file is incomplete.
    4. Portal workflow is "Azure Virtual Desktop > App Attach > +Create" -- a
       top-level blade, not nested under the host pool as older guidance describes.
    5. Package assignment (to host pools, users/groups) happens at the App Attach
       package level directly. RemoteApp publishing is a SEPARATE, optional step --
       you do NOT add MSIX/Appx apps to a desktop application group at all; per
       Microsoft: "You can't add MSIX or Appx applications to the desktop
       application group with App Attach."
    6. Az.DesktopVirtualization module version 4.2.1 or later is required for the
       App Attach cmdlets -- check and update before running any
       Get-AzWvdAppAttachPackage / New-AzWvdAppAttachPackage commands.
    7. Disk images should be excluded from antivirus scanning (they're read-only)
       and should NOT share a file share with FSLogix profile containers --
       Microsoft explicitly recommends against this. msix-apps (Phase 4) is
       already a separate share from profiles -- correct, keep it that way.

    Run Phase 7A (cert/signing) on a packaging workstation -- vm-avd-host-0 itself
    is fine for a lab. Phase 7B (msixmgr) needs admin rights on a Windows 10/11
    device. Phase 7C/D are portal or PowerShell from wherever you manage Azure.
#>

# ---- 0. Variables ----
$Location           = "centralindia"
$SpokeRg            = "rg-avd-prod-centralindia-001"
$HostPoolName       = "hp-avd-prod-01"
$StorageAccountName = "stavdfslogixprod012842"
$MsixShareName      = "msix-apps"
$AppGroupName       = "ag-avd-remoteapp-01"   # RemoteApp group -- optional, Phase 7E
$WorkspaceName      = "ws-avd-prod"

# ---- Pre-check: confirm Az.DesktopVirtualization module version ----
Write-Host "=== 0. Confirming Az.DesktopVirtualization module version (need 4.2.1+) ===" -ForegroundColor Cyan
Get-Module Az.DesktopVirtualization -ListAvailable | Select-Object Name, Version
# If below 4.2.1 or not installed:
# Install-Module -Name Az.DesktopVirtualization -Force -AllowClobber -MinimumVersion 4.2.1

# ============================================================
# PHASE 7A — Packaging workstation: certificate and signing
# Run on a Windows 10/11 machine with admin rights (vm-avd-host-0 works for a lab)
# ============================================================

Write-Host "`n=== 7A.1 Create a self-signed code-signing certificate ===" -ForegroundColor Cyan
Write-Host "Self-signed certs are supported ONLY for test environments per Microsoft's own guidance." -ForegroundColor Yellow

<#
# The Subject must match the MSIX package's own Publisher field exactly, or
# signing will fail -- check your .msix package's AppxManifest.xml Publisher
# value first (or use Get-AppxPackageManifest after a test unpack) rather than
# assume it matches a value you pick here.
$cert = New-SelfSignedCertificate `
    -Type Custom `
    -Subject "CN=YourPublisherNameHere" `
    -KeyUsage DigitalSignature `
    -FriendlyName "AVD App Attach Test Cert" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")
    # 1.3.6.1.5.5.7.3.3 is the code-signing certificate object identifier --
    # confirmed from Microsoft's own doc text, not assumed.

# ---- 7A.2 Export PFX (private key, for signing) and CER (public, for trust) ----
$pfxPassword = ConvertTo-SecureString -String "<CHANGE-ME>" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "C:\AppAttachLab\signing-cert.pfx" -Password $pfxPassword
Export-Certificate -Cert $cert -FilePath "C:\AppAttachLab\signing-cert.cer"

# ---- 7A.3 Trust the CER on vm-avd-host-0 (and any other session host) ----
# Self-signed: install to Trusted Root Certification Authorities.
# Microsoft explicitly recommends against distributing this via GPO/Intune --
# "should only be used for testing."
Import-Certificate -FilePath "C:\AppAttachLab\signing-cert.cer" -CertStoreLocation "Cert:\LocalMachine\Root"

# ---- 7A.4 Sign the MSIX package ----
# Requires signtool.exe from the Windows SDK.
& "C:\Program Files (x86)\Windows Kits\10\bin\<version>\x64\signtool.exe" sign `
    /fd SHA256 /a /f "C:\AppAttachLab\signing-cert.pfx" /p "<CHANGE-ME>" `
    "C:\AppAttachLab\TestApp.msix"

# ---- 7A.5 Verify the signature ----
& "C:\Program Files (x86)\Windows Kits\10\bin\<version>\x64\signtool.exe" verify /pa "C:\AppAttachLab\TestApp.msix"
#>

# ============================================================
# PHASE 7B — Create the CIM image
# Run as administrator on a Windows 10/11 device. The device's Windows version
# must be <= the version your session hosts run, or the CIM may not mount there.
# ============================================================

Write-Host "`n=== 7B.1 Download msixmgr ===" -ForegroundColor Cyan
Write-Host "Download from https://aka.ms/msixmgr and extract to a folder." -ForegroundColor Yellow

<#
# ---- 7B.2 Create a destination folder FIRST -- msixmgr does not create it ----
New-Item -Path "C:\msix\TestApp" -ItemType Directory -Force

# ---- 7B.3 Create the CIM image ----
# Exact syntax confirmed from Microsoft Learn, fetched live during this project.
& "C:\msixmgr\msixmgr.exe" -Unpack `
    -packagePath "C:\AppAttachLab\TestApp.msix" `
    -destination "C:\msix\TestApp\TestApp.cim" `
    -applyACLs `
    -create `
    -fileType cim `
    -rootDirectory apps

# Expected output: "Successfully created the CIM file: C:\msix\TestApp\TestApp.cim"

# ---- 7B.4 Confirm ALL the CIM files were created (not just the .cim itself) ----
# A CIM image is multiple files: the .cim metadata file, plus objectid_* and
# region_* data files. All must be copied together.
Get-ChildItem "C:\msix\TestApp" -Force
#>

Write-Host "`n=== 7B.5 Copy the ENTIRE CIM folder contents to the msix-apps share ===" -ForegroundColor Cyan
<#
# Copy every file in the destination folder, not just the .cim -- the
# objectid_*/region_* files are required alongside it.
Copy-Item "C:\msix\TestApp\*" -Destination "\\$StorageAccountName.file.core.windows.net\$MsixShareName\TestApp\" -Recurse -Force

# ---- 7B.6 Confirm it landed, and confirm NTFS/share read access is already
# correct from Phase 4's grp-avd-hosts Reader role ----
Get-ChildItem "\\$StorageAccountName.file.core.windows.net\$MsixShareName\TestApp\"
#>

# ============================================================
# PHASE 7C — Create the App Attach package
# Portal: Azure Virtual Desktop > App Attach > +Create (a top-level blade, not
# nested under the host pool). PowerShell equivalent below, for the record --
# confirm the exact cmdlet syntax against your installed Az.DesktopVirtualization
# module version (4.2.1+) before relying on it, since this cmdlet surface is
# newer and more likely to have version-specific differences.
# ============================================================

Write-Host "`n=== 7C. App Attach package creation -- portal recommended for first attempt ===" -ForegroundColor Cyan
Write-Host "Portal path: Azure Virtual Desktop > App Attach > +Create" -ForegroundColor Yellow
Write-Host "Basics: subscription, resource group, Host pool = $HostPoolName, Location = $Location" -ForegroundColor Yellow
Write-Host "Image path: Select from storage account > $StorageAccountName > $MsixShareName > TestApp.cim" -ForegroundColor Yellow
Write-Host "Registration type: On-demand (default, recommended -- doesn't slow sign-in)" -ForegroundColor Yellow
Write-Host "State: Active" -ForegroundColor Yellow

# ============================================================
# PHASE 7D — Assign the package (separate step from RemoteApp publishing)
# ============================================================

Write-Host "`n=== 7D. Assignment -- do this regardless of whether you also do RemoteApp ===" -ForegroundColor Cyan
Write-Host "Portal: open the App Attach package > Host pools > +Assign > $HostPoolName" -ForegroundColor Yellow
Write-Host "Portal: open the App Attach package > Users > +Add > avduser01 or GRP-AVD-USERS" -ForegroundColor Yellow
Write-Host "NOTE: per Microsoft, this alone makes the app available in a DESKTOP session." -ForegroundColor Yellow
Write-Host "RemoteApp (7E below) is only needed if you specifically want RemoteApp delivery." -ForegroundColor Yellow

# ============================================================
# PHASE 7E — RemoteApp publishing (OPTIONAL)
# ============================================================
<#
New-AzWvdApplicationGroup -ResourceGroupName $SpokeRg -Name $AppGroupName -Location $Location `
    -HostPoolArmPath (Get-AzWvdHostPool -ResourceGroupName $SpokeRg -Name $HostPoolName).Id `
    -ApplicationGroupType "RemoteApp"

# Portal from here: Application groups > ag-avd-remoteapp-01 > Applications > +Add
# Application source = App Attach > select package > select the application inside it

# Add the RemoteApp group to the workspace
Update-AzWvdWorkspace -ResourceGroupName $SpokeRg -Name $WorkspaceName `
    -ApplicationGroupReference (Get-AzWvdApplicationGroup -ResourceGroupName $SpokeRg -Name $AppGroupName).Id
#>

# ============================================================
# PHASE 7F — Validation
# ============================================================

Write-Host "`n=== 7F. Validation checklist ===" -ForegroundColor Cyan
<#
# Sign in via Windows App as the assigned user, confirm the app appears and launches.

# Confirm it is NOT locally installed on the session host (proves App Attach,
# not a local install)
Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*TestApp*" }
# Expect: no result -- if it IS installed locally, App Attach isn't actually
# the delivery mechanism and something is wrong.
#>

Write-Host "`nPhase 7 script complete. 7A/7B are commented templates -- fill in your actual" -ForegroundColor Cyan
Write-Host "app name, certificate subject (must match the MSIX Publisher field), and" -ForegroundColor Cyan
Write-Host "paths before running. 7C/7D are portal-first by design for a first attempt." -ForegroundColor Cyan
