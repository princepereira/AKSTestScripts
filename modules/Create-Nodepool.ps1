Import-Module -Force .\modules\constants.psm1

$rgName = $Global:RG_NAME
$location = $Global:LOCATION
$clusterName = $Global:CLUSTER_NAME
$nodePoolName = $Global:NODE_POOL_NAME
$nodeCount = $Global:NODE_COUNT
$osSku = $Global:OS_SKU
$nodeVmSize = $Global:NODE_VM_SIZE

Write-Host "Creating Windows Node Pool: $nodePoolName in Cluster: $clusterName, OS SKU: $osSku, Node Count: $nodeCount" -ForegroundColor Cyan
Write-Host "Executing [New-AzAksNodePool -ResourceGroupName $rgName -ClusterName $clusterName -Name $nodePoolName -VmSize $nodeVmSize -Count $nodeCount -OsType 'Windows' -OsSKU $osSku -VmSetType 'VirtualMachineScaleSets' -OsDiskSize 256]" -ForegroundColor Yellow
New-AzAksNodePool -ResourceGroupName $rgName -ClusterName $clusterName -Name $nodePoolName -VmSize $nodeVmSize -Count $nodeCount -OsType 'Windows' -OsSKU $osSku -VmSetType 'VirtualMachineScaleSets' -OsDiskSize 256
Write-Host "Waiting for 5 minutes for the nodes to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 300
Write-Host "Windows Node Pool: $nodePoolName created successfully in Cluster: $clusterName." -ForegroundColor Green
kubectl get nodes -o wide