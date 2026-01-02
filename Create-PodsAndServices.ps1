Write-Host "Creating Pods and Services..." -ForegroundColor Cyan
kubectl create -f .\Yamls\hpc-ds-win22.yaml
kubectl create -f .\Yamls\dep-test.yaml
kubectl create -f .\Yamls\Svc-*
Write-Host "Pods and Services created successfully." -ForegroundColor Green