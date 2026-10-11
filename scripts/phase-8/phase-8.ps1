<#
.SYNOPSIS
    Phase 8: P2 batch -- Conditional Access, PIM, Sentinel SIEM + SOAR (Logic App
    playbook). Expanded from the original plan to a full detect-triage-respond
    workflow per a later design pass (see README Deviations).

.NOTES
    TIME-BOXING, CRITICAL ON A TRIAL DEADLINE:
    Steps 1-7 (P2, CA, PIM, Sentinel, detection) are P2-dependent and must
    finish before the trial expires. Step 8 (Logic App SOAR layer) is NOT
    P2-dependent and can be built after the trial ends if time runs out --
    Logic Apps, automation rules and playbooks are standard Azure features,
    not gated by Entra ID P2. DO STEPS 1-7 FIRST. Attempt step 8 only once
    those are evidenced.

    Most of this phase is portal-driven by design -- CA, PIM, and Sentinel's
    own UI are more reliable and faster than their PowerShell/Graph equivalents
    for a first-time, time-pressured build. This script covers what's genuinely
    faster to script: the workspace, its cap, and config exports for evidence.
#>

$SpokeRg = "rg-avd-prod-centralindia-001"
$WorkspaceName = "law-avd-secops-001"
$Location = "centralindia"

# ============================================================
# STEP 0 -- DO THIS FIRST, BEFORE ANYTHING ELSE
# ============================================================
Write-Host "=== Confirm P2 trial status and exact expiry RIGHT NOW ===" -ForegroundColor Red
Write-Host "Portal: entra.microsoft.com > Identity > Overview > Licenses, or" -ForegroundColor Yellow
Write-Host "Billing > Licenses > All products > Microsoft Entra ID P2" -ForegroundColor Yellow
Write-Host "Screenshot the exact expiry timestamp NOW -- this is evidence item 01." -ForegroundColor Yellow

# ============================================================
# STEP 0b -- Break-glass account, BEFORE any CA policy
# ============================================================
<#
# Portal: Entra admin center > Identity > Users > + New user
# Cloud-only account, strong password stored OUTSIDE this repo.
# Do NOT put its real UPN in any committed file -- refer to it only as
# "break-glass account" in documentation, per the privacy rules for this repo.
#>

# ============================================================
# STEP 1-2 -- Log Analytics workspace + Sentinel (workspace is scriptable)
# ============================================================
Write-Host "`n=== Creating Log Analytics workspace with daily cap ===" -ForegroundColor Cyan
New-AzOperationalInsightsWorkspace -ResourceGroupName $SpokeRg -Name $WorkspaceName -Location $Location -Sku "PerGB2018"
Set-AzOperationalInsightsWorkspaceCapping -ResourceGroupName $SpokeRg -WorkspaceName $WorkspaceName -DailyQuotaGb 1

Write-Host "Workspace created. Enable Sentinel via portal: search 'Microsoft Sentinel' > +Create > select $WorkspaceName" -ForegroundColor Yellow

# ============================================================
# STEP 3 -- Data connectors (portal only -- no reliable scripted path
# for connector enablement across all connector types)
# ============================================================
<#
Portal: Sentinel > Data connectors
Connect: Microsoft Entra ID (sign-in logs), Azure Activity
Windows Security Events: via Azure Monitor Agent > Data Collection Rule >
  scoped to "Common" event set, NOT "All Events" -- cost control.
Export the DCR once created:
#>
<#
Get-AzDataCollectionRule -ResourceGroupName $SpokeRg | Where-Object { $_.Name -like "*avd*" } |
    ConvertTo-Json -Depth 10 | Out-File "sentinel/dcr.json"
#>

# ============================================================
# STEP 4 -- Conditional Access (portal only -- Graph API scripting is
# slower and riskier to get right under time pressure than the CA UI)
# ============================================================
<#
Portal: entra.microsoft.com > Protection > Conditional Access > + New policy
Name: CA-AVD-Require-MFA
Users: GRP-AVD-USERS (or a single test user)
Exclude: break-glass account -- DO THIS, don't skip it
Target resource: Azure Virtual Desktop
Grant: Require multifactor authentication
Enable: Report-only FIRST, validate in sign-in logs, THEN switch to On.

