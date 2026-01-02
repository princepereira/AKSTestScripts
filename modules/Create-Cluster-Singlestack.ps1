Import-Module -Force .\constants.psm1

$rgName = $Global:RG_NAME
$location = $Global:LOCATION
$clusterName = $Global:CLUSTER_NAME
$nodeUserName = $Global:NODE_USER_NAME
$nodePassword = $Global:NODE_PASSWORD
$k8sVersion = $Global:K8S_VERSION

Write-Host "Creating Single Stack AKS Cluster: $clusterName" -ForegroundColor Cyan
az aks create --resource-group $rgName --name $clusterName --node-count 1 --windows-admin-username $nodeUserName --windows-admin-password $nodePassword --kubernetes-version $k8sVersion --os-sku AzureLinux --network-plugin-mode overlay --network-plugin azure
az aks get-credentials --resource-group $rgName --name $clusterName --overwrite-existing
Write-Host "Single Stack AKS Cluster: $clusterName created successfully." -ForegroundColor Green