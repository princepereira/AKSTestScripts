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

function Remove-Trace {
    $txtFile = [System.IO.Path]::ChangeExtension($TraceFile, ".txt")
    Write-Host "`n===== Removing trace files from all nodes =====" -ForegroundColor Yellow
    foreach ($pod in $hpcPods) {
        Write-Host "  Removing $TraceFile and $txtFile on $pod ..." -ForegroundColor Cyan
        kubectl exec -n $Namespace $pod -- powershell -Command "Remove-Item -Path $TraceFile, $txtFile -Force -ErrorAction SilentlyContinue"
    }
}