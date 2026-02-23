<#
.SYNOPSIS
    Get file hashes and process IDs of HNS and KubeProxy on each Windows node.

.DESCRIPTION
    This script connects to each Windows node in the cluster and retrieves
    the SHA256 file hash of HostNetSvc.dll and kube-proxy.exe, along with
    the process IDs of the HNS and KubeProxy services.

.PARAMETER Namespace
    Namespace to use for temporary pods (default: demo)

.EXAMPLE
    .\Get-NodeFileHashes.ps1
#>

param(
    [string]$Namespace = "demo"
)

Import-Module -Force .\modules\constants.psm1

$hpcDaemonsSet = $Global:HPC_NAME

# Files to check
$FilesToCheck = @(
    @{ Name = "HostNetSvc.dll"; Path = "C:\windows\system32\HostNetSvc.dll" },
    @{ Name = "kube-proxy.exe"; Path = "C:\k\kube-proxy.exe" }
)

# Services/Processes to check
$ProcessesToCheck = @(
    @{ Name = "HNS"; ServiceName = "hns"; ProcessName = "svchost" },
    @{ Name = "KubeProxy"; ServiceName = "kubeproxy"; ProcessName = "kube-proxy" }
)

function Get-AllHpcPods {
    $hpcPods = @()
    $items = (kubectl get pods -n $namespace -l name=$hpcDaemonsSet -o json | ConvertFrom-Json).items
    foreach ($item in $items) {
        $podName = $item.metadata.name
        $hpcPods += $podName
    }
    return $hpcPods
}

function Get-FileHashFromNode {
    param(
        [string]$hpcPod
    )
    foreach ($file in $FilesToCheck) {
        $command = "if (Test-Path '$($file.Path)') { (Get-FileHash -Path '$($file.Path)' -Algorithm SHA256).Hash } else { 'FILE_NOT_FOUND' }"
        $hash = kubectl exec $hpcPod -n $namespace -- powershell -Command $command 2>$null
        Write-Host "$($file.Name) hash on $hpcPod : $hash" -ForegroundColor Green
    }
}

function Get-ProcessIdsFromNode {
    param(
        [string]$hpcPod
    )
    foreach ($proc in $ProcessesToCheck) {
        # Use sc.exe queryex to get the PID of the service
        $command = "((sc.exe queryex $($proc.ServiceName) | Select-String 'PID') -replace '.*PID\s*:\s*', '').Trim()"
        $processId = kubectl exec $hpcPod -n $namespace -- powershell -Command $command 2>$null
        if ($processId -and $processId.Trim() -ne "" -and $processId.Trim() -ne "0") {
            Write-Host "$($proc.Name) PID on $hpcPod : $("$processId".Trim())" -ForegroundColor Cyan
        } else {
            Write-Host "$($proc.Name) PID on $hpcPod : NOT_FOUND or NOT_RUNNING" -ForegroundColor Yellow
        }
    }
}

Write-Host "Fetching HPC Pods..." -ForegroundColor Yellow
$hpcPods = Get-AllHpcPods
if ($hpcPods.Count -eq 0) {
    Write-Host "No HPC Pods found in namespace '$namespace'." -ForegroundColor Red
    exit 1
}
Write-Host "Found $($hpcPods.Count) HPC Pods. Retrieving file hashes and process IDs..." -ForegroundColor Cyan
foreach ($pod in $hpcPods) {
    Write-Host "`n=== Node via Pod: $pod ===" -ForegroundColor Magenta
    Write-Host "File Hashes:" -ForegroundColor Yellow
    Get-FileHashFromNode -hpcPod $pod
    Write-Host "Process IDs:" -ForegroundColor Yellow
    Get-ProcessIdsFromNode -hpcPod $pod
}