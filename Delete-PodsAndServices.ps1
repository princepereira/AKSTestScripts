Import-Module -Force .\modules\constants.psm1

$namespace = $Global:NAMESPACE
$osSku = $Global:OS_SKU

Write-Host "Deleting Pods and Services..." -ForegroundColor Cyan
(Get-Content .\Yamls\Dep-Test.yaml).Replace("OS_SKU", $osSku) | kubectl.exe delete -f -
(Get-Content .\Yamls\hpc-ds-win22.yaml).Replace("OS_SKU", $osSku) | kubectl.exe delete -f -
kubectl delete -f .\Yamls\Services\.
# kubectl delete -f .\Yamls\hpc-ds-win.yaml
kubectl delete namespace $namespace
Write-Host "Pods and Services deleted successfully." -ForegroundColor Green