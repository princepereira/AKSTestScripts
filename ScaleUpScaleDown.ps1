function DeleteTerminatingPods {
	$pods = kubectl get pods -n demo --no-headers | Select-String "Terminating"
	foreach ($pod in $pods) {
		$podName = ($pod.ToString().Trim() -split '\s+')[0]
		Write-Host "Deleting $podName"
		kubectl delete pod $podName -n demo --grace-period=0 --force
	}
	Start-Sleep -seconds 10
}

for($i = 0; $i -le 15; $i++) {
	Write-Host "Iteration $i : Creating Deployment..." -ForegroundColor Cyan
	kubectl create -f .\Yamls\dep-test.yaml
	Start-Sleep -seconds 10
	Write-Host "Iteration $i : Scaling up to 20..." -ForegroundColor Cyan
	kubectl scale deployment/server --replicas=20 -n demo
	Start-Sleep -seconds 20
	Write-Host "Iteration $i : Scaling down to 2..." -ForegroundColor Cyan
	kubectl scale deployment/server --replicas=2 -n demo
	Start-Sleep -seconds 10
	Write-Host "Iteration $i : Scaling up to 20 after Scale Down to 2..." -ForegroundColor Cyan
	kubectl scale deployment/server --replicas=20 -n demo
	Start-Sleep -seconds 20
	Write-Host "Iteration $i : Scaling Down to 0..." -ForegroundColor Cyan
	kubectl scale deployment/server --replicas=0 -n demo
	Start-Sleep -seconds 10
	Write-Host "Iteration $i : Scaling up to 20 after Scale Down to 0..." -ForegroundColor Cyan
	kubectl scale deployment/server --replicas=20 -n demo
	Start-Sleep -seconds 20
	Write-Host "Iteration $i : Deleting Deployment..." -ForegroundColor Cyan
	kubectl delete -f .\Yamls\dep-test.yaml
	# DeleteTerminatingPods
}