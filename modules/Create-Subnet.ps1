Import-Module -Force .\modules\constants.psm1

$rgName = $Global:RG_NAME
$location = $Global:LOCATION
$clusterName = $Global:CLUSTER_NAME

# Network configuration
$vnetName = $Global:VNET_NAME
$subnetName = $Global:SUBNET_NAME
$subnetPrefix = $Global:SUBNET_PREFIX
$vnetPrefix = $Global:VNET_PREFIX

Write-Host "Creating Virtual Network: $vnetName" -ForegroundColor Cyan
az network vnet create `
    --resource-group $rgName `
    --name $vnetName `
    --address-prefix $vnetPrefix `
    --location $location

Write-Host "Creating Subnet: $subnetName with prefix $subnetPrefix" -ForegroundColor Cyan
az network vnet subnet create `
    --resource-group $rgName `
    --vnet-name $vnetName `
    --name $subnetName `
    --address-prefix $subnetPrefix

# Get Subnet ID for AKS cluster creation
$subnetId = az network vnet subnet show `
    --resource-group $rgName `
    --vnet-name $vnetName `
    --name $subnetName `
    --query id -o tsv

# Store subnet ID globally for use by cluster creation scripts
$Global:SUBNET_ID = $subnetId

Write-Host "Subnet created successfully!" -ForegroundColor Green
Write-Host "Subnet ID: $subnetId" -ForegroundColor Yellow
