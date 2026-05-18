param(
    [Parameter(Mandatory=$false)][switch]$SingleStackOnly,
    [Parameter(Mandatory=$false)][switch]$UseNetConnectImage
)

Import-Module -Force .\modules\constants.psm1

$namespace = $Global:NAMESPACE
$osSku = $Global:OS_SKU
$netconnectRegistry = $Global:NETCONNECT_REGISTRY

Write-Host "Creating Pods and Services..." -ForegroundColor Cyan
kubectl create namespace $namespace
(Get-Content .\Yamls\hpc-ds-win22.yaml).Replace("OS_SKU", $osSku) | kubectl.exe create -f -
if ($UseNetConnectImage) {
    az aks update -n $Global:CLUSTER_NAME -g $Global:RG_NAME --attach-acr $netconnectRegistry
    (Get-Content .\Yamls\Dep-NC-Client.yaml) | kubectl.exe create -f -
    (Get-Content .\Yamls\Dep-NC-Server.yaml) | kubectl.exe create -f -
    if ($SingleStackOnly) {
        kubectl create -f .\Yamls\Services-NC\Svc-IPV4-Cluster.yaml
        kubectl create -f .\Yamls\Services-NC\Svc-IPV4-Local.yaml
    } else {
        kubectl create -f .\Yamls\Services\.
    }
} else {
    (Get-Content .\Yamls\Dep-Http-Client.yaml) | kubectl.exe create -f -
    (Get-Content .\Yamls\Dep-Http-Server.yaml) | kubectl.exe create -f -
    if ($SingleStackOnly) {
        kubectl create -f .\Yamls\Services\Svc-IPV4-Cluster.yaml
        kubectl create -f .\Yamls\Services\Svc-IPV4-Local.yaml
    } else {
        kubectl create -f .\Yamls\Services\.
    }
}
Write-Host "Pods and Services created successfully." -ForegroundColor Green