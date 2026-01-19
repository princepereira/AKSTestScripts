Import-Module -Force .\modules\constants.psm1

$rgName = $Global:RG_NAME
$location = $Global:LOCATION
$clusterName = $Global:CLUSTER_NAME
$nodePoolName = $Global:NODE_POOL_NAME
$nodeCount = $Global:NODE_COUNT
$osSku = $Global:OS_SKU
$nodeVmSize = $Global:NODE_VM_SIZE

Write-Host "Creating Windows Node Pool: $nodePoolName in Cluster: $clusterName, OS SKU: $osSku, Node Count: $nodeCount" -ForegroundColor Cyan
New-AzAksNodePool -ResourceGroupName $rgName -ClusterName $clusterName -Name $nodePoolName -VmSize Standard_D4s_v5 -Count $nodeCount -OsType 'Windows' -OsSKU $osSku -VmSetType 'VirtualMachineScaleSets' -OsDiskSize 256
az aks nodepool add --resource-group $rgName --cluster-name $clusterName --os-type Windows --os-sku $osSku --node-vm-size standard_e8-2as_v5 --name $nodePoolName --node-count $nodeCount
Write-Host "Waiting for 5 minutes for the nodes to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 300
Write-Host "Windows Node Pool: $nodePoolName created successfully in Cluster: $clusterName." -ForegroundColor Green
kubectl get nodes -o wide