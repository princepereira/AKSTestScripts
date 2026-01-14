c:\k\sfpcopy.exe C:\k\kube-proxy_Orig.exe C:\k\kube-proxy.exe
Stop-Service -Force KubeProxy
Start-Sleep -Seconds 2
rm C:\k\kubeproxy.err.log -ErrorAction SilentlyContinue
Restart-Service -Force hns
Start-Service KubeProxy
