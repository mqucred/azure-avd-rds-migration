<#
.SYNOPSIS
    Phase 3: Hybrid identity with Entra Connect.
.NOTES
    Entra Connect installation and the device-options wizard are GUI-driven and
    cannot be scripted end-to-end. This file gives you the verification commands
    and the pieces that CAN be scripted (OU scoping filter reference, verification).
    See portal/phase-3-hybrid-identity/README.md for the click-by-click GUI steps.
    No new VMs in this phase — no quota impact.
#>

# ---- Manual: on vm-onprem-dc01, download and run the Entra Connect installer ----
# https://www.microsoft.com/en-us/download/details.aspx?id=47594
# Choose "Customize" during setup, NOT "Use express settings" — Express settings
# skips the device options screen entirely and hybrid join cannot be configured
# after the fact without re-running the wizard.

# ---- Manual: during the wizard ----
# 1. Connect to Azure AD: sign in with a Global Administrator account.
# 2. Connect your directories: select the contoso.local forest, use an enterprise
#    admin account when prompted.
# 3. Domain/OU filtering: scope sync to OU=AVD_Users and OU=AVD_Hosts only
#    (do not sync the whole domain in a lab).
# 4. Optional features: select "Password Hash Synchronization".
# 5. Configure device options: select "Configure Hybrid Azure AD join", choose the
#    Windows 10 or later / Windows Server 2019 or later SCP option, select the
#    contoso.local forest.

# ---- Verification (run these after the wizard completes and a sync cycle runs) ----

# On the DC: confirm the Service Connection Point was created
Get-ADObject -Filter { objectClass -eq "serviceConnectionPoint" } `
    -SearchBase "CN=Configuration,DC=contoso,DC=local" |
    Where-Object { $_.Name -like "*ADSync*" -or $_.DistinguishedName -like "*Device Registration*" }

# On the DC: confirm the sync scheduler ran without errors
Get-ADSyncScheduler

# In a browser: confirm both users show as synced in the Entra admin center
# https://entra.microsoft.com > Identity > Users > (select avduser01) > check "Directory synced"

Write-Host "Phase 3 requires manual GUI steps in Entra Connect. Run the verification commands above only after the wizard finishes and a sync cycle completes (can take a few minutes)." -ForegroundColor Cyan
