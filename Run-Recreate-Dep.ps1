param(
    [int]$Iterations = 20,
    [string]$YamlFile = ".\Yamls\dep-test.yaml",
    [int]$DeleteWaitSeconds = 20,
    [int]$CreateWaitSeconds = 20,
    [string]$Namespace = "demo",
    [string]$DaemonSetLabel = "hpc-ds-win22",
    [string]$TraceFile = "server.etl",
    [string]$LocalTraceDir = ".\traces"
)

# Get all HPC pods
$hpcPods = @(kubectl get pods -n $Namespace -l name=$DaemonSetLabel -o jsonpath='{.items[*].metadata.name}' | ForEach-Object { $_ -split '\s+' } | Where-Object { $_ })
if ($hpcPods.Count -eq 0) {
    Write-Host "No HPC pods found in namespace '$Namespace' with label name=$DaemonSetLabel" -ForegroundColor Red
    exit 1
}
Write-Host "Found $($hpcPods.Count) HPC pod(s): $($hpcPods -join ', ')" -ForegroundColor Green

function Start-Trace {
    Write-Host "`n===== Starting trace on all nodes =====" -ForegroundColor Yellow
    foreach ($pod in $hpcPods) {
        Write-Host "  Starting trace on $pod ..." -ForegroundColor Cyan
        kubectl exec -n $Namespace $pod -- powershell -Command "netsh trace start provider='{0C885E0D-6EB6-476C-A048-2457EED3A5C1}' level=3 tracefile=$TraceFile report=di persistent=yes"
    }
}

function Stop-Trace {
    Write-Host "`n===== Stopping trace on all nodes =====" -ForegroundColor Yellow
    foreach ($pod in $hpcPods) {
        Write-Host "  Stopping trace on $pod ..." -ForegroundColor Cyan
        kubectl exec -n $Namespace $pod -- powershell -Command "netsh trace stop"
    }
}

function Loop-DepRecreation {
    Write-Host "`n===== Starting churn loop ($Iterations iterations) =====" -ForegroundColor Yellow
    for ($i = 1; $i -le $Iterations; $i++) {
        Write-Host "Iteration $i of $Iterations" -ForegroundColor Cyan
        kubectl delete -f $YamlFile
        Start-Sleep -Seconds $DeleteWaitSeconds
        kubectl create -f $YamlFile
        Start-Sleep -Seconds $CreateWaitSeconds
    }
}

function Convert-Trace {
    Write-Host "`n===== Converting ETL on all nodes =====" -ForegroundColor Yellow
    foreach ($pod in $hpcPods) {
        Write-Host "  Converting ETL on $pod ..." -ForegroundColor Cyan
        kubectl exec -n $Namespace $pod -- powershell -Command "netsh trace convert $TraceFile"
    }
}

