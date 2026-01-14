param(
    [Parameter(Mandatory=$true)][string]$DstPath,
    [Parameter(Mandatory=$false)][switch]$IncludeInstallLogs
)

Import-Module -Force .\modules\constants.psm1

$namespace = $Global:NAMESPACE
$hpcDaemonsSet = $Global:HPC_NAME
$RootDir = $Global:LOGS_ROOT_DIR

$FolderPath = Join-Path -Path $RootDir -ChildPath $DstPath
if (-Not (Test-Path -Path $FolderPath)) {
    New-Item -ItemType Directory -Path $FolderPath | Out-Null
}

$podsAndServicesLog = Join-Path -Path $FolderPath -ChildPath "nodes-pods-services.txt"
$allPodsAndServicesLog = Join-Path -Path $FolderPath -ChildPath "all-pods-services.txt"
$servicesInDetailLog = Join-Path -Path $FolderPath -ChildPath "services-detail.txt"

Remove-Item -Recurse -Force "$FolderPath\*" -ErrorAction SilentlyContinue

# Returns a map of HPC Pod Names to Node Names
function Get-AllHpcPods {
    $allHpcPods = (kubectl get pods -n $namespace -l name=$hpcDaemonsSet -o json | ConvertFrom-Json).items.metadata.name
    Write-Host "HPC Pods in Namespace '$namespace':" -ForegroundColor Cyan
    foreach ($pod in $allHpcPods) {
        $nodeName = (kubectl get pod $pod -n $namespace -o json | ConvertFrom-Json).spec.nodeName
        Write-Host "  Pod: $pod  -->  Node: $nodeName" -ForegroundColor Green
    }
    return $allHpcPods
}

#============================================================================#

Write-Host "Collecting cluster information..." -ForegroundColor Yellow

Write-Output "`n======================= NODES =======================`n" | Out-File -FilePath $podsAndServicesLog -Encoding utf8 -Append
kubectl get nodes -o wide | Out-File -FilePath $podsAndServicesLog -Encoding utf8 -Append
Write-Output "`n======================= PODS =======================`n" | Out-File -FilePath $podsAndServicesLog -Encoding utf8 -Append
kubectl get pods -n $namespace -o wide | Out-File -FilePath $podsAndServicesLog -Encoding utf8 -Append
Write-Output "`n======================= SERVICES =======================`n" | Out-File -FilePath $podsAndServicesLog -Encoding utf8 -Append
kubectl get svc -n $namespace -o wide | Out-File -FilePath $podsAndServicesLog -Encoding utf8 -Append
Write-Output "`n======================= ALL PODS =======================`n" | Out-File -FilePath $podsAndServicesLog -Encoding utf8 -Append
kubectl get pods -A -o wide | Out-File -FilePath $allPodsAndServicesLog -Encoding utf8 -Append
Write-Output "`n======================= ALL SERVICES =======================`n" | Out-File -FilePath $podsAndServicesLog -Encoding utf8 -Append
kubectl get svc -A -o wide | Out-File -FilePath $allPodsAndServicesLog -Encoding utf8 -Append
Write-Output "`n======================= SERVICES IN DETAIL =======================`n" | Out-File -FilePath $servicesInDetailLog -Encoding utf8 -Append
$allServices = (kubectl get svc -n $namespace -o json | ConvertFrom-Json).items.metadata.name
foreach ($svc in $allServices) {
    Write-Output "`n======================= Service: $svc =======================`n" | Out-File -FilePath $servicesInDetailLog -Encoding utf8 -Append
    kubectl get svc $svc -n $namespace -o json | Out-File -FilePath $servicesInDetailLog -Encoding utf8 -Append
}

#============================================================================#

Write-Host "Collecting HPC Pods information..." -ForegroundColor Yellow


$allHpcPods = Get-AllHpcPods
foreach ($pod in $allHpcPods) {
    Write-Host "Collecting Windows Logs from Pod: $pod" -ForegroundColor Yellow
    Write-Host "Copying collect script to Pod: $pod" -ForegroundColor DarkYellow
    kubectl cp -n $namespace .\modules\collectlogs.ps1 $pod`:collectlogs.ps1
    Write-Host "Executing collect script in Pod: $pod" -ForegroundColor DarkYellow
    $includeLogsParam = if ($IncludeInstallLogs) { "-IncludeInstallLogs `$true" } else { "-IncludeInstallLogs `$false" }
    kubectl exec -n $namespace $pod -- powershell -Command ".\collectlogs.ps1 $includeLogsParam"
    Write-Host "Copying logs.zip from Pod: $pod" -ForegroundColor DarkYellow
    kubectl cp -n $namespace $pod`:logs.zip "$pod.zip"
    move-item -Force "$pod.zip" "$FolderPath\$pod.zip"
    Write-Host "Finished collecting logs from Pod: $pod" -ForegroundColor Green
    Expand-Archive -Path "$FolderPath\$pod.zip" -DestinationPath "$FolderPath\$pod" -Force
}

Write-Host "All logs collected and stored in folder: $FolderPath" -ForegroundColor Magenta