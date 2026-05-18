$Global:SUBSCRIPTION_ID="b8c06bcd-5024-43fa-9507-691b5623f59a"
$Global:RG_NAME="pper-vfptest-rg"
$Global:LOCATION="westus2"
$Global:CLUSTER_NAME="pper-vfptest-aks"
$Global:NODE_USER_NAME="prince"
$Global:NODE_PASSWORD="prince@123456123456"
$Global:NETCONNECT_REGISTRY="wcninternal"
# $Global:K8S_VERSION="1.30.100", 1.34.3, 1.32.7, 1.34.6
# az aks get-versions --location westus2 --output table
$Global:K8S_VERSION="1.34.6"
$Global:NODE_POOL_NAME="npwin"
$Global:OS_SKU="Windows2022"
$Global:NODE_COUNT="2"
$Global:NODE_VM_SIZE="Standard_D4s_v5" # Standard_D4s_v5 (Low CPU) / Standard_E8-2as_v5 (High CPU) / Standard_E8-2as_v7
$Global:NODE_POOL_ZONES=@(1,2)  # e.g. @(1,2,3) for zones 1,2,3; empty for no zones

$Global:VNET_NAME="pper-vfptest-vnet"
$Global:SUBNET_NAME="pper-vfptest-subnet"
$Global:VNET_PREFIX="172.16.0.0/16"
$Global:SUBNET_PREFIX="172.16.7.0/24"

$Global:HPC_NAME="hpc-ds-win"
$Global:NAMESPACE  ="demo"
$Global:SERVER_POD_DEPLOYMENT="server"
$Global:CLIENT_POD_DEPLOYMENT="client"
$Global:LOGS_ROOT_DIR="C:\Users\ppereira\Logs\Bugs\Cilium\KubeProxyDualStackbehav"