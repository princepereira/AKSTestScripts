Write-Host "Deploying modified hns binary" -ForegroundColor Yellow
Remove-Item -Recurse -Force hns -ErrorAction SilentlyContinue
Expand-Archive hns.zip -DestinationPath hns -Force
if (-not (Test-Path -Path C:\k\HostNetSvc_Orig.dll)) {
    Copy-Item -Path C:\windows\system32\HostNetSvc.dll -Destination C:\k\HostNetSvc_Orig.dll -Force
    Copy-Item -Path .\sfpcopy.exe -Destination C:\k\sfpcopy.exe -Force
}
Stop-Service -Force KubeProxy
Start-Sleep -Seconds 5
rm C:\k\kubeproxy.* -ErrorAction SilentlyContinue
c:\k\sfpcopy.exe .\hns\HostNetSvc.dll C:\windows\system32\HostNetSvc.dll
for ($i = 0; $i -lt 3; $i++) {
    Restart-Service -Force hns
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully restarted hns service." -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 2
    Write-Host "Retrying restart of hns service (Attempt $($i + 1))" -ForegroundColor DarkYellow
}
for ($i = 0; $i -lt 3; $i++) {
    Restart-Computer -Force
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully restarted KubeProxy service." -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 2
    Write-Host "Retrying restart of KubeProxy service (Attempt $($i + 1))" -ForegroundColor DarkYellow
}
Write-Host "kube-proxy deployment script completed." -ForegroundColor Green
