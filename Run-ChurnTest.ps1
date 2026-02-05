<#
.SYNOPSIS
    Churn Master Script for AKS Pod/Service Testing

.DESCRIPTION
    This script performs iterative churn testing with KWOK and real deployments,
    including service creation, scaling operations, and cleanup.

.PARAMETER Namespace
    Kubernetes namespace to use (default: demo)

.PARAMETER Iterations
    Number of churn iterations to perform (default: 20)

.PARAMETER TimeoutSeconds
    Timeout in seconds for waiting on pod readiness (default: 300)

.PARAMETER SkipIPv6
    Skip creating IPv6 services if the cluster doesn't support IPv6 (default: false)

.EXAMPLE
    .\Run-ChurnTest.ps1
    .\Run-ChurnTest.ps1 -Iterations 5 -Namespace demo
#>

param(
    [string]$Namespace = "demo",
    [int]$Iterations = 20,
    [int]$TimeoutSeconds = 300,
    [switch]$SkipIPv6
)

$ErrorActionPreference = "Stop"

# Paths to YAML templates
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$YamlDir = Join-Path $ScriptDir "Yamls\kwok"

$DepKwokYaml = Join-Path $YamlDir "dep-kwok.yaml"
$DepRealYaml = Join-Path $YamlDir "dep-real.yaml"
$SvcTemplateYaml = Join-Path $YamlDir "Svc-Template.yaml"
$NodeKwokYaml = Join-Path $YamlDir "nodes-kwok.yaml"
$KwokStagesYaml = Join-Path $YamlDir "kwok-stages.yaml"

# KWOK Node configuration
$KwokNodeCount = 50
$ServiceIndexStart = 1
$ServiceIndexEnd = 10
$DepRealCount = 5
$MaxRealPods = 30

# Service configurations: Name prefix, IP Family, Traffic Policy
$ServiceConfigs = @(
    @{ NamePrefix = "httpserver-ipv4-cluster"; IPFamily = "IPv4"; TrafficPolicy = "Cluster" },
    @{ NamePrefix = "httpserver-ipv4-local"; IPFamily = "IPv4"; TrafficPolicy = "Local" }
)
if (-not $SkipIPv6) {
    $ServiceConfigs += @(
        @{ NamePrefix = "httpserver-ipv6-cluster"; IPFamily = "IPv6"; TrafficPolicy = "Cluster" },
        @{ NamePrefix = "httpserver-ipv6-local"; IPFamily = "IPv6"; TrafficPolicy = "Local" }
    )
}

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "INFO"    { "White" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        default   { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Wait-ForPods {
    param(
        [string]$LabelSelector,
        [int]$ExpectedCount,
        [string]$Namespace,
        [int]$TimeoutSeconds = 300
    )

    Write-Log "Waiting for $ExpectedCount pods with selector '$LabelSelector' to be ready..."
    
    $startTime = Get-Date
    $ready = $false
    
    while (-not $ready) {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
            Write-Log "Timeout waiting for pods. Expected: $ExpectedCount" "ERROR"
            kubectl get pods -n $Namespace -l $LabelSelector
            return $false
        }

        $pods = kubectl get pods -n $Namespace -l $LabelSelector -o json | ConvertFrom-Json
        $runningPods = ($pods.items | Where-Object { $_.status.phase -eq "Running" }).Count
        
        if ($runningPods -eq $ExpectedCount) {
            $ready = $true
            Write-Log "All $ExpectedCount pods are running." "SUCCESS"
        }
        else {
            Write-Host "." -NoNewline
            Start-Sleep -Seconds 5
        }
    }
    
    return $true
}

function Wait-ForPodsTerminated {
    param(
        [string]$LabelSelector,
        [string]$Namespace,
        [int]$TimeoutSeconds = 300
    )

    Write-Log "Waiting for pods with selector '$LabelSelector' to terminate..."
    
    $startTime = Get-Date
    
    while ($true) {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
            Write-Log "Timeout waiting for pods to terminate." "ERROR"
            return $false
        }

        $pods = kubectl get pods -n $Namespace -l $LabelSelector -o json 2>$null | ConvertFrom-Json
        $podCount = $pods.items.Count
        
        if ($podCount -eq 0) {
            Write-Log "All pods terminated." "SUCCESS"
            return $true
        }
        
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 5
    }
}