function Copy-Trace {
    $txtFile = [System.IO.Path]::ChangeExtension($TraceFile, ".txt")
    $zipFile = [System.IO.Path]::ChangeExtension($TraceFile, ".zip")
    if (-not (Test-Path $LocalTraceDir)) {
        New-Item -ItemType Directory -Path $LocalTraceDir -Force | Out-Null
    }

    Write-Host "`n===== Compressing, copying, and expanding trace files =====" -ForegroundColor Yellow
    foreach ($pod in $hpcPods) {
        Write-Host "  Removing old $zipFile on $pod ..." -ForegroundColor Cyan
        kubectl exec -n $Namespace $pod -- powershell -Command "Remove-Item -Path '$zipFile' -Force -ErrorAction SilentlyContinue"

        Write-Host "  Compressing on $pod ..." -ForegroundColor Cyan
        kubectl exec -n $Namespace $pod -- powershell -Command "
            `$items = @('$txtFile')
            if (Test-Path 'c:\LocalDumps\*') { `$items += @(Get-ChildItem 'c:\LocalDumps\*' | Select-Object -ExpandProperty FullName) }
            Compress-Archive -Path `$items -DestinationPath '$zipFile' -Force
        "

        $localZip = Join-Path $LocalTraceDir "$pod-$zipFile"
        Write-Host "  Copying $zipFile from $pod -> $localZip" -ForegroundColor Cyan
        $copied = $false
        for ($retry = 1; $retry -le 10; $retry++) {
            try {
                kubectl cp "${Namespace}/${pod}:${zipFile}" $localZip
                if (Test-Path $localZip) {
                    $copied = $true
                    break
                }
            } catch {}
            Write-Host "    Retry $retry/10 failed, waiting 5s ..." -ForegroundColor Red
            Start-Sleep -Seconds 5
        }
        if (-not $copied) {
            Write-Host "  Failed to copy from $pod after 10 retries, skipping." -ForegroundColor Red
            continue
        }

        Write-Host "  Expanding $localZip ..." -ForegroundColor Cyan
        Expand-Archive -Path $localZip -DestinationPath (Join-Path $LocalTraceDir $pod) -Force
        Remove-Item -Path $localZip -Force -ErrorAction SilentlyContinue
    }
}

function Copy-ServerTxt {
    $serverTxt = "server.txt"
    $serverZip = "server-txt.zip"
    if (-not (Test-Path $LocalTraceDir)) {
        New-Item -ItemType Directory -Path $LocalTraceDir -Force | Out-Null
    }

    Write-Host "`n===== Compressing and copying server.txt from all nodes =====" -ForegroundColor Yellow
    foreach ($pod in $hpcPods) {
        # Check if server.txt exists on the pod
        $exists = kubectl exec -n $Namespace $pod -- powershell -Command "Test-Path '$serverTxt'" 2>$null
        if ($exists -ne 'True') {
            Write-Host "  $serverTxt not found on $pod, skipping." -ForegroundColor Red
            continue
        }

        Write-Host "  Removing old $serverZip on $pod ..." -ForegroundColor Cyan
        kubectl exec -n $Namespace $pod -- powershell -Command "Remove-Item -Path '$serverZip' -Force -ErrorAction SilentlyContinue"

        Write-Host "  Compressing $serverTxt on $pod ..." -ForegroundColor Cyan
        kubectl exec -n $Namespace $pod -- powershell -Command "
            Compress-Archive -Path '$serverTxt' -DestinationPath '$serverZip' -Force
        "

        $localZip = Join-Path $LocalTraceDir "$pod-$serverZip"
        Write-Host "  Copying $serverZip from $pod -> $localZip" -ForegroundColor Cyan
        $copied = $false
        for ($retry = 1; $retry -le 10; $retry++) {
            try {
                kubectl cp "${Namespace}/${pod}:${serverZip}" $localZip
                if (Test-Path $localZip) {
                    $copied = $true
                    break
                }
            } catch {}
            Write-Host "    Retry $retry/10 failed, waiting 5s ..." -ForegroundColor Red
            Start-Sleep -Seconds 5
        }
        if (-not $copied) {
            Write-Host "  Failed to copy from $pod after 10 retries, skipping." -ForegroundColor Red
            continue
        }

        Write-Host "  Expanding $localZip ..." -ForegroundColor Cyan
        Expand-Archive -Path $localZip -DestinationPath (Join-Path $LocalTraceDir $pod) -Force
        Remove-Item -Path $localZip -Force -ErrorAction SilentlyContinue
    }
}

function Check-CrashDumps {
    Write-Host "`n===== Checking for crash dumps on all nodes =====" -ForegroundColor Yellow
    $anyCrash = $false
    foreach ($pod in $hpcPods) {
        $dumpFiles = kubectl exec -n $Namespace $pod -- powershell -Command "Get-ChildItem 'c:\LocalDumps\*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name" 2>$null
        if ($dumpFiles) {
            $anyCrash = $true
            Write-Host "  $pod has crash dumps: $dumpFiles" -ForegroundColor Red
        } else {
            Write-Host "  $pod : No crash dumps found." -ForegroundColor Green
        }
    }
    if ($anyCrash) {
        Write-Host "`n  ERROR: HNS CRASHED! Crash dumps were found on one or more nodes." -ForegroundColor Red
    } else {
        Write-Host "`n  No crash dumps detected on any node." -ForegroundColor Green
    }
}

function Remove-Trace {
    $txtFile = [System.IO.Path]::ChangeExtension($TraceFile, ".txt")
    Write-Host "`n===== Removing trace files from all nodes =====" -ForegroundColor Yellow
    foreach ($pod in $hpcPods) {
        Write-Host "  Removing $TraceFile and $txtFile on $pod ..." -ForegroundColor Cyan
        kubectl exec -n $Namespace $pod -- powershell -Command "Remove-Item -Path $TraceFile, $txtFile -Force -ErrorAction SilentlyContinue"
    }
}

