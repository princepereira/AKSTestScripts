Import-Module -Force .\modules\constants.psm1

$namespace = $Global:NAMESPACE

Write-Host "Creating Pods and Services..." -ForegroundColor Cyan
kubectl create namespace $namespace
kubectl create -f .\Yamls\hpc-ds-win22.yaml
# kubectl create -f .\Yamls\hpc-ds-winannual.yaml
kubectl create -f .\Yamls\Dep-Test.yaml
kubectl create -f .\Yamls\Svc-IPV4-Cluster.yaml
kubectl create -f .\Yamls\Svc-IPV4-Local.yaml
kubectl create -f .\Yamls\Svc-IPV6-Cluster.yaml
kubectl create -f .\Yamls\Svc-IPV6-Local.yaml
kubectl create -f .\Yamls\Svc-Pref-DUAL-Cluster.yaml
kubectl create -f .\Yamls\Svc-Pref-DUAL-Local.yaml
kubectl create -f .\Yamls\Svc-Req-DUAL-Cluster.yaml
kubectl create -f .\Yamls\Svc-Req-DUAL-Local.yaml
Write-Host "Pods and Services created successfully." -ForegroundColor Green