function Wait-ForServicesReady {
    param(
        [string]$Namespace,
        [int]$ExpectedCount,
        [int]$TimeoutSeconds = 600
    )

    Write-Log "Waiting for $ExpectedCount services to get ExternalIP assigned..."
    
    $startTime = Get-Date
    
    while ($true) {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
            Write-Log "Timeout waiting for services to get ExternalIP. Check service status." "ERROR"
            kubectl get svc -n $Namespace | Select-String "httpserver-ip"
            return $false
        }

        $services = kubectl get svc -n $Namespace -o json | ConvertFrom-Json
        $churnServices = $services.items | Where-Object { $_.metadata.name -match "httpserver-ip" }
        
        # Count services with ExternalIP assigned (not <pending>)
        $readyServices = $churnServices | Where-Object { 
            $_.status.loadBalancer.ingress -and $_.status.loadBalancer.ingress.Count -gt 0
        }
        $readyCount = $readyServices.Count
        
        if ($readyCount -ge $ExpectedCount) {
            Write-Log "All $readyCount services have ExternalIP assigned." "SUCCESS"
            return $true
        }
        
        Write-Host "." -NoNewline
        Write-Log "Services ready: $readyCount / $ExpectedCount" "INFO"
        Start-Sleep -Seconds 10
    }
}

function Apply-YamlWithIndexReplacement {
    param(
        [string]$YamlPath,
        [int]$Index
    )

    $content = Get-Content -Path $YamlPath -Raw
    $modifiedContent = $content -replace "index", $Index
    $ErrorActionPreference = "SilentlyContinue"
    $modifiedContent | kubectl apply -f - 2>&1 | Out-Null
    $ErrorActionPreference = "Stop"
}

function Delete-YamlWithIndexReplacement {
    param(
        [string]$YamlPath,
        [int]$Index
    )

    $content = Get-Content -Path $YamlPath -Raw
    $modifiedContent = $content -replace "index", $Index
    $ErrorActionPreference = "SilentlyContinue"
    $modifiedContent | kubectl delete -f - --ignore-not-found 2>&1 | Out-Null
    $ErrorActionPreference = "Stop"
}

function Apply-ServiceFromTemplate {
    param(
        [string]$NamePrefix,
        [string]$IPFamily,
        [string]$TrafficPolicy,
        [int]$Index
    )

    $content = Get-Content -Path $SvcTemplateYaml -Raw
    $serviceName = "$NamePrefix-$Index"
    
    # Replace placeholders
    $modifiedContent = $content -replace "__SERVICENAME__", $serviceName
    $modifiedContent = $modifiedContent -replace "__NAMESPACE__", $Namespace
    $modifiedContent = $modifiedContent -replace "__IPFAMILY__", $IPFamily
    
    # Handle traffic policy - only add externalTrafficPolicy for Local
    if ($TrafficPolicy -eq "Local") {
        $modifiedContent = $modifiedContent -replace "__TRAFFICPOLICY__", "externalTrafficPolicy: Local"
    } else {
        $modifiedContent = $modifiedContent -replace "  __TRAFFICPOLICY__`r?`n", ""
    }
    
    $ErrorActionPreference = "SilentlyContinue"
    $modifiedContent | kubectl apply -f - 2>&1 | Out-Null
    $ErrorActionPreference = "Stop"
}

