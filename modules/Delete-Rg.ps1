Import-Module -Force .\modules\constants.psm1

$rgName = $Global:RG_NAME

Write-Host "Deleting Resource Group: $rgName" -ForegroundColor Cyan
az group delete --name $rgName --yes
Write-Host "Resource Group: $rgName deleted successfully." -ForegroundColor Green
