<#
.SYNOPSIS
Remove Application Gateway publishing rules if it has been created with the naming convention used here : https://github.com/JamesDLD/AzureRm-PowerShell/blob/master/Publish-AzAppOnApg.ps1/?WT.mc_id=DOP-MVP-5003548

.NOTES
   AUTHOR: James Dumont le Douarec
   
.EXAMPLE
./Remove-AzAppOnApg.ps1
#>

## Global variables
$AzureRmSubscriptionName = "mvp-sub1"
$RgName = "infr-hub-prd-rg1"
$AppGwName = "mvp-hub-agw1"

$Rules = @(
  # @{
  #   ApplicationName = "myapp1apiprd" #only letters!
  # };
  @{
    ApplicationName = "myapp1apidev" #only letters!
  };
  # @{
  #   ApplicationName = "myapp1apistg" #only letters!
  # };
)

## Connectivity
# Login first with Connect-AzAccount if not using Cloud Shell
$AzureRmContext = Get-AzSubscription -SubscriptionName $AzureRmSubscriptionName | Set-AzContext -ErrorAction Stop
Select-AzSubscription -Name $AzureRmSubscriptionName -Context $AzureRmContext -Force -ErrorAction Stop | Out-Null

Foreach ($Rule in $Rules) {

  $AppGw = Get-AzApplicationGateway -Name $AppGwName -ResourceGroupName $RgName

  #Health Probe
  $ProbeConfig = Get-AzApplicationGatewayProbeConfig -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-hpb" }
  if ($ProbeConfig) {
    Write-Host "Delete the Health Probe configuration"  -ForegroundColor Cyan
    Remove-AzApplicationGatewayProbeConfig -ApplicationGateway $AppGw  -Name $ProbeConfig.Name | Out-Null
  }

  #Routing rule
  $rule01 = Get-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-rqrt-https" }
  if ($rule01) {
    Write-Host "Delete Request Routing Rule $($Rule.ApplicationName)-rqrt-https" -ForegroundColor Cyan
    Remove-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw -Name $rule01.Name | Out-Null 
  }

  $rule02 = Get-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-rqrt-http" }
  if ($rule02) {
    Write-Host "Delete Request Routing Rule $($Rule.ApplicationName)-rqrt-http" -ForegroundColor Cyan
    Remove-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw -Name $rule02.Name | Out-Null 
  }

  $listener01 = Get-AzApplicationGatewayHttpListener -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-ln-443" }
  if ($listener01) {
    Write-Host "Delete the listener $($Rule.ApplicationName)-ln-443" -ForegroundColor Cyan
    Remove-AzApplicationGatewayHttpListener -ApplicationGateway $appgw -Name $listener01.Name | Out-Null
  }

  $listener02 = Get-AzApplicationGatewayHttpListener -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-ln-80" }
  if ($listener02) {
    Write-Host "Delete the listener $($Rule.ApplicationName)-ln-80" -ForegroundColor Cyan
    Remove-AzApplicationGatewayHttpListener -ApplicationGateway $appgw -Name $listener02.Name | Out-Null
  }

  #Backend Http
  $poolSetting01 = Get-AzApplicationGatewayBackendHttpSetting -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-be-htst1" }
  if ($poolSetting01) {
    Write-Host "Delete Backend setting $($Rule.ApplicationName)-be-htst1" -ForegroundColor Cyan
    Remove-AzApplicationGatewayBackendHttpSetting -ApplicationGateway $appgw -Name $poolSetting01.Name | Out-Null
  }

  #Backend Address Pool
  $pool = Get-AzApplicationGatewayBackendAddressPool -ApplicationGateway $appgw | where-object { $_.Name -like "$($Rule.ApplicationName)-pool1" }
  if ($pool) {
    Write-Host "Delete the Pool $($Rule.ApplicationName)-pool1"
    Remove-AzApplicationGatewayBackendAddressPool -ApplicationGateway $appgw -Name $pool.Name | Out-Null
  }

  #Redirection configuration
  $redirectConfig = Get-AzApplicationGatewayRedirectConfiguration -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-rqrt-https" }
  if ($redirectConfig) {
    Write-Host "Delete the redirection configuration"  -ForegroundColor Cyan
    Remove-AzApplicationGatewayRedirectConfiguration -ApplicationGateway $appgw -Name $redirectConfig.Name | Out-Null
  }

  #Pushing the configuration on the Application Gateway
  Write-Host "Updating the Application Gateway : $AppGwName" -ForegroundColor Cyan
  Set-AzApplicationGateway -ApplicationGateway $appgw | Out-Null
  #endregion

}