<#
.SYNOPSIS
    Consolidated Phase 6-8 troubleshooting and validation reference
    for azure-avd-rds-migration.

.DESCRIPTION
    This is a REFERENCE / VALIDATION script. It intentionally avoids destructive
    deployment and deletion operations. Commands are grouped by the layers that
    were actually tested during the lab.

    Phases:
      6 - Legacy profile / FSLogix validation
      7 - App Attach / CIM troubleshooting / VHDX validation
      8 - Sentinel analytics rule / SOAR validation

    Replace paths only when reproducing the lab. Do not put passwords, PFX
    passwords, tokens or client secrets into this file.
#>

[CmdletBinding()]
param(
    [switch]$RunReadOnlyChecks
)

# ---------------------------------------------------------------------------
# VARIABLES
# ---------------------------------------------------------------------------

$Location           = "centralindia"
$ResourceGroup      = "rg-avd-prod-centralindia-001"
$HostPoolName       = "hp-avd-prod-01"
$SessionHost        = "vm-avd-host-0"
$StorageAccount     = "stavdfslogixprod012842"
$ProfileShare       = "profiles"
$MsixShare          = "msix-apps"
$WorkspaceName      = "law-avd-secops-001"
$SentinelRuleName   = "DET-AVD-Repeated-Failed-SignIns"
$LogicAppName       = "la-avd-soc-001"

$LegacyProfile      = "\\vm-onprem-dc01\legacy-profiles\avduser01.V6"
$LegacyNtUserDat    = "$LegacyProfile\NTUSER.DAT"

$AzureProfileRoot   = "\\$StorageAccount.file.core.windows.net\$ProfileShare"
$AzureMsixRoot      = "\\$StorageAccount.file.core.windows.net\$MsixShare"

$CimPath            = "$AzureMsixRoot\NotepadPlusPlus\NotepadPlusPlus.cim"
$VhdxPath           = "$AzureMsixRoot\NotepadPlusPlus\NotepadPlusPlus.vhdx"

$FslogixExe         = "C:\Program Files\FSLogix\Apps\frx.exe"
# NOTE: FSLogix writes one log file per day (Profile-YYYYMMDD.log). A hardcoded
# date breaks the day after it's written. Resolve the current day's file at
# run time instead, falling back to the most recently modified log if today's
# doesn't exist yet (e.g. running this before any sign-in today).
$FslogixLogDir      = "C:\ProgramData\FSLogix\Logs\Profile"

Write-Host "`n=== Azure AVD RDS Migration — Phase 6-8 Validation ===" -ForegroundColor Cyan
Write-Host "Resource group : $ResourceGroup"
Write-Host "Host pool      : $HostPoolName"
Write-Host "Session host   : $SessionHost"
Write-Host "Storage        : $StorageAccount"
Write-Host ""

# ---------------------------------------------------------------------------
# PHASE 6 — LEGACY PROFILE / FSLOGIX
# ---------------------------------------------------------------------------

function Test-LegacyProfileAccess {
    Write-Host "`n[Phase 6] Legacy NTUSER.DAT access" -ForegroundColor Cyan

    Get-Item $LegacyNtUserDat -ErrorAction Stop |
        Select-Object FullName, Length, LastWriteTime, Attributes
}

function Test-LegacyHiveLoad {
    Write-Host "`n[Phase 6] Registry hive load/unload" -ForegroundColor Cyan

    if (-not (Test-Path $LegacyNtUserDat)) {
        throw "Legacy NTUSER.DAT not found: $LegacyNtUserDat"
    }

    & reg.exe load HKU\TempAvdUser $LegacyNtUserDat

    if ($LASTEXITCODE -ne 0) {
        throw "reg load failed with exit code $LASTEXITCODE"
    }

    & reg.exe query HKU\TempAvdUser | Select-Object -First 20

    & reg.exe unload HKU\TempAvdUser

    if ($LASTEXITCODE -ne 0) {
        throw "reg unload failed with exit code $LASTEXITCODE"
    }

    Write-Host "Hive load/unload completed successfully." -ForegroundColor Green
}

