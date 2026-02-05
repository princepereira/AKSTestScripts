Write-Host "Deploying modified kube-proxy binary" -ForegroundColor Yellow
Remove-Item -Recurse -Force kubeproxy -ErrorAction SilentlyContinue
Expand-Archive kubeproxy.zip -DestinationPath kubeproxy -Force
if (-not (Test-Path -Path C:\k\kube-proxy_Orig.exe)) {
    Copy-Item -Path C:\k\kube-proxy.exe -Destination C:\k\kube-proxy_Orig.exe -Force
    Copy-Item -Path .\sfpcopy.exe -Destination C:\k\sfpcopy.exe -Force
}
Stop-Service -Force KubeProxy
Start-Sleep -Seconds 2
rm C:\k\kubeproxy.* -ErrorAction SilentlyContinue
c:\k\sfpcopy.exe .\kubeproxy\kube-proxy.exe C:\k\kube-proxy.exe
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
    Restart-Service -Force KubeProxy
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully restarted KubeProxy service." -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 2
    Write-Host "Retrying restart of KubeProxy service (Attempt $($i + 1))" -ForegroundColor DarkYellow
}
Write-Host "kube-proxy deployment script completed." -ForegroundColor Green