function Delete-ServiceFromTemplate {
    param(
        [string]$NamePrefix,
        [string]$IPFamily,
        [string]$TrafficPolicy,
        [int]$Index
    )

    $content = Get-Content -Path $SvcTemplateYaml -Raw
    $serviceName = "$NamePrefix-$Index"
    
    # Replace placeholders
    $modifiedContent = $content -replace "__SERVICENAME__", $serviceName
    $modifiedContent = $modifiedContent -replace "__NAMESPACE__", $Namespace
    $modifiedContent = $modifiedContent -replace "__IPFAMILY__", $IPFamily
    
    # Handle traffic policy
    if ($TrafficPolicy -eq "Local") {
        $modifiedContent = $modifiedContent -replace "__TRAFFICPOLICY__", "externalTrafficPolicy: Local"
    } else {
        $modifiedContent = $modifiedContent -replace "  __TRAFFICPOLICY__`r?`n", ""
    }
    
    $ErrorActionPreference = "SilentlyContinue"
    $modifiedContent | kubectl delete -f - --ignore-not-found 2>&1 | Out-Null
    $ErrorActionPreference = "Stop"
}

function Create-KwokNodes {
    param([int]$NodeCount = 500)

    Write-Log "=== Creating $NodeCount KWOK Nodes ===" "INFO"
    
    # Ensure KWOK Stages are applied (required for nodes to become Ready)
    Write-Log "Applying KWOK Stages..."
    $ErrorActionPreference = "SilentlyContinue"
    kubectl apply -f $KwokStagesYaml 2>&1 | Out-Null
    $ErrorActionPreference = "Stop"
    
    $content = Get-Content -Path $NodeKwokYaml -Raw
    
    for ($i = 1; $i -le $NodeCount; $i++) {
        $modifiedContent = $content -replace "__INDEX__", $i
        $ErrorActionPreference = "SilentlyContinue"
        $modifiedContent | kubectl apply -f - 2>&1 | Out-Null
        $ErrorActionPreference = "Stop"
        
        if ($i % 50 -eq 0) {
            Write-Log "Created $i / $NodeCount KWOK nodes..." "INFO"
        }
    }
    
    # Wait for nodes to be ready
    Write-Log "Waiting for KWOK nodes to be Ready..."
    $startTime = Get-Date
    while ($true) {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
            Write-Log "Timeout waiting for KWOK nodes to be Ready." "ERROR"
            return $false
        }
        
        $nodes = kubectl get nodes -l type=kwok -o json | ConvertFrom-Json
        $readyNodes = ($nodes.items | Where-Object { 
            ($_.status.conditions | Where-Object { $_.type -eq "Ready" -and $_.status -eq "True" }).Count -gt 0
        }).Count
        
        if ($readyNodes -ge $NodeCount) {
            Write-Log "All $NodeCount KWOK nodes are Ready." "SUCCESS"
            return $true
        }
        
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 5
    }
}

function Delete-KwokNodes {
    param([int]$NodeCount = 500)

    Write-Log "=== Deleting $NodeCount KWOK Nodes ===" "INFO"
    
    $content = Get-Content -Path $NodeKwokYaml -Raw
    
    for ($i = 1; $i -le $NodeCount; $i++) {
        $modifiedContent = $content -replace "__INDEX__", $i
        $ErrorActionPreference = "SilentlyContinue"
        $modifiedContent | kubectl delete -f - --ignore-not-found 2>&1 | Out-Null
        $ErrorActionPreference = "Stop"
        
        if ($i % 50 -eq 0) {
            Write-Log "Deleted $i / $NodeCount KWOK nodes..." "INFO"
        }
    }
    
    Write-Log "All KWOK nodes deletion initiated." "SUCCESS"
}

# ============================================================================
# Step Functions
# ============================================================================