function Test-FslogixBinary {
    Write-Host "`n[Phase 6] FSLogix frx.exe" -ForegroundColor Cyan

    if (-not (Test-Path $FslogixExe)) {
        throw "FSLogix frx.exe not found: $FslogixExe"
    }

    (Get-Item $FslogixExe).VersionInfo |
        Select-Object FileVersion, ProductVersion
}

function Test-AzureProfileShare {
    Write-Host "`n[Phase 6] Azure Files profile share" -ForegroundColor Cyan

    Test-Path $AzureProfileRoot

    if (Test-Path $AzureProfileRoot) {
        Get-ChildItem $AzureProfileRoot -Force |
            Select-Object Name, Length, LastWriteTime, Attributes
    }
}

function Test-FslogixLog {
    Write-Host "`n[Phase 6] Recent FSLogix profile log" -ForegroundColor Cyan

    $fslogixLog = Get-ChildItem -Path $FslogixLogDir -Filter "Profile-*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($fslogixLog) {
        Write-Host "Using: $($fslogixLog.FullName)" -ForegroundColor DarkGray
        Get-Content $fslogixLog.FullName -Tail 200
    }
    else {
        Write-Warning "No FSLogix profile log found in: $FslogixLogDir"
    }
}

# ---------------------------------------------------------------------------
# PHASE 7 — AZURE FILES / APP ATTACH CONNECTIVITY
# ---------------------------------------------------------------------------

function Test-AzureFilesConnectivity {
    Write-Host "`n[Phase 7] Azure Files TCP 445" -ForegroundColor Cyan

    Test-NetConnection `
        "$StorageAccount.file.core.windows.net" `
        -Port 445

    Write-Host "`n[Phase 7] CIM path" -ForegroundColor Cyan
    Test-Path $CimPath

    Write-Host "`n[Phase 7] VHDX path" -ForegroundColor Cyan
    Test-Path $VhdxPath
}

function Test-SystemCimPath {
    <#
        This is a reminder of the SYSTEM-context test used in the lab.
        Run the following from a SYSTEM-context PowerShell session:

        Test-Path "\\stavdfslogixprod012842.file.core.windows.net\msix-apps\NotepadPlusPlus\NotepadPlusPlus.cim"
    #>

    Write-Host "`nSYSTEM-context CIM test:" -ForegroundColor Yellow
    Write-Host 'Test-Path "\\stavdfslogixprod012842.file.core.windows.net\msix-apps\NotepadPlusPlus\NotepadPlusPlus.cim"'
}

function Test-CimPrerequisites {
    Write-Host "`n[Phase 7] CIM / mount prerequisites" -ForegroundColor Cyan

    Get-Command Mount-CimDiskImage -ErrorAction SilentlyContinue

    Get-Service |
        Where-Object {
            $_.Name -in @("CimFS", "wcifs")
        } |
        Select-Object Name, Status, StartType

    Get-Module CimDiskImage -ListAvailable |
        Sort-Object Version -Descending |
        Select-Object -First 5 Name, Version, Path
}

function Test-CimMountReference {
    <#
        Diagnostic reference only.

        The lab reproduced:
          ErrorCode 298
          "Too many posts were made to a semaphore"

        Local testing also produced:
          ErrorCode 0
          "The operation completed successfully"

        ErrorCode 0 was NOT accepted as proof of a successful mount.
    #>

    Write-Host "`n[Phase 7] CIM mount troubleshooting reference" -ForegroundColor Yellow
    Write-Host "Observed native failure: ErrorCode 298 — Too many posts were made to a semaphore"
    Write-Host "Observed misleading result: ErrorCode 0 — operation completed successfully"
}

# ---------------------------------------------------------------------------
# PHASE 7 — VHDX VALIDATION
# ---------------------------------------------------------------------------

function Get-VhdxHash {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "VHDX not found: $Path"
    }

    Get-FileHash -Path $Path -Algorithm SHA256
}

