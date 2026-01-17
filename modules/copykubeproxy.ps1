Write-Host "Deploying modified kube-proxy binary" -ForegroundColor Yellow
Remove-Item -Recurse -Force kubeproxy -ErrorAction SilentlyContinue
Expand-Archive kubeproxy.zip -DestinationPath kubeproxy -Force
if (-not (Test-Path -Path C:\k\kube-proxy_Orig.exe)) {
    Copy-Item -Path C:\k\kube-proxy.exe -Destination C:\k\kube-proxy_Orig.exe -Force
    Copy-Item -Path .\sfpcopy.exe -Destination C:\k\sfpcopy.exe -Force
}
Stop-Service -Force KubeProxy
Start-Sleep -Seconds 2
rm C:\k\kubeproxy.err.log -ErrorAction SilentlyContinue
c:\k\sfpcopy.exe C:\kubeproxy\kube-proxy.exe C:\k\kube-proxy.exe
Restart-Service -Force hns
Start-Service KubeProxy
Write-Host "kube-proxy deployment script completed." -ForegroundColor Green
