Import-Module -Force .\constants.psm1

$subscriptionId = $Global:SUBSCRIPTION_ID
$rgName = $Global:RG_NAME
$location = $Global:LOCATION

Write-Host "Creating Resource Group: $rgName in Location: $location" -ForegroundColor Cyan
az login
az account set --subscription $subscriptionId
az group create --name $rgName --location $location
Write-Host "Resource Group: $rgName created successfully in Location: $location." -ForegroundColor Green