function Test-VhdxHash {
    Write-Host "`n[Phase 7] Azure Files VHDX SHA256" -ForegroundColor Cyan

    if (-not (Test-Path $VhdxPath)) {
        throw "Azure Files VHDX not accessible: $VhdxPath"
    }

    Get-FileHash -Path $VhdxPath -Algorithm SHA256
}

function Test-VirtualDiskState {
    Write-Host "`n[Phase 7] Virtual disk state" -ForegroundColor Cyan

    Get-Disk |
        Where-Object { $_.FriendlyName -eq "Msft Virtual Disk" } |
        Select-Object Number, FriendlyName, OperationalStatus,
                      PartitionStyle, Size

    Get-Volume |
        Where-Object { $_.DriveLetter } |
        Select-Object DriveLetter, FileSystem, FileSystemLabel,
                      HealthStatus, Size
}

function Test-AppxPackageState {
    Write-Host "`n[Phase 7] Final session-host App Attach package state" -ForegroundColor Cyan

    Get-AppxPackage -AllUsers |
        Where-Object {
            $_.Name -like "*NotepadPlusPlus*"
        } |
        Select-Object `
            Name,
            Publisher,
            Architecture,
            Version,
            PackageFullName,
            PackageFamilyName,
            PackageUserInformation,
            IsPartiallyStaged,
            Status,
            SignatureKind
}

# ---------------------------------------------------------------------------
# PHASE 7 — MSIX SIGNING REFERENCE
# ---------------------------------------------------------------------------

function Verify-MsixSignature {
    param(
        [Parameter(Mandatory)]
        [string]$MsixPath,

        [Parameter(Mandatory)]
        [string]$SignToolPath
    )

    if (-not (Test-Path $MsixPath)) {
        throw "MSIX not found: $MsixPath"
    }

    if (-not (Test-Path $SignToolPath)) {
        throw "SignTool not found: $SignToolPath"
    }

    Get-AuthenticodeSignature $MsixPath

    & $SignToolPath verify /pa /all /v $MsixPath

    if ($LASTEXITCODE -ne 0) {
        throw "SignTool verification failed with exit code $LASTEXITCODE"
    }
}

# Known lab result:
# SignTool 10.0.28000.0 -> "file format not recognized"
# SignTool 10.0.18362.0 -> signing successful

# ---------------------------------------------------------------------------
# PHASE 7 — MSIXMGR REFERENCE
# ---------------------------------------------------------------------------

function Show-CimCreationCommand {
    <#
        Reference command used for CimFS image creation.

        The destination directory must exist first.
        A CIM image is multiple files and all sidecars must be copied.

        & "C:\msixmgr\msixmgr.exe" -Unpack `
            -packagePath "C:\AppAttachLab\TestApp.msix" `
            -destination "C:\msix\TestApp\TestApp.cim" `
            -applyACLs `
            -create `
            -fileType cim `
            -rootDirectory apps
    #>

    Write-Host "`nCIM creation reference:" -ForegroundColor Yellow
    Write-Host '& "C:\msixmgr\msixmgr.exe" -Unpack -packagePath "C:\AppAttachLab\TestApp.msix" -destination "C:\msix\TestApp\TestApp.cim" -applyACLs -create -fileType cim -rootDirectory apps'
}

function Show-CimCopyCommand {
    Write-Host "`nCIM copy reference:" -ForegroundColor Yellow
    Write-Host 'Copy-Item "C:\msix\TestApp\*" -Destination "\\stavdfslogixprod012842.file.core.windows.net\msix-apps\TestApp\" -Recurse -Force'
}

# ---------------------------------------------------------------------------
# PHASE 8 — SENTINEL KQL
# ---------------------------------------------------------------------------

$query = @'
SigninLogs
| where TimeGenerated > ago(10m)
| where ResultType == 50126
| summarize FailedAttempts=count(), FirstSeen=min(TimeGenerated), LastSeen=max(TimeGenerated) by UserPrincipalName
| where FailedAttempts >= 3
| where LastSeen - FirstSeen <= 10m
| project TimeGenerated=LastSeen, UserPrincipalName, FailedAttempts, FirstSeen, LastSeen
'@

