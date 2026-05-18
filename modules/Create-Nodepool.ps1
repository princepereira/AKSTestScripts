Import-Module -Force .\modules\constants.psm1

$rgName = $Global:RG_NAME
$location = $Global:LOCATION
$clusterName = $Global:CLUSTER_NAME
$nodePoolName = $Global:NODE_POOL_NAME
$nodeCount = $Global:NODE_COUNT
$osSku = $Global:OS_SKU
$nodeVmSize = $Global:NODE_VM_SIZE
$zones = $Global:NODE_POOL_ZONES

$zoneArgs = ""
if ($zones -and $zones.Count -gt 0) {
    $zoneArgs = "--zones $($zones -join ' ')"
}

$zonesDisplay = if ($zones -and $zones.Count -gt 0) { $zones -join ' ' } else { 'None' }
Write-Host "Creating Windows Node Pool: $nodePoolName in Cluster: $clusterName, OS SKU: $osSku, Node Count: $nodeCount, Zones: $zonesDisplay" -ForegroundColor Cyan

$fipsArgs = ""
if ($osSku -match "^Windows20(25|[3-9]\d)") {
    az extension add -n aks-preview
    az extension update --name aks-preview
    az feature register --namespace "Microsoft.ContainerService" --name "AKSWindowsAnnualPreview"
    $fipsArgs = "--enable-fips-image"
}

$cmd = "az aks nodepool add --resource-group $rgName --cluster-name $clusterName --name $nodePoolName --node-count $nodeCount --node-vm-size $nodeVmSize --os-type Windows --os-sku $osSku --vm-set-type VirtualMachineScaleSets $fipsArgs $zoneArgs"
Write-Host "Executing [$cmd]" -ForegroundColor Yellow
Invoke-Expression $cmd

# Wait for nodes to be ready with 8-minute timeout
Write-Host "Waiting for $nodeCount node(s) in nodepool '$nodePoolName' to be Ready..." -ForegroundColor Yellow
$timeoutSeconds = 480  # 8 minutes
$pollIntervalSeconds = 15
$startTime = Get-Date

while ($true) {
    $elapsed = (Get-Date) - $startTime
    if ($elapsed.TotalSeconds -gt $timeoutSeconds) {
        Write-Host "Timeout: Nodes did not become Ready within 8 minutes." -ForegroundColor Red
        kubectl get nodes -o wide
        throw "Timeout waiting for nodepool '$nodePoolName' nodes to be Ready."
    }

    # Get nodes from this nodepool that are Ready
    $nodes = kubectl get nodes -o json | ConvertFrom-Json
    $nodepoolNodes = $nodes.items | Where-Object { 
        $_.metadata.name -match "^$($nodePoolName.ToLower())" 
    }
    $readyNodes = $nodepoolNodes | Where-Object {
        ($_.status.conditions | Where-Object { $_.type -eq "Ready" -and $_.status -eq "True" }).Count -gt 0
    }
    $readyCount = @($readyNodes).Count

    $elapsedMinutes = [math]::Floor($elapsed.TotalMinutes)
    $elapsedSeconds = [math]::Floor($elapsed.TotalSeconds % 60)
    Write-Host "  [$elapsedMinutes`:$($elapsedSeconds.ToString('00'))] Ready nodes: $readyCount / $nodeCount" -ForegroundColor Cyan

    if ($readyCount -ge $nodeCount) {
        Write-Host "All $nodeCount node(s) are Ready!" -ForegroundColor Green
        break
    }

    Start-Sleep -Seconds $pollIntervalSeconds
}

Write-Host "Windows Node Pool: $nodePoolName created successfully in Cluster: $clusterName." -ForegroundColor Green
kubectl get nodes -o wide