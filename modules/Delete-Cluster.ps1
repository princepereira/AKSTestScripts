Import-Module -Force .\modules\constants.psm1

$rgName = $Global:RG_NAME
$location = $Global:LOCATION
$clusterName = $Global:CLUSTER_NAME

Write-Host "Deleting AKS Cluster: $clusterName in Resource Group: $rgName" -ForegroundColor Cyan
az aks delete --resource-group $rgName --name $clusterName --yes
Write-Host "AKS Cluster: $clusterName deleted successfully." -ForegroundColor Green
kubectl config delete-context $clusterName
Write-Host "Kubernetes context for Cluster: $clusterName deleted successfully." -ForegroundColor Green
