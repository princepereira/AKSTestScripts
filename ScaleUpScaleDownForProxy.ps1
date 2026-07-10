function DeleteTerminatingPods {
	$pods = kubectl get pods -n demo --no-headers | Select-String "Terminating"
	foreach ($pod in $pods) {
		$podName = ($pod.ToString().Trim() -split '\s+')[0]
		Write-Host "Deleting $podName"
		kubectl delete pod $podName -n demo --grace-period=0 --force
	}
	Start-Sleep -seconds 10
}

function ForceDeleteAllPods {
	Start-Sleep -seconds 20
	$pods = kubectl get pods -n demo --no-headers
	foreach ($pod in $pods) {
		$podName = ($pod.ToString().Trim() -split '\s+')[0]
		Write-Host "Force deleting $podName"
		kubectl delete pod $podName -n demo --grace-period=0 --force
	}
	Start-Sleep -seconds 10
}

function ScaleDeployment {
	param (
		[string]$deploymentName,
		[int]$replicas
	)
	Write-Host "Scaling deployment $deploymentName to $replicas replicas..." -ForegroundColor Cyan
	kubectl scale deployment/$deploymentName --replicas=$replicas -n demo
	Start-Sleep -seconds 20
}

for($i = 0; $i -le 15; $i++) {
	Start-Sleep -seconds 10
	ScaleDeployment -deploymentName "server" -replicas 20
	ScaleDeployment -deploymentName "server" -replicas 2
	Write-Host "Iteration $i : Scaling up to 20 after Scale Down to 2..." -ForegroundColor Cyan
	ScaleDeployment -deploymentName "server" -replicas 20
	Write-Host "Iteration $i : Scaling Down to 0..." -ForegroundColor Cyan
	ScaleDeployment -deploymentName "server" -replicas 0
	Write-Host "Iteration $i : Scaling up to 20 after Scale Down to 0..." -ForegroundColor Cyan
	ScaleDeployment -deploymentName "server" -replicas 20
	# ForceDeleteAllPods
}

Write-Host "Deleting Deployment..." -ForegroundColor Cyan
kubectl delete -f .\Yamls\Dep-NC-Server.yaml
# ForceDeleteAllPods