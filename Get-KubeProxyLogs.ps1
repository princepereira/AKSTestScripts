param(
    [Parameter(Mandatory=$false)][string]$DstPath,
    [Parameter(Mandatory=$false)][string]$Namespace = "demo",
    [Parameter(Mandatory=$false)][string]$HpcDaemonSet = "hpc-ds-win"
)

# Determine destination folder
if (-Not $DstPath) {
    $DstPath = "KubeProxyLogs_" + (Get-Date -Format "yyMMdd_HHmm")
}
$FolderPath = $DstPath

if (-Not (Test-Path -Path $FolderPath)) {
    New-Item -ItemType Directory -Path $FolderPath | Out-Null
}

# Returns the list of HPC Pod Names and prints their node mapping
function Get-AllHpcPods {
    $allHpcPods = (kubectl get pods -n $Namespace -l name=$HpcDaemonSet -o json | ConvertFrom-Json).items.metadata.name
    Write-Host "HPC Pods in Namespace '$Namespace':" -ForegroundColor Cyan
    foreach ($pod in $allHpcPods) {
        $nodeName = (kubectl get pod $pod -n $Namespace -o json | ConvertFrom-Json).spec.nodeName
        Write-Host "  Pod: $pod  -->  Node: $nodeName" -ForegroundColor Green
    }
    return $allHpcPods
}

#============================================================================#

$allHpcPods = Get-AllHpcPods
if (-Not $allHpcPods) {
    Write-Host "No HPC pods found in namespace '$Namespace' with label name=$HpcDaemonSet" -ForegroundColor Red
    return
}

foreach ($pod in $allHpcPods) {
    Write-Host "Collecting kubeproxy logs from Pod: $pod" -ForegroundColor Yellow

    # 1. Copy kubeproxy logs to a local "logs" dir on the node, then compress.
    #    The script is Base64-encoded and passed via -EncodedCommand to avoid
    #    quoting/parsing issues when sent through kubectl exec.
    #    The zip is written to the container's working directory with a relative
    #    name so that 'kubectl cp' (below) does not mangle a Windows drive letter.
    $collectScript = @'
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"
Remove-Item -Recurse -Force .\logs -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path .\logs -Force | Out-Null
Copy-Item -Path C:\k\kubeproxy.err* -Destination .\logs -Force
Remove-Item .\kubeproxylogs.zip -ErrorAction SilentlyContinue
Compress-Archive -Path .\logs\* -DestinationPath .\kubeproxylogs.zip -Force
'@
    $encodedCmd = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($collectScript))
    Write-Host "Copying and compressing kubeproxy logs on Pod: $pod" -ForegroundColor DarkYellow
    kubectl exec -n $Namespace $pod -- powershell -EncodedCommand $encodedCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to collect kubeproxy logs on Pod: $pod" -ForegroundColor Red
        continue
    }

    # 2. Copy the compressed archive locally (with retries)
    Write-Host "Copying kubeproxylogs.zip from Pod: $pod" -ForegroundColor DarkYellow
    $copied = $false
    for ($i = 0; $i -lt 10; $i++) {
        kubectl cp -n $Namespace "$pod`:kubeproxylogs.zip" "$pod.zip"
        if ($LASTEXITCODE -eq 0) {
            $copied = $true
            Write-Host "Successfully copied kubeproxylogs.zip from Pod: $pod" -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds 2
        Write-Host "Retrying copy from Pod: $pod (Attempt $($i + 1))" -ForegroundColor DarkYellow
    }
    if (-Not $copied) {
        Write-Host "Failed to copy kubeproxylogs.zip from Pod: $pod" -ForegroundColor Red
        continue
    }

    Move-Item -Force "$pod.zip" "$FolderPath\$pod.zip"
    try {
        Expand-Archive -Path "$FolderPath\$pod.zip" -DestinationPath "$FolderPath\$pod" -Force -ErrorAction Stop
    } catch {
        Write-Host "Failed to expand archive for Pod: $pod - $_" -ForegroundColor Red
    }
    Write-Host "Finished collecting kubeproxy logs from Pod: $pod" -ForegroundColor Green
}

Write-Host "All kubeproxy logs collected and stored in folder: $FolderPath" -ForegroundColor Magenta