Export once created:
#>
<#
Connect-MgGraph -Scopes "Policy.Read.All"
Get-MgIdentityConditionalAccessPolicy | Where-Object { $_.DisplayName -eq "CA-AVD-Require-MFA" } |
    ConvertTo-Json -Depth 10 | Out-File "conditional-access/avd-mfa.json"
#>

# ============================================================
# STEP 5 -- PIM (portal only)
# ============================================================
<#
Portal: Entra admin center > Identity Governance > PIM > Azure roles
Role: Virtual Machine Contributor (narrowly scoped, not a powerful role)
Scope: rg-avd-prod-centralindia-001
Assignment type: Eligible
Then: My roles > Activate (once, for evidence)
#>

# ============================================================
# STEP 6 -- Detection rule (portal, KQL below for reference)
# ============================================================
<#
Portal: Sentinel > Analytics > + Create > Scheduled query rule
Name: DET-AVD-Repeated-Failed-SignIns

SigninLogs
| where ResultType != 0
| summarize FailedAttempts = count(), FirstSeen = min(TimeGenerated),
    LastSeen = max(TimeGenerated), IPs = make_set(IPAddress, 10)
    by UserPrincipalName, bin(TimeGenerated, 10m)
| where FailedAttempts >= 5
| project TimeGenerated = LastSeen, UserPrincipalName, FailedAttempts, FirstSeen, LastSeen, IPs

Run every 10-15 min, threshold creates an incident. Map to MITRE T1110
(Brute Force) if the rule wizard offers a MITRE mapping field.

Export once created:
#>
<#
Get-AzSentinelAlertRule -ResourceGroupName $SpokeRg -WorkspaceName $WorkspaceName |
    Where-Object { $_.DisplayName -eq "DET-AVD-Repeated-Failed-SignIns" } |
    ConvertTo-Json -Depth 10 | Out-File "sentinel/analytics-rule.json"
#>

# ============================================================
# STEP 7 -- Trigger the detection (controlled, not a real attack)
# ============================================================
Write-Host "`n=== Generate 5+ deliberate failed sign-ins against the TEST account only ===" -ForegroundColor Cyan
Write-Host "Use a wrong password on purpose, 5+ times within 10 min, against GRP-AVD-USERS's test user." -ForegroundColor Yellow
Write-Host "Wait for the scheduled rule to run, then check Sentinel > Incidents." -ForegroundColor Yellow

# ============================================================
# ---- CHECKPOINT: Steps 1-7 evidenced = Phase 8's P2-dependent core is
# done. If the trial is about to expire, STOP HERE and document the
# Logic App/SOAR layer (step 8) as a follow-up, not a blocker. ----
# ============================================================

# ============================================================
# STEP 8 -- SOAR layer (Logic App playbook) -- OPTIONAL, not P2-gated,
# can be done after the trial expires if time runs short
# ============================================================
<#
Portal: Logic Apps > + Create > Consumption plan
Name: la-avd-soc-001
Trigger: "Microsoft Sentinel Incident" (search Sentinel connector triggers)

Workflow (build in Logic App Designer):
  1. Trigger: When Sentinel incident created
  2. Parse incident fields: ID, alert name, severity, user, entities
  3. Compose a notification message (see README for the template text)
  4. Send notification (email/Teams connector -- use whatever you already have)
  5. Add incident comment via Sentinel connector action
  6. Add tags: SOC-Simulation, MITRE-T1110, FalsePositive-Test, AVD-Lab
  7. Close incident, classification = False Positive, reason = Controlled test

Then create the Automation Rule that invokes it:
Portal: Sentinel > Automation > + Create > Automation rule
Name: AUTO-AVD-FailedSignIn-SOAR
Trigger: When incident is created
Condition: Analytics rule name = DET-AVD-Repeated-Failed-SignIns
Action: Run playbook > la-avd-soc-001 > PB-AVD-FailedSignIn-Triage
#>

Write-Host "`nPhase 8 script complete. Steps 1-2 are scripted; 3-8 are portal-first" -ForegroundColor Cyan
Write-Host "by design. Prioritize 1-7 if the P2 trial is close to expiring --" -ForegroundColor Cyan
Write-Host "step 8 (Logic App SOAR) is not P2-gated and can follow later." -ForegroundColor Cyan
