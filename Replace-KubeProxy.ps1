[CmdletBinding()]
param(
    [switch]$replaceWithOriginal
)

Import-Module -Force .\modules\constants.psm1

$namespace = $Global:NAMESPACE
$hpcDaemonsSet = $Global:HPC_NAME

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

$allHpcPods = Get-AllHpcPods

if ($replaceWithOriginal) {
    Write-Host "Preparing to replace kube-proxy with original version." -ForegroundColor Yellow

    foreach ($pod in $allHpcPods) {
        Write-Host "Copying 'replacekubeproxywithoriginal.ps1' script to Pod: $pod" -ForegroundColor DarkYellow
        kubectl cp -n $namespace .\modules\replacekubeproxywithoriginal.ps1 $pod`:replacekubeproxywithoriginal.ps1
        Write-Host "Executing 'replacekubeproxywithoriginal.ps1' script in Pod: $pod" -ForegroundColor DarkYellow
        kubectl exec -n $namespace $pod -- powershell -Command ".\replacekubeproxywithoriginal.ps1"
        Write-Host "Finished updating kube-proxy in Pod: $pod." -ForegroundColor Green
    }

} else {

    Write-Host "Preparing kube-proxy package for deployment to HPC Pods" -ForegroundColor Yellow
    if ((Test-Path -Path "~\kube-proxy.exe")) {
        Remove-Item -Path .\bins\kube-proxy.exe -Force -ErrorAction SilentlyContinue
        Move-Item -Path "~\kube-proxy.exe" -Destination .\bins\kube-proxy.exe -Force
    }
    Remove-Item -Path .\bins\kubeproxy.zip -Force -ErrorAction SilentlyContinue
    $kubeProxyHash = (Get-FileHash -Path .\bins\kube-proxy.exe).Hash
    Compress-Archive .\bins\kube-proxy.exe .\bins\kubeproxy.zip -Force

    foreach ($pod in $allHpcPods) {
        Write-Host "Copying 'copykubeproxy.ps1' script to Pod: $pod" -ForegroundColor DarkYellow
        kubectl cp -n $namespace .\modules\copykubeproxy.ps1 $pod`:copykubeproxy.ps1
        Write-Host "Copying 'sfpcopy.exe' and 'kubeproxy.zip' to Pod: $pod" -ForegroundColor DarkYellow
        kubectl cp -n $namespace .\bins\sfpcopy.exe $pod`:sfpcopy.exe
        Write-Host "Copying 'kubeproxy.zip' to Pod: $pod" -ForegroundColor DarkYellow
        kubectl cp -n $namespace .\bins\kubeproxy.zip $pod`:kubeproxy.zip
        Write-Host "Executing 'copykubeproxy.ps1' script in Pod: $pod" -ForegroundColor DarkYellow
        kubectl exec -n $namespace $pod -- powershell -Command ".\copykubeproxy.ps1"
        Write-Host "Finished updating kube-proxy in Pod: $pod." -ForegroundColor Green
    }
}

Write-Host "Waiting 5 seconds for KubeProxy service to come online..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

foreach ($pod in $allHpcPods) {
    Write-Host "Verifying KubeProxy service status in Pod: $pod" -ForegroundColor DarkYellow
    kubectl exec -n $namespace $pod -- powershell -Command "Get-Service KubeProxy"
    if ($replaceWithOriginal) {
        $kubeProxyHash = kubectl exec -n $namespace $pod -- powershell -Command "(Get-FileHash -Path C:\k\kube-proxy_Orig.exe).Hash"
    }
    $podKubeProxyHash = kubectl exec -n $namespace $pod -- powershell -Command "(Get-FileHash -Path C:\k\kube-proxy.exe).Hash"
    if ($podKubeProxyHash -eq $kubeProxyHash) {
        Write-Host "kube-proxy.exe successfully updated in Pod: $pod" -ForegroundColor Green
        Write-Host "All HPC Pods updated with new kube-proxy version." -ForegroundColor Magenta
    } else {
        Write-Host "ERROR: kube-proxy.exe update failed in Pod: $pod" -ForegroundColor Red
    }
    Write-Host "Finished updating kube-proxy in Pod: $pod." -ForegroundColor Green
    Write-Host "Actual hash: $kubeProxyHash" -ForegroundColor Green
    Write-Host "PodKubeProxy Hash: $podKubeProxyHash" -ForegroundColor Green
}

kubectl get pods -n $namespace -o wide