function Show-SentinelQuery {
    Write-Host "`n[Phase 8] Final Sentinel KQL" -ForegroundColor Cyan
    $query
}

# Quick-verify query -- narrower than the detection rule itself, used to
# confirm raw 50126 events exist and their timing/count before waiting on
# the scheduled analytics rule to pick them up.
$verifyQuery = @'
SigninLogs
| where TimeGenerated > ago(15m)
| where ResultType == 50126
| project TimeGenerated, UserPrincipalName, ResultType, ResultDescription
| order by TimeGenerated desc
'@

function Show-SentinelVerifyQuery {
    Write-Host "`n[Phase 8] Quick-verify query (raw 50126 events, last 15 min)" -ForegroundColor Cyan
    $verifyQuery
}

function New-TestFailedSignIns {
    <#
        Generates deliberate failed sign-in attempts (Entra error 50126 --
        invalid username/password) against ONE test account, spaced closely
        enough to land inside the detection rule's 10-minute window.

        This is a controlled simulation for testing the detection pipeline --
        not a real credential attack. Use a test account only (e.g. avduser02),
        never a production or admin identity.

        50089 (expired flow/token) is a DIFFERENT error code and will NOT
        satisfy this detection rule -- if your verification query shows 50089
        instead of 50126, the attempts aren't landing as genuine bad-password
        failures and won't trigger the rule.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$UserPrincipalName,

        [int]$AttemptCount = 3,

        [int]$DelaySeconds = 20
    )

    Write-Host "`n[Phase 8] Generating $AttemptCount deliberate failed sign-ins for $UserPrincipalName" -ForegroundColor Cyan
    Write-Host "Spaced $DelaySeconds seconds apart -- stay well inside the rule's 10-minute window." -ForegroundColor Yellow

    $badCred = Get-Credential -UserName $UserPrincipalName -Message "Enter a DELIBERATELY WRONG password -- used $AttemptCount times to trigger 50126"

    for ($i = 1; $i -le $AttemptCount; $i++) {
        try {
            Connect-AzAccount -Credential $badCred -ErrorAction Stop
        }
        catch {
            Write-Host "Attempt $i of $AttemptCount failed as expected: $($_.Exception.Message)" -ForegroundColor DarkGray
        }

        if ($i -lt $AttemptCount) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    Write-Host "`nDone. Wait ~1-2 minutes for sign-in log ingestion, then run Show-SentinelVerifyQuery" -ForegroundColor Green
    Write-Host "against the workspace and confirm $AttemptCount rows, same user, all within a few minutes." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# PHASE 8 — SENTINEL RULE DEPLOYMENT REFERENCE
# ---------------------------------------------------------------------------

function New-FinalSentinelRuleReference {
    <#
        Deployment reference used in the lab.

        This is intentionally a function so importing this script does not
        modify Azure. Execute the body only when recreating the rule.
    #>

    if (-not (Get-Command New-AzSentinelAlertRule -ErrorAction SilentlyContinue)) {
        Write-Warning "New-AzSentinelAlertRule is not available in the current session."
        return
    }

    New-AzSentinelAlertRule `
        -ResourceGroupName $ResourceGroup `
        -WorkspaceName $WorkspaceName `
        -Kind Scheduled `
        -Enabled `
        -DisplayName $SentinelRuleName `
        -Severity Medium `
        -Query $query `
        -QueryFrequency (New-TimeSpan -Minutes 5) `
        -QueryPeriod (New-TimeSpan -Minutes 10) `
        -TriggerOperator "GreaterThan" `
        -TriggerThreshold 0 `
        -CreateIncident
}

function Remove-OldSentinelRuleReference {
    <#
        Old GUI-created rule removed during the lab:

        Rule ID:
        c321c30d-b8cb-4989-b84b-6f5d75bf2800

        This function is intentionally NOT executed automatically.
    #>

    $OldRuleId = "c321c30d-b8cb-4989-b84b-6f5d75bf2800"

    Write-Host "`nOld rule removal reference only:" -ForegroundColor Yellow

    @"
Remove-AzSentinelAlertRule `
    -ResourceGroupName "$ResourceGroup" `
    -WorkspaceName "$WorkspaceName" `
    -RuleId "$OldRuleId" `
    -Confirm:`$false
"@
}

# ---------------------------------------------------------------------------
# PHASE 8 — FINAL SENTINEL STATE
# ---------------------------------------------------------------------------

function Show-FinalSentinelState {
    Write-Host "`n[Phase 8] Final Sentinel rule state" -ForegroundColor Cyan

    @"
Display name       : $SentinelRuleName
Enabled             : True
Kind                : Scheduled
Severity            : Medium
Query frequency     : 00:05:00
Query period        : 00:10:00
Trigger operator    : GreaterThan
Trigger threshold   : 0
Create incident     : True
Suppression         : False
Grouping            : False
Rule ID             : af9a201c-7b3a-40ba-b9d4-9bc9b96f6524
"@
}

# ---------------------------------------------------------------------------
# PHASE 8 — LOGIC APP / SOAR REFERENCE
# ---------------------------------------------------------------------------

function Show-FinalSoarArchitecture {
    Write-Host "`n[Phase 8] Final SOAR architecture" -ForegroundColor Cyan

    @"
3 x ResultType 50126
        |
        v
DET-AVD-Repeated-Failed-SignIns
        |
        v
Sentinel Incident #15
        |
        v
Automation Rule
        |
        v
$LogicAppName
        |
        +--> DEBUG_IncidentData
        |
        +--> Entities - Get Accounts
        |
        +--> Send an email (V2)
        |
        v
Outlook notification received
"@
}

function Show-LogicAppExpressions {
    Write-Host "`n[Phase 8] Final Logic App expressions" -ForegroundColor Cyan

    @"
ObjectId:
@triggerBody()?['object']?['id']

IncidentArmId:
@triggerBody()?['object']?['properties']?['incidentArmId']

Related entities:
@triggerBody()?['object']?['properties']?['relatedEntities']

Account output used in the final email:
@{body('Entities_-_Get_Accounts')?['Accounts']}
"@
}

# ---------------------------------------------------------------------------
# RUN READ-ONLY CHECKS
# ---------------------------------------------------------------------------

if ($RunReadOnlyChecks) {
    Test-LegacyProfileAccess
    Test-LegacyHiveLoad
    Test-FslogixBinary
    Test-AzureProfileShare
    Test-FslogixLog

    Test-AzureFilesConnectivity
    Test-CimPrerequisites
    Test-CimMountReference
    Test-VirtualDiskState
    Test-VhdxHash
    Test-AppxPackageState

    Show-SentinelQuery
    Show-SentinelVerifyQuery
    Show-FinalSentinelState
    Show-FinalSoarArchitecture
    Show-LogicAppExpressions
}
else {
    Write-Host "`nReference loaded. No Azure resources were changed." -ForegroundColor Green
    Write-Host "Run with -RunReadOnlyChecks to execute the non-destructive local checks." -ForegroundColor Yellow
}

Write-Host "`nNOTE: New-TestFailedSignIns is NOT part of the read-only checks above --" -ForegroundColor DarkGray
Write-Host "it deliberately generates failed sign-ins and prompts for a credential." -ForegroundColor DarkGray
Write-Host "Call it explicitly: New-TestFailedSignIns -UserPrincipalName 'avduser02@contoso.onmicrosoft.com'" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# FINAL ERROR CARD
# ---------------------------------------------------------------------------
<#

CIM:
  Error 87
  HRESULT -2147024809
  0x80070057
  ERROR_INVALID_PARAMETER

  Error 298
  "Too many posts were made to a semaphore"

  ErrorCode 0
  "The operation completed successfully"
  (mount still failed)

SIGNTOOL:
  10.0.28000.0 -> format not recognized
  10.0.18362.0 -> successful

SOAR:
  Add Comment V3 -> 400 / Incident Arm id missing
  Final workflow -> Add Comment removed
  Automatic Sentinel -> Logic App -> Outlook -> SUCCESS

#>
