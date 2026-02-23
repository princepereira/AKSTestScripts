param(
    [string]$Namespace = "demo",
    [string]$DaemonSetLabel = "hpc-ds-win22",
    [int]$DelayBetweenNodes = 5
)

# Get all HPC pods
$hpcPods = @(kubectl get pods -n $Namespace -l name=$DaemonSetLabel -o jsonpath='{.items[*].metadata.name}' | ForEach-Object { $_ -split '\s+' } | Where-Object { $_ })
if ($hpcPods.Count -eq 0) {
    Write-Host "No HPC pods found in namespace '$Namespace' with label name=$DaemonSetLabel" -ForegroundColor Red
    exit 1
}
Write-Host "Found $($hpcPods.Count) HPC pod(s): $($hpcPods -join ', ')" -ForegroundColor Green

Write-Host "`n===== Restarting all nodes via HPC pods =====" -ForegroundColor Yellow
foreach ($pod in $hpcPods) {
    Write-Host "  Restarting node via $pod ..." -ForegroundColor Cyan
    kubectl exec -n $Namespace $pod -- powershell -Command "Restart-Computer -Force"
    if ($DelayBetweenNodes -gt 0 -and $pod -ne $hpcPods[-1]) {
        Write-Host "  Waiting ${DelayBetweenNodes}s before next restart ..." -ForegroundColor Gray
        Start-Sleep -Seconds $DelayBetweenNodes
    }
}

Write-Host "`n===== Restart commands sent to all nodes. =====" -ForegroundColor Green
