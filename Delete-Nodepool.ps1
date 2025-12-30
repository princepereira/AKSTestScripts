$subscriptionId="b8c06bcd-5024-43fa-9507-691b5623f59a"
$rgName="pper-vfptest-rg"
$clusterName="pper-vfptest-aks"
$nodePoolName="npwin"

Write-Host "Deleting Node Pool: $nodePoolName from Cluster: $clusterName" -ForegroundColor Cyan
az aks nodepool delete --resource-group $rgName --cluster-name $clusterName --name $nodePoolName