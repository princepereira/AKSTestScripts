Write-Host "Creating Pods and Services..." -ForegroundColor Cyan
kubectl create -f .\Yamls\hpc-ds-win22.yaml
kubectl create -f .\Yamls\dep-test.yaml
kubectl create -f .\Yamls\Svc-IPV4.yaml
kubectl create -f .\Yamls\Svc-IPV6.yaml
kubectl create -f .\Yamls\Svc-Pref-DUAL-Cluster.yaml
kubectl create -f .\Yamls\Svc-Pref-DUAL-Local.yaml
kubectl create -f .\Yamls\Svc-Req-DUAL-Cluster.yaml
kubectl create -f .\Yamls\Svc-Req-DUAL-Local.yaml
Write-Host "Pods and Services created successfully." -ForegroundColor Green