function Step1-CreateServices {
    Write-Log "=== STEP 1: Creating Services ===" "INFO"
    
    $serviceCount = $ServiceIndexEnd - $ServiceIndexStart + 1
    $totalServices = $ServiceConfigs.Count * $serviceCount
    Write-Log "Creating $totalServices services..."

    foreach ($svcConfig in $ServiceConfigs) {
        for ($i = $ServiceIndexStart; $i -le $ServiceIndexEnd; $i++) {
            Apply-ServiceFromTemplate -NamePrefix $svcConfig.NamePrefix -IPFamily $svcConfig.IPFamily `
                                      -TrafficPolicy $svcConfig.TrafficPolicy -Index $i
        }
        Write-Log "Created $serviceCount copies of $($svcConfig.NamePrefix)"
    }

    # Verify services created
    Start-Sleep -Seconds 2
    $services = kubectl get svc -n $Namespace -o json | ConvertFrom-Json
    $churnServices = $services.items | Where-Object { $_.metadata.name -match "httpserver-ip" }
    Write-Log "Total services created: $($churnServices.Count)" "INFO"

    # Wait for all services to get ExternalIP assigned
    Wait-ForServicesReady -Namespace $Namespace -ExpectedCount $totalServices -TimeoutSeconds $TimeoutSeconds

    Write-Log "All services are ready with ExternalIP." "SUCCESS"
}

function Step2-CreateDeployments {
    Write-Log "=== STEP 2: Creating Deployments ===" "INFO"
    
    # Create dep-kwok (no index replacement needed)
    Write-Log "Creating dep-kwok..."
    kubectl apply -f $DepKwokYaml 2>&1 | Out-Null

    # Create dep-real-1 to dep-real-5
    Write-Log "Creating dep-real deployments (1-$DepRealCount)..."
    for ($i = 1; $i -le $DepRealCount; $i++) {
        Apply-YamlWithIndexReplacement -YamlPath $DepRealYaml -Index $i
    }

    # Wait for initial pods
    Wait-ForPods -LabelSelector "app=httpserver" -ExpectedCount (1 + $DepRealCount) -Namespace $Namespace -TimeoutSeconds $TimeoutSeconds

    Write-Log "All deployments created." "SUCCESS"
}

function Step3-ScaleUp {
    param([int]$KwokReplicas = 500, [int]$RealReplicasPerDep = 10, [int]$KwokScaleStep = 25)
    
    Write-Log "=== STEP 3/5/7: Scaling UP ===" "INFO"
    
    # Calculate real replicas to not exceed max
    $totalRealTarget = $DepRealCount * $RealReplicasPerDep
    if ($totalRealTarget -gt $MaxRealPods) {
        $RealReplicasPerDep = [math]::Floor($MaxRealPods / $DepRealCount)
        Write-Log "Adjusted real replicas per deployment to $RealReplicasPerDep to stay within $MaxRealPods limit" "WARNING"
    }
    $totalRealExpected = $DepRealCount * $RealReplicasPerDep

    # Scale each dep-real first
    Write-Log "Scaling each dep-real to $RealReplicasPerDep replicas..."
    for ($i = 1; $i -le $DepRealCount; $i++) {
        kubectl scale deployment "dep-real-$i" -n $Namespace --replicas=$RealReplicasPerDep 2>&1 | Out-Null
    }

    # Get current KWOK replica count
    $currentKwok = 0
    $depJson = kubectl get deployment dep-kwok -n $Namespace -o json 2>$null | ConvertFrom-Json
    if ($depJson) {
        $currentKwok = [int]$depJson.spec.replicas
    }

    # Scale dep-kwok gradually by $KwokScaleStep
    Write-Log "Scaling dep-kwok from $currentKwok to $KwokReplicas (step: $KwokScaleStep)..."
    while ($currentKwok -lt $KwokReplicas) {
        $currentKwok = [math]::Min($currentKwok + $KwokScaleStep, $KwokReplicas)
        kubectl scale deployment dep-kwok -n $Namespace --replicas=$currentKwok 2>&1 | Out-Null
        
        $totalExpected = $currentKwok + $totalRealExpected
        Wait-ForPods -LabelSelector "app=httpserver" -ExpectedCount $totalExpected -Namespace $Namespace -TimeoutSeconds $TimeoutSeconds
        Write-Log "KWOK scaled to $currentKwok" "INFO"
    }

    Write-Log "Scale UP complete. KWOK: $KwokReplicas, Real: $totalRealExpected" "SUCCESS"
}

function Step4-ScaleDown {
    param([int]$KwokReplicas = 10, [int]$RealReplicasPerDep = 2, [int]$KwokScaleStep = 25)

    Write-Log "=== STEP 4: Scaling DOWN ===" "INFO"
    
    $totalRealExpected = $DepRealCount * $RealReplicasPerDep

    # Scale each dep-real first
    Write-Log "Scaling each dep-real to $RealReplicasPerDep replicas..."
    for ($i = 1; $i -le $DepRealCount; $i++) {
        kubectl scale deployment "dep-real-$i" -n $Namespace --replicas=$RealReplicasPerDep 2>&1 | Out-Null
    }

    # Get current KWOK replica count
    $currentKwok = 0
    $depJson = kubectl get deployment dep-kwok -n $Namespace -o json 2>$null | ConvertFrom-Json
    if ($depJson) {
        $currentKwok = [int]$depJson.spec.replicas
    }

    # Scale dep-kwok gradually by $KwokScaleStep
    Write-Log "Scaling dep-kwok from $currentKwok to $KwokReplicas (step: $KwokScaleStep)..."
    while ($currentKwok -gt $KwokReplicas) {
        $currentKwok = [math]::Max($currentKwok - $KwokScaleStep, $KwokReplicas)
        kubectl scale deployment dep-kwok -n $Namespace --replicas=$currentKwok 2>&1 | Out-Null
        
        $totalExpected = $currentKwok + $totalRealExpected
        Wait-ForPods -LabelSelector "app=httpserver" -ExpectedCount $totalExpected -Namespace $Namespace -TimeoutSeconds $TimeoutSeconds
        Write-Log "KWOK scaled to $currentKwok" "INFO"
    }

    Write-Log "Scale DOWN complete. KWOK: $KwokReplicas, Real: $totalRealExpected" "SUCCESS"
}

function Step6-ScaleToZero {
    param([int]$KwokScaleStep = 25)
    
    Write-Log "=== STEP 6: Scaling to ZERO ===" "INFO"
    
    # Scale each dep-real to 0 first
    Write-Log "Scaling each dep-real to 0 replicas..."
    for ($i = 1; $i -le $DepRealCount; $i++) {
        kubectl scale deployment "dep-real-$i" -n $Namespace --replicas=0 2>&1 | Out-Null
    }

    # Get current KWOK replica count
    $currentKwok = 0
    $depJson = kubectl get deployment dep-kwok -n $Namespace -o json 2>$null | ConvertFrom-Json
    if ($depJson) {
        $currentKwok = [int]$depJson.spec.replicas
    }

    # Scale dep-kwok gradually to 0 by $KwokScaleStep
    Write-Log "Scaling dep-kwok from $currentKwok to 0 (step: $KwokScaleStep)..."
    while ($currentKwok -gt 0) {
        $currentKwok = [math]::Max($currentKwok - $KwokScaleStep, 0)
        kubectl scale deployment dep-kwok -n $Namespace --replicas=$currentKwok 2>&1 | Out-Null
        
        Wait-ForPods -LabelSelector "app=httpserver" -ExpectedCount $currentKwok -Namespace $Namespace -TimeoutSeconds $TimeoutSeconds
        Write-Log "KWOK scaled to $currentKwok" "INFO"
    }

    Write-Log "Scale to ZERO complete." "SUCCESS"
}

function Step8-DeleteDeployments {
    Write-Log "=== STEP 8: Deleting Deployments ===" "INFO"
    
    # Delete dep-kwok
    Write-Log "Deleting dep-kwok..."
    kubectl delete -f $DepKwokYaml --ignore-not-found 2>&1 | Out-Null

    # Delete all dep-real
    Write-Log "Deleting dep-real deployments..."
    for ($i = 1; $i -le $DepRealCount; $i++) {
        Delete-YamlWithIndexReplacement -YamlPath $DepRealYaml -Index $i
    }

    # Wait for pods to terminate
    Start-Sleep -Seconds 5
    Wait-ForPodsTerminated -LabelSelector "app=httpserver" -Namespace $Namespace -TimeoutSeconds $TimeoutSeconds

    Write-Log "All deployments deleted." "SUCCESS"
}

function Step10-DeleteServices {
    Write-Log "=== STEP 10: Deleting All Services ===" "INFO"
    
    foreach ($svcConfig in $ServiceConfigs) {
        for ($i = $ServiceIndexStart; $i -le $ServiceIndexEnd; $i++) {
            Delete-ServiceFromTemplate -NamePrefix $svcConfig.NamePrefix -IPFamily $svcConfig.IPFamily `
                                       -TrafficPolicy $svcConfig.TrafficPolicy -Index $i
        }
    }

    Write-Log "All services deleted." "SUCCESS"
}

