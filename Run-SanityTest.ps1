<#
.SYNOPSIS
    Master sanity-test orchestration script.

.DESCRIPTION
    Runs the full sanity test pipeline:
      1. Deploy pods/services and run baseline connectivity tests.
      2. Run churn test (KWOK-based scaling).
      3. Re-deploy pods/services, run recreate-dep traces, then re-test connectivity.
      4. Collect Windows logs and dump the combined test report.

.PARAMETER ChurnIterations
    Number of iterations for Run-ChurnTest.ps1 (default: 6)

.PARAMETER TimeoutSeconds
    Timeout in seconds for pod/service readiness waits (default: 300)

.PARAMETER LogDstPath
    Destination subfolder for Get-WindowsLogs.ps1 (default: WinKProxy)

.EXAMPLE
    .\Run-SanityTest.ps1
    .\Run-SanityTest.ps1 -ChurnIterations 10 -TimeoutSeconds 600
#>

param(
    [int]$ChurnIterations = 6,
    [int]$TimeoutSeconds = 300,
    [string]$LogDstPath = "WinKProxy"
)

$ErrorActionPreference = "Stop"

Import-Module -Force .\modules\constants.psm1

$Namespace       = $Global:NAMESPACE
$ServerLabel     = "app=$($Global:SERVER_POD_DEPLOYMENT)"
$ClientLabel     = "app=$($Global:CLIENT_POD_DEPLOYMENT)"
$ServerReplicas  = 8   # from Yamls\dep-test.yaml
$ClientReplicas  = 4   # from Yamls\Dep-Client.yaml
$TestLogsPath    = ".\ConnectivityLogs.txt"
$ReportPath      = ".\SanityTestReport.txt"

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Step {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "`n================================================================================" -ForegroundColor Yellow
    Write-Host " [$ts] $Message" -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow
}

function Wait-ForPods {
    param(
        [string]$LabelSelector,
        [int]$ExpectedCount
    )

    Write-Host "Waiting for $ExpectedCount pods ($LabelSelector) to be Running..." -ForegroundColor Cyan
    $startTime = Get-Date

    while ($true) {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
            Write-Host "`nTimeout waiting for pods ($LabelSelector). Expected: $ExpectedCount" -ForegroundColor Red
            kubectl get pods -n $Namespace -l $LabelSelector
            throw "Timeout waiting for pods with label '$LabelSelector'"
        }

        $pods = kubectl get pods -n $Namespace -l $LabelSelector -o json 2>$null | ConvertFrom-Json
        $running = @($pods.items | Where-Object { $_.status.phase -eq "Running" }).Count

        if ($running -ge $ExpectedCount) {
            Write-Host "`nAll $running pods ($LabelSelector) are Running." -ForegroundColor Green
            return
        }

        Write-Host "." -NoNewline
        Start-Sleep -Seconds 5

        # Force-delete pods stuck in Terminating
        kubectl get pods -n $Namespace --no-headers 2>$null |
            Select-String "Terminating" |
            ForEach-Object {
                $pod = ($_.ToString().Trim() -split '\s+')[0]
                kubectl delete pod $pod -n $Namespace --grace-period=0 --force 2>$null
            }
    }
}

function Wait-ForPodsTerminated {
    param([string]$LabelSelector)

    Write-Host "Waiting for pods ($LabelSelector) to terminate..." -ForegroundColor Cyan
    $startTime = Get-Date

    while ($true) {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
            Write-Host "`nTimeout waiting for pods to terminate ($LabelSelector)." -ForegroundColor Red
            throw "Timeout waiting for pods with label '$LabelSelector' to terminate"
        }

        $pods = kubectl get pods -n $Namespace -l $LabelSelector -o json 2>$null | ConvertFrom-Json
        if ($pods.items.Count -eq 0) {
            Write-Host "`nAll pods ($LabelSelector) terminated." -ForegroundColor Green
            return
        }

        Write-Host "." -NoNewline
        Start-Sleep -Seconds 5

        kubectl get pods -n $Namespace --no-headers 2>$null |
            Select-String "Terminating" |
            ForEach-Object {
                $pod = ($_.ToString().Trim() -split '\s+')[0]
                kubectl delete pod $pod -n $Namespace --grace-period=0 --force 2>$null
            }
    }
}

