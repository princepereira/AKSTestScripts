function Log-Message {
    param(
        [Parameter(Mandatory=$true)][string] $Message,
        [Parameter(Mandatory=$false)][string] $Color=((Get-Host).ui.rawui.ForegroundColor),
        [Parameter(Mandatory=$false)][int] $MaxFileSizeMB = 1
    )
    try {
        Write-Host $Message -ForegroundColor $color
    } catch {
        # Ignore any errors in logging
    }
}

function Execute-DiagnosticCommand {
    param (
        [Parameter(Mandatory=$true)][string] $Command,
        [Parameter(Mandatory=$true)][string] $OutFile
    )

    try {
        # Log the command being executed
        Log-Message "Executing diagnostic command: $Command"

        # Create the directory for the output file if it doesn't exist
        $outFileDir = Split-Path -Parent $OutFile
        if (-not (Test-Path $outFileDir)) {
            New-Item -ItemType Directory -Path $outFileDir -Force | Out-Null
        }

        # Execute the command and capture output
        $output = Invoke-Expression $Command 2>&1 | Out-String

        # Append output to file (create if doesn't exist)
        if (Test-Path $OutFile) {
            Add-Content -Path $OutFile -Value "`nCommand: $Command`n$output"
        } else {
            Set-Content -Path $OutFile -Value "Command: $Command`n$output"
        }
    } catch {
        Log-Message "Failed to execute diagnostic command '$Command': $_" -Color Red

        # Still try to write the error to the output file
        try {
            $errorOutput = "Command: $Command (FAILED)`nERROR: $_"
            if (Test-Path $OutFile) {
                Add-Content -Path $OutFile -Value "`n$errorOutput"
            } else {
                Set-Content -Path $OutFile -Value $errorOutput
            }
        } catch {
            # Do nothing - suppress errors
        }
    }
}