function Enable-CrashDump {
    Write-Host "`n===== Enabling crash dumps on all nodes =====" -ForegroundColor Yellow
    $crashDumpCommands = @(
        'mkdir c:\LocalDumps -ErrorAction SilentlyContinue'
        'New-Item -Path ''HKLM:\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps'' -Force -ErrorAction SilentlyContinue'
        'Set-ItemProperty -Path ''HKLM:\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps'' -Name DumpCount -Value 50 -Type DWord'
        'Set-ItemProperty -Path ''HKLM:\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps'' -Name DumpType -Value 2 -Type DWord'
        'Set-ItemProperty -Path ''HKLM:\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps'' -Name DumpFolder -Value ''c:\LocalDumps'' -Type ExpandString'
        'Remove-Item -Recurse -Force c:\LocalDumps\* -ErrorAction SilentlyContinue'
        'Restart-Service -Force hns'
    ) -join '; '

    foreach ($pod in $hpcPods) {
        Write-Host "  Enabling crash dumps on $pod ..." -ForegroundColor Cyan
        kubectl exec -n $Namespace $pod -- powershell -Command $crashDumpCommands
    }
}

function Get-ProcessIds {
    param([string]$Label)
    Write-Host "`n===== Capturing HNS & KubeProxy PIDs ($Label) =====" -ForegroundColor Yellow
    $pidMap = @{}
    foreach ($pod in $hpcPods) {
        Write-Host "  Querying PIDs on $pod ..." -ForegroundColor Cyan
        $pids = kubectl exec -n $Namespace $pod -- powershell -Command "
            `$hns = Get-Process -Name 'svchost' -ErrorAction SilentlyContinue | Where-Object { `$_.Modules.ModuleName -contains 'hns.dll' } | Select-Object -First 1
            `$kp  = Get-Process -Name 'kube-proxy' -ErrorAction SilentlyContinue | Select-Object -First 1
            [PSCustomObject]@{
                HNS_PID        = if (`$hns) { `$hns.Id } else { 'N/A' }
                KubeProxy_PID  = if (`$kp)  { `$kp.Id }  else { 'N/A' }
            } | ConvertTo-Json
        " | Out-String
        $pidObj = $pids | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($pidObj) {
            Write-Host "    HNS PID: $($pidObj.HNS_PID), KubeProxy PID: $($pidObj.KubeProxy_PID)" -ForegroundColor Gray
        }
        $pidMap[$pod] = $pidObj
    }
    return $pidMap
}

function Compare-ProcessIds {
    param(
        [hashtable]$Before,
        [hashtable]$After
    )
    Write-Host "`n===== Process ID Comparison (Before vs After) =====" -ForegroundColor Yellow
    $anyRestarted = $false
    foreach ($pod in $hpcPods) {
        $b = $Before[$pod]
        $a = $After[$pod]
        if (-not $b -or -not $a) {
            Write-Host "  $pod : Unable to compare (missing data)" -ForegroundColor Red
            continue
        }

        $hnsMatch = $b.HNS_PID -eq $a.HNS_PID
        $kpMatch  = $b.KubeProxy_PID -eq $a.KubeProxy_PID

        $hnsStatus = if ($hnsMatch) { "SAME ($($b.HNS_PID))" } else { "CHANGED ($($b.HNS_PID) -> $($a.HNS_PID)) *** RESTARTED ***" }
        $kpStatus  = if ($kpMatch)  { "SAME ($($b.KubeProxy_PID))" } else { "CHANGED ($($b.KubeProxy_PID) -> $($a.KubeProxy_PID)) *** RESTARTED ***" }

        $color = if ($hnsMatch -and $kpMatch) { "Green" } else { "Red"; $anyRestarted = $true }

        Write-Host "  $pod" -ForegroundColor $color
        Write-Host "    HNS       : $hnsStatus" -ForegroundColor $color
        Write-Host "    KubeProxy : $kpStatus" -ForegroundColor $color
    }

    if ($anyRestarted) {
        Write-Host "`n  WARNING: One or more processes restarted during the test!" -ForegroundColor Red
    } else {
        Write-Host "`n  All processes remained stable." -ForegroundColor Green
    }
}

function Delete-TerminatingPods {
    kubectl get pods -n $Namespace --no-headers | Select-String "Terminating" | ForEach-Object { $pod = ($_.ToString().Trim() -split '\s+')[0]; Write-Host "Deleting $pod"; kubectl delete pod $pod -n $Namespace --grace-period=0 --force }
}

# Execution
Stop-Trace
Remove-Trace
# Enable-CrashDump
# $pidsBefore = Get-ProcessIds -Label "Before"
Start-Trace
Loop-DepRecreation
Start-Sleep -Seconds 20
Delete-TerminatingPods
Start-Sleep -Seconds 10
Stop-Trace
# $pidsAfter = Get-ProcessIds -Label "After"
# Compare-ProcessIds -Before $pidsBefore -After $pidsAfter
Convert-Trace
Copy-Trace
# Check-CrashDumps

Write-Host "`n===== Done. Trace files saved to $LocalTraceDir =====" -ForegroundColor Green
