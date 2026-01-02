[CmdletBinding()]
param(
    [switch]$isSingleStack
)

.\modules\Create-Rg.ps1

if ($isSingleStack) {
    .\modules\Create-Cluster-Singlestack.ps1
} else {
    .\modules\Create-Cluster-Dualstack.ps1
}

.\modules\Create-Nodepool.ps1

.\Create-PodsAndServices.ps1