function Get-RundownState {
    param (
        [Parameter (Mandatory = $true)]
        [String] $stateDir,
        [switch] $VerboseState
    )
    try {
        Log-Message "===== Get-RundownState operation started ======"
        if (-not (Test-Path $stateDir)) {
            New-Item -ItemType Directory -Path $stateDir
        }

        # Get ebpf state
        $ebpfStateFile = Join-Path $stateDir "ebpf_state.txt"
        Execute-DiagnosticCommand -Command "netsh ebpf show programs" -OutFile $ebpfStateFile
        Execute-DiagnosticCommand -Command "netsh ebpf show pins" -OutFile $ebpfStateFile

        # eBPF map state
        Log-Message "Obtaining eBPF map state"
        $ebpfMapsDir = Join-Path $stateDir "ebpf_maps"
        if (-not (Test-Path $ebpfMapsDir)) {
            New-Item -ItemType Directory -Path $ebpfMapsDir
        }
        try {
            # List base map entries
            $mapNames = @(
                "node_config",
                "node_devices",
                "observability_config",
                "endpoints",
                "ipcache",
                "lb",
                "lb_affinity",
                "lb_backend",
                "lb_revnat",
                "masquerade",
                "neighbor",
                "nodeport_neighbor"
            )
            if ($VerboseState) {
                $mapNames += @(
                    "connection_tracker",
                    "snat"
                )
            }
            foreach ($name in $mapNames) {
                $mapFile = Join-Path $ebpfMapsDir "$name.txt"
                Log-Message "    cnc_cli.exe --state map=$name out=$mapFile"
                $result = (& cnc_cli.exe --state map=$name out=$mapFile)
            }
        } catch {
            Log-Message "Failed to collect eBPF map state. $_" -Color Red
        }

        # Cilium metrics
        try {
            $ciliumMetricsFile = Join-Path $stateDir "cilium_metrics.txt"
            cnc_cli.exe --metrics metrics-agg=cpu out=$ciliumMetricsFile
        } catch {
            Log-Message "Failed to collect Cilium metrics. $_" -Color Red
        }

        # Get HNS state
        $hnsDiagFile = Join-Path $stateDir "hnsdiag.txt"
        Execute-DiagnosticCommand -Command "hnsdiag.exe list all -dfl" -OutFile $hnsDiagFile

        # Create WCN debug directory for wcnagent snapshot and metrics
        $wcnDebugDir = Join-Path $stateDir "wcn_debug"
        if (-not (Test-Path $wcnDebugDir)) {
            New-Item -ItemType Directory -Path $wcnDebugDir
        }

        # Get WCN state - split into separate components
        $wcnStateLoadBalancerFile = Join-Path $wcnDebugDir "wcncli_state_loadbalancer.txt"
        Execute-DiagnosticCommand -Command "wcncli.exe --module wcn state loadbalancer" -OutFile $wcnStateLoadBalancerFile

        $wcnStateEndpointFile = Join-Path $wcnDebugDir "wcncli_state_endpoint.txt"
        Execute-DiagnosticCommand -Command "wcncli.exe --module wcn state endpoint" -OutFile $wcnStateEndpointFile

        $wcnStateNetworkFile = Join-Path $wcnDebugDir "wcncli_state_network.txt"
        Execute-DiagnosticCommand -Command "wcncli.exe --module wcn state network" -OutFile $wcnStateNetworkFile

        $wcnStateNamespaceFile = Join-Path $wcnDebugDir "wcncli_state_namespace.txt"
        Execute-DiagnosticCommand -Command "wcncli.exe --module wcn state namespace" -OutFile $wcnStateNamespaceFile

        # Get WCN metrics
        $wcnMetricsFile = Join-Path $wcnDebugDir "wcncli_metrics.txt"
        Execute-DiagnosticCommand -Command "wcncli.exe --module wcn metrics" -OutFile $wcnMetricsFile

        # Get WCN service-info
        $wcnServiceInfoFile = Join-Path $wcnDebugDir "wcncli_service_info.txt"
        Execute-DiagnosticCommand -Command "wcncli.exe --module wcn service-info" -OutFile $wcnServiceInfoFile

        # Get kubeproxy logs
        $kubeproxyLogsDir = Join-Path $stateDir "kubeproxylogs"
        if (-not (Test-Path $kubeproxyLogsDir)) {
            New-Item -ItemType Directory -Path $kubeproxyLogsDir -Force
        }
        Log-Message "Copying kubeproxy logs (C:\k\kubeproxy.*)"
        Copy-Item -Path "C:\k\kubeproxy.*" -Destination $kubeproxyLogsDir -Force -ErrorAction Ignore

        # Get containerd logs
        $containerdLogsDir = Join-Path $stateDir "containerdlogs"
        if (-not (Test-Path $containerdLogsDir)) {
            New-Item -ItemType Directory -Path $containerdLogsDir -Force
        }
        Log-Message "Copying containerd logs (C:\k\containerd.*)"
        Copy-Item -Path "C:\k\containerd.*" -Destination $containerdLogsDir -Force -ErrorAction Ignore

        # Get CNI logs
        $cniLogsDir = Join-Path $stateDir "cnilogs"
        if (-not (Test-Path $cniLogsDir)) {
            New-Item -ItemType Directory -Path $cniLogsDir -Force
        }
        Log-Message "Copying CNI logs"
        Copy-Item -Path "C:\k\azure-vnet.log" -Destination $cniLogsDir -Force -ErrorAction Ignore
        Copy-Item -Path "C:\k\azure-vnet-telemetry.log" -Destination $cniLogsDir -Force -ErrorAction Ignore
        Copy-Item -Path "C:\k\azurecni\netconf\10-azure.conflist" -Destination $cniLogsDir -Force -ErrorAction Ignore
        Copy-Item -Path "C:\k\azurecns\*" -Destination $cniLogsDir -Force -ErrorAction Ignore

        # Get windows node reset logs
        Log-Message "Copying windows node reset logs (C:\k\windowsnodereset.log)"
        Copy-Item -Path "C:\k\windowsnodereset.log" -Destination $stateDir -Force -ErrorAction Ignore

        # Get agentbaker logs
        $agentbakerLogsDir = Join-Path $stateDir "agentbakerlogs"
        if (-not (Test-Path $agentbakerLogsDir)) {
            New-Item -ItemType Directory -Path $agentbakerLogsDir -Force
        }
        Log-Message "Copying agentbaker logs (C:\AzureData\CustomDataSetupScript.log)"
        Copy-Item -Path "C:\AzureData\CustomDataSetupScript.log" -Destination $agentbakerLogsDir -Force -ErrorAction Ignore

        # Get Node information
        $nodeInformationFile = Join-Path $stateDir "nodeinfo.txt"
        $services = $(
            "kubelet",
            "kubeproxy",
            "containerd",
            "docker",
            "hns",
            "xdp",
            "ebpfcore",
            "netebpfext",
            "wtc",
            "neteventebpfext",
            "pktmon"
        )
        foreach ($service in $services) {
            Execute-DiagnosticCommand -Command "Get-Service $service -ErrorAction SilentlyContinue" -OutFile $nodeInformationFile
        }
        Execute-DiagnosticCommand -Command "tasklist /m cncapi.dll" -OutFile $nodeInformationFile
        Execute-DiagnosticCommand -Command "tasklist /m wcnagent.dll" -OutFile $nodeInformationFile
        Execute-DiagnosticCommand -Command "reg query HKLM\SYSTEM\CurrentControlSet\Services\HNS /s" -OutFile $nodeInformationFile
        Execute-DiagnosticCommand -Command "Get-Hotfix" -OutFile $nodeInformationFile
        Execute-DiagnosticCommand -Command "Get-ItemProperty `"HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion`"" -OutFile $nodeInformationFile

        # Get networking information
        $networkDir = Join-Path $stateDir "network"
        # IP information
        $ipFile = Join-Path $networkDir "ip.txt"
        Execute-DiagnosticCommand -Command "ipconfig /allcompartments /all" -OutFile $ipFile
        Execute-DiagnosticCommand -Command "Get-NetIPAddress -IncludeAllCompartments" -OutFile $ipFile
        Execute-DiagnosticCommand -Command "Get-NetIPInterface -IncludeAllCompartments" -OutFile $ipFile
        # Routes
        $routeFile = Join-Path $networkDir "routes.txt"
        Execute-DiagnosticCommand -Command "route print" -OutFile $routeFile
        Execute-DiagnosticCommand -Command "Get-NetRoute -IncludeAllCompartments" -OutFile $routeFile
        # MTU
        $mtuFile = Join-Path $networkDir "mtu.txt"
        Execute-DiagnosticCommand -Command "netsh int ipv4 sh int" -OutFile $mtuFile
        Execute-DiagnosticCommand -Command "netsh int ipv6 sh int" -OutFile $mtuFile
        # NVSP Info
        $nvspFile = Join-Path $networkDir "nvspinfo.txt"
        Execute-DiagnosticCommand -Command "nvspinfo -a -i -h -D -p -d -m -q " -OutFile $nvspFile
        # nmscrub info
        $nmscrubFile = Join-Path $networkDir "nmscrub.txt"
        Execute-DiagnosticCommand -Command "nmscrub.exe -a -n -t" -OutFile $nmscrubFile
        # nmbind
        $nmbindFile = Join-Path $networkDir "nmbind.txt"
        Execute-DiagnosticCommand -Command "nmbind.exe" -OutFile $nmbindFile
        # arp
        $arpFile = Join-Path $networkDir "arp.txt"
        Execute-DiagnosticCommand -Command "arp -a" -OutFile $arpFile
        Execute-DiagnosticCommand -Command "Get-NetNeighbor -IncludeAllCompartments" -OutFile $arpFile
        # Netadapter
        $networkInfoFile = Join-Path $networkDir "netadapter.txt"
        Execute-DiagnosticCommand -Command "Get-NetAdapter" -OutFile $networkInfoFile
        # excluded port range
        $excludedPortRangeFile = Join-Path $networkDir "excludedportrange.txt"
        Execute-DiagnosticCommand -Command "netsh interface ipv4 show excludedportrange tcp" -OutFile $excludedPortRangeFile
        Execute-DiagnosticCommand -Command "netsh interface ipv4 show excludedportrange udp" -OutFile $excludedPortRangeFile
        Execute-DiagnosticCommand -Command "netsh interface ipv6 show excludedportrange tcp" -OutFile $excludedPortRangeFile
        Execute-DiagnosticCommand -Command "netsh interface ipv6 show excludedportrange udp" -OutFile $excludedPortRangeFile
        # dynamic port range
        $dynamicPortRangeFile = Join-Path $networkDir "dynamicportrange.txt"
        Execute-DiagnosticCommand -Command "netsh interface ipv4 show dynamicportrange tcp" -OutFile $dynamicPortRangeFile
        Execute-DiagnosticCommand -Command "netsh interface ipv4 show dynamicportrange udp" -OutFile $dynamicPortRangeFile
        Execute-DiagnosticCommand -Command "netsh interface ipv6 show dynamicportrange tcp" -OutFile $dynamicPortRangeFile
        Execute-DiagnosticCommand -Command "netsh interface ipv6 show dynamicportrange udp" -OutFile $dynamicPortRangeFile
        # TCP connections
        $tcpConnectionsFile = Join-Path $networkDir "tcpconnections.txt"
        Execute-DiagnosticCommand -Command "netsh int ipv4 sh tcpconnections" -OutFile $tcpConnectionsFile

        # HNS Endpoint info
        $hnsEndpointFile = Join-Path $networkDir "hnsendpoint.txt"
        Execute-DiagnosticCommand -Command "Get-HnsEndpoint | ConvertTo-Json -Depth 10" -OutFile $hnsEndpointFile

        # HNS Policy info
        $hnsPolicyFile = Join-Path $networkDir "hnspolicy.txt"
        Execute-DiagnosticCommand -Command "Get-HnsPolicyList | ConvertTo-Json -Depth 10" -OutFile $hnsPolicyFile

        # Get Kubelet logs
        Log-Message "Copying kubelet logs (C:\k\kubelet.err.log)"
        Copy-Item -Path "C:\k\kubelet.err.log" -Destination $stateDir -Force -ErrorAction Ignore
        Log-Message "Copying kubelet logs (C:\k\kubelet.log)"
        Copy-Item -Path "C:\k\kubelet.log" -Destination $stateDir -Force -ErrorAction Ignore
        Log-Message "Copying kubeclusterconfig.json (C:\k\kubeclusterconfig.json)"
        Copy-Item -Path "C:\k\kubeclusterconfig.json" -Destination $stateDir -Force -ErrorAction Ignore
    } catch {
        Log-Message "Failed to collect rundown state. $_" -Color Red
    }
    Log-Message "===== Get-RundownState operation completed ====="
}

mkdir logs -ErrorAction SilentlyContinue
Set-Location logs
Remove-Item -Recurse -Force * -ErrorAction SilentlyContinue

#============================== VFP =============================
$ports = (vfpctrl.exe /list-vmswitch-port /format 1 | ConvertFrom-Json).Ports.Name
foreach ($port in $ports) {
	Write-Output "Dumping vfp rules for Port: $port" > vfprules.txt
	vfpctrl /port $port /list-rule >> .\vfprules.txt
}

Get-RundownState -stateDir . -VerboseState:$true

#============================== EBPF =============================
Set-Location ..
Remove-Item logs.zip -ErrorAction SilentlyContinue
Compress-archive logs\* logs.zip