function Wait-ForAllPodsAndServices {
    Wait-ForPods -LabelSelector $ServerLabel -ExpectedCount $ServerReplicas
    Wait-ForPods -LabelSelector $ClientLabel -ExpectedCount $ClientReplicas
    Write-Host "All pods and services are ready." -ForegroundColor Green
}

function Wait-ForAllPodsDeleted {
    Wait-ForPodsTerminated -LabelSelector $ServerLabel
    Wait-ForPodsTerminated -LabelSelector $ClientLabel
    Write-Host "All pods deleted." -ForegroundColor Green
}

# ============================================================================
# Pipeline
# ============================================================================

$pipelineStart = Get-Date

# ---------- Phase 1: Deploy & baseline test ----------
Write-Step "PHASE 1 - Creating Pods and Services"
& .\Create-PodsAndServices.ps1
Wait-ForAllPodsAndServices

Write-Step "PHASE 1 - Running Basic Tests (baseline)"
& .\Run-BasicTests.ps1

Write-Step "PHASE 1 - Saving baseline test report to $ReportPath"
$header = @(
    "================================================================================"
    " SANITY TEST REPORT - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "================================================================================"
    ""
    "===== PHASE 1: Baseline Connectivity Tests ====="
    ""
)
$header | Set-Content -Path $ReportPath
if (Test-Path $TestLogsPath) {
    Get-Content $TestLogsPath | Add-Content -Path $ReportPath
} else {
    "WARNING: $TestLogsPath not found." | Add-Content -Path $ReportPath
}

Write-Step "PHASE 1 - Deleting Pods and Services"
& .\Delete-PodsAndServices.ps1
Wait-ForAllPodsDeleted

# ---------- Phase 2: Churn test ----------
Write-Step "PHASE 2 - Running Churn Test ($ChurnIterations iterations)"
& .\Run-ChurnTest.ps1 -Iterations $ChurnIterations

# ---------- Phase 3: Recreate-dep, then re-test ----------
Write-Step "PHASE 3 - Creating Pods and Services"
& .\Create-PodsAndServices.ps1
Wait-ForAllPodsAndServices

Write-Step "PHASE 3 - Running Recreate-Dep"
& .\Run-Recreate-Dep.ps1

Write-Step "PHASE 3 - Waiting for Pods and Services after Recreate-Dep"
Wait-ForAllPodsAndServices

Write-Step "PHASE 3 - Running Basic Tests (post-churn)"
& .\Run-BasicTests.ps1

Write-Step "PHASE 3 - Appending post-churn test report to $ReportPath"
$separator = @(
    ""
    "===== PHASE 3: Post-Churn Connectivity Tests ====="
    ""
)
$separator | Add-Content -Path $ReportPath
if (Test-Path $TestLogsPath) {
    Get-Content $TestLogsPath | Add-Content -Path $ReportPath
} else {
    "WARNING: $TestLogsPath not found." | Add-Content -Path $ReportPath
}

Write-Step "PHASE 3 - Deleting Pods and Services"
& .\Delete-PodsAndServices.ps1
Wait-ForAllPodsDeleted

# ---------- Phase 4: Collect logs ----------
Write-Step "PHASE 4 - Collecting Windows Logs (DstPath: $LogDstPath)"
& .\Get-WindowsLogs.ps1 -DstPath $LogDstPath

# ---------- Dump report ----------
$pipelineEnd = Get-Date
$elapsed = $pipelineEnd - $pipelineStart

$footer = @(
    ""
    "================================================================================"
    " Sanity test completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    " Total elapsed: $($elapsed.ToString('hh\:mm\:ss'))"
    "================================================================================"
)
$footer | Add-Content -Path $ReportPath

Write-Step "SANITY TEST COMPLETE - Dumping Report"
Write-Host ""
Get-Content $ReportPath
Write-Host "`nReport saved to: $((Resolve-Path $ReportPath).Path)" -ForegroundColor Green
