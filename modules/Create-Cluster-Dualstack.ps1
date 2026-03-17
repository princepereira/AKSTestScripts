[CmdletBinding()]
param(
    [switch]$useCustomSubnet
)

Import-Module -Force .\modules\constants.psm1

$rgName = $Global:RG_NAME
$location = $Global:LOCATION
$clusterName = $Global:CLUSTER_NAME
$nodeUserName = $Global:NODE_USER_NAME
$nodePassword = $Global:NODE_PASSWORD
$k8sVersion = $Global:K8S_VERSION

Write-Host "Creating Dual Stack AKS Cluster: $clusterName" -ForegroundColor Cyan

$subnetParam = ""
if ($useCustomSubnet -and $Global:SUBNET_ID) {
    $subnetParam = "--vnet-subnet-id $($Global:SUBNET_ID)"
    Write-Host "Using custom subnet: $($Global:SUBNET_ID)" -ForegroundColor Yellow
}

# For 1.30.x
# az aks create --resource-group $rgName --name $clusterName --node-count 1 --windows-admin-username $nodeUserName --windows-admin-password $nodePassword --kubernetes-version $k8sVersion --os-sku AzureLinux --network-plugin-mode overlay --network-plugin azure --ip-families ipv4,ipv6 --tier premium --k8s-support-plan AKSLongTermSupport $subnetParam
$cmd = "az aks create --resource-group $rgName --name $clusterName --node-count 1 --windows-admin-username $nodeUserName --windows-admin-password $nodePassword --kubernetes-version $k8sVersion --os-sku AzureLinux --network-plugin-mode overlay --network-plugin azure --ip-families ipv4,ipv6 $subnetParam"
Invoke-Expression $cmd
az aks get-credentials --resource-group $rgName --name $clusterName --overwrite-existing
Write-Host "Dual Stack AKS Cluster: $clusterName created successfully." -ForegroundColor Green