# ============================================================================
# Main Execution
# ============================================================================

function Main {
    Write-Log "========================================" "INFO"
    Write-Log "    CHURN TEST MASTER SCRIPT" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "Namespace: $Namespace"
    Write-Log "Iterations: $Iterations"
    Write-Log "YAML Directory: $YamlDir"
    Write-Log "Max Real Pods: $MaxRealPods"
    Write-Log "Service Types: $($ServiceConfigs.Count)"
    Write-Log "KWOK Nodes: $KwokNodeCount"
    Write-Log "========================================" "INFO"

    Write-Log "Deploying KWOK Controller and Stages..." "INFO"

    kubectl apply -f https://github.com/kubernetes-sigs/kwok/releases/latest/download/kwok.yaml

    # Verify YAML files exist
    $requiredFiles = @($DepKwokYaml, $DepRealYaml, $SvcTemplateYaml, $NodeKwokYaml, $KwokStagesYaml)
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path $file)) {
            Write-Log "Required YAML file not found: $file" "ERROR"
            return
        }
    }
    Write-Log "All required YAML files found." "SUCCESS"

    $overallStartTime = Get-Date

    # Ensure namespace exists (ignore if already exists)
    $ErrorActionPreference = "SilentlyContinue"
    kubectl create namespace $Namespace 2>&1 | Out-Null
    $ErrorActionPreference = "Stop"

    # Step 0: Create KWOK nodes
    Create-KwokNodes -NodeCount $KwokNodeCount
    
    # Step 1: Create all services (once at the beginning)
    Step1-CreateServices

    # Steps 2-8 repeated for $Iterations times
    for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
        Write-Log "========================================"
        Write-Log "    ITERATION $iteration of $Iterations" "INFO"
        Write-Log "========================================"

        $iterationStartTime = Get-Date

        # Step 2: Create deployments
        Step2-CreateDeployments

        # Step 3: Scale UP (500 KWOK, 10 real each)
        Step3-ScaleUp -KwokReplicas 500 -RealReplicasPerDep 10

        # Step 4: Scale DOWN (10 KWOK, 2 real each)
        Step4-ScaleDown -KwokReplicas 10 -RealReplicasPerDep 2

        # Step 5: Scale UP again (500 KWOK, 10 real each)
        Step3-ScaleUp -KwokReplicas 500 -RealReplicasPerDep 10

        # Step 6: Scale to ZERO
        Step6-ScaleToZero

        # Step 7: Scale UP again (500 KWOK, 10 real each)
        Step3-ScaleUp -KwokReplicas 500 -RealReplicasPerDep 10

        # Step 8: Delete all deployments
        Step8-DeleteDeployments

        $iterationDuration = (Get-Date) - $iterationStartTime
        Write-Log "Iteration $iteration completed in $($iterationDuration.TotalMinutes.ToString('F2')) minutes" "SUCCESS"
    }

    # Step 10: Delete all services
    Step10-DeleteServices

    # Step 11: Delete KWOK nodes
    Delete-KwokNodes -NodeCount $KwokNodeCount

    $overallDuration = (Get-Date) - $overallStartTime
    Write-Log "========================================" "SUCCESS"
    Write-Log "CHURN TEST COMPLETED" "SUCCESS"
    Write-Log "Total Duration: $($overallDuration.TotalMinutes.ToString('F2')) minutes" "SUCCESS"
    Write-Log "========================================" "SUCCESS"
}

# Run the main function
Main
