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
    Write-Host "Preparing to replace hns with original version." -ForegroundColor Yellow

    foreach ($pod in $allHpcPods) {
        Write-Host "Copying 'replacehnswithoriginal.ps1' script to Pod: $pod" -ForegroundColor DarkYellow
        kubectl cp -n $namespace .\modules\replacehnswithoriginal.ps1 $pod`:replacehnswithoriginal.ps1
        Write-Host "Executing 'replacehnswithoriginal.ps1' script in Pod: $pod" -ForegroundColor DarkYellow
        kubectl exec -n $namespace $pod -- powershell -Command ".\replacehnswithoriginal.ps1"
        Write-Host "Finished updating hns in Pod: $pod." -ForegroundColor Green
    }

} else {

    Write-Host "Preparing hns package for deployment to HPC Pods" -ForegroundColor Yellow
    if ((Test-Path -Path "~\hns.zip")) {
        Remove-Item -Path .\bins\hns.zip -Force -ErrorAction SilentlyContinue
        Move-Item -Path "~\hns.zip" -Destination .\bins\hns.zip -Force
    }

    foreach ($pod in $allHpcPods) {
        Write-Host "Copying 'copyhns.ps1' script to Pod: $pod" -ForegroundColor DarkYellow
        kubectl cp -n $namespace .\modules\copyhns.ps1 $pod`:copyhns.ps1
        Write-Host "Copying 'sfpcopy.exe' and 'hns.zip' to Pod: $pod" -ForegroundColor DarkYellow
        kubectl cp -n $namespace .\bins\sfpcopy.exe $pod`:sfpcopy.exe
        Write-Host "Copying 'hns.zip' to Pod: $pod" -ForegroundColor DarkYellow
        kubectl cp -n $namespace .\bins\hns.zip $pod`:hns.zip
        Write-Host "Executing 'copyhns.ps1' script in Pod: $pod" -ForegroundColor DarkYellow
        kubectl exec -n $namespace $pod -- powershell -Command ".\copyhns.ps1"
        Write-Host "Finished updating hns in Pod: $pod." -ForegroundColor Green
    }
}

Write-Host "Waiting 5 seconds for hns service to come online..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

kubectl get pods -n $namespace -o wide