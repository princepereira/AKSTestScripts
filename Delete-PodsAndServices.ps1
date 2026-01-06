Write-Host "Deleting Pods and Services..." -ForegroundColor Cyan
kubectl delete -f .\Yamls\Dep-Test.yaml
kubectl delete -f .\Yamls\Svc-IPV4-Cluster.yaml
kubectl delete -f .\Yamls\Svc-IPV4-Local.yaml
kubectl delete -f .\Yamls\Svc-IPV6-Cluster.yaml
kubectl delete -f .\Yamls\Svc-IPV6-Local.yaml
kubectl delete -f .\Yamls\Svc-Pref-DUAL-Cluster.yaml
kubectl delete -f .\Yamls\Svc-Pref-DUAL-Local.yaml
kubectl delete -f .\Yamls\Svc-Req-DUAL-Cluster.yaml
kubectl delete -f .\Yamls\Svc-Req-DUAL-Local.yaml
kubectl delete -f .\Yamls\hpc-ds-win22.yaml
Write-Host "Pods and Services deleted successfully." -ForegroundColor Green