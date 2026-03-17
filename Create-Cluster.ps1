[CmdletBinding()]
param(
    [switch]$isSingleStack,
    [switch]$useCustomSubnet
)

.\modules\Create-Rg.ps1

if ($useCustomSubnet) {
    .\modules\Create-Subnet.ps1
}

if ($isSingleStack) {
    .\modules\Create-Cluster-Singlestack.ps1 -useCustomSubnet:$useCustomSubnet
} else {
    .\modules\Create-Cluster-Dualstack.ps1 -useCustomSubnet:$useCustomSubnet
}

.\modules\Create-Nodepool.ps1

.\Create-PodsAndServices.ps1