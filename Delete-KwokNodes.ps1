<#
.SYNOPSIS
    Deletes all KWOK nodes from the cluster

.DESCRIPTION
    This script identifies and deletes all KWOK fake nodes (nodes with names starting with "kwok-node-")

.EXAMPLE
    .\Delete-KwokNodes.ps1
#>

param(
    [switch]$Force
)

Write-Host "Fetching KWOK nodes..." -ForegroundColor Yellow

# Get all nodes that match kwok-node pattern
$kwokNodes = kubectl get nodes -o name | Where-Object { $_ -match "kwok-node" }

if ($kwokNodes.Count -eq 0) {
    Write-Host "No KWOK nodes found." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($kwokNodes.Count) KWOK nodes to delete." -ForegroundColor Cyan

if (-not $Force) {
    $confirm = Read-Host "Are you sure you want to delete all KWOK nodes? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

# Delete all KWOK nodes
foreach ($node in $kwokNodes) {
    Write-Host "Deleting $node..." -ForegroundColor DarkYellow
    kubectl delete $node --force --grace-period=0 2>$null
}

Write-Host "All KWOK nodes deleted." -ForegroundColor Green
