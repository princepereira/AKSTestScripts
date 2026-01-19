Import-Module -Force .\modules\constants.psm1

$namespace = $Global:NAMESPACE
$osSku = $Global:OS_SKU

Write-Host "Creating Pods and Services..." -ForegroundColor Cyan
kubectl create namespace $namespace
(Get-Content .\Yamls\hpc-ds-win22.yaml).Replace("OS_SKU", $osSku) | kubectl.exe create -f -
(Get-Content .\Yamls\Dep-Test.yaml).Replace("OS_SKU", $osSku) | kubectl.exe create -f -
kubectl create -f .\Yamls\Services\.
Write-Host "Pods and Services created successfully." -ForegroundColor Green