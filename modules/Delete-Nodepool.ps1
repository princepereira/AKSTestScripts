Import-Module -Force .\modules\constants.psm1

$rgName = $Global:RG_NAME
$location = $Global:LOCATION
$clusterName = $Global:CLUSTER_NAME
$nodePoolName = $Global:NODE_POOL_NAME

Write-Host "Deleting Node Pool: $nodePoolName from Cluster: $clusterName" -ForegroundColor Cyan
az aks nodepool delete --resource-group $rgName --cluster-name $clusterName --name $nodePoolName --yes
Write-Host "Node Pool: $nodePoolName deleted successfully from Cluster: $clusterName." -ForegroundColor Green