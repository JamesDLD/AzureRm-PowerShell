<#
Creating an Application Gateway with the following parameters
- Create a self signed certificate or re use an existing one if it exists in the Key Vault
- Create a Backend Pool that points to Backend FQDNs
- Create 2 frontend ports if they doesn't exist : feport-80 and feport-443

Prerequisites
- Application Gateway
- Key Vault

Tips
Get-AzApplicationGatewayHttpListener -ApplicationGateway $appgw | Select-Object Name,Protocol,Hostnames,Hostname

#>
#Based on 
#https://docs.microsoft.com/en-us/azure/application-gateway/configure-keyvault-ps
#https://docs.microsoft.com/en-us/azure/application-gateway/tutorial-http-header-rewrite-powershell
#https://docs.microsoft.com/en-us/azure/application-gateway/rewrite-http-headers
#https://medium.com/objectsharp/azure-application-gateway-http-headers-rewrite-rules-for-app-service-with-aad-authentication-b1092a58b60 

## Global variables
$AzureRmSubscriptionName = "mvp-sub1"
$RgName = "infr-hub-prd-rg1"
$AppGwName = "mvp-hub-agw1"
$KeyVaultName = "mvp-hub-kv1"

$Rules = @(
  # @{
  #   ApplicationName = "myapp1dev" #only letters!
  #   CertificateName = "myapp1devwebhelpcom"
  #   SubjectName     = "CN=myapp1-dev.webhelp.com"
  #   Hostname       = "myapp1-dev.webhelp.com"
  #   BackendFqdns    = "dev-myapp1-uiapp1.azurewebsites.net"
  #   ProbePath       = "/"
  # };
  @{
    ApplicationName = "myapp1apidev" #only letters!
    CertificateName = "myapp1apidevdld23com"
    SubjectName     = "CN=myapp1-api-dev.dld23.com"
    Hostname       = "myapp1-api-dev.dld23.com"
    BackendFqdns    = "dev-myapp1-apiapp1.azurewebsites.net"
    ProbePath       = "/"
  };
)

## Connectivity
# Login first with Connect-AzAccount if not using Cloud Shell
$AzureRmContext = Get-AzSubscription -SubscriptionName $AzureRmSubscriptionName | Set-AzContext -ErrorAction Stop
Select-AzSubscription -Name $AzureRmSubscriptionName -Context $AzureRmContext -Force -ErrorAction Stop

Foreach ($Rule in $Rules) {
  #region Certificate
  # Create a policy and the certificate to be used by the application gateway

  if (Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $Rule.CertificateName) {
    Write-Host "Re using the EXISTING certificate having the name : $($Rule.CertificateName)" -ForegroundColor DarkYellow
    $certificate = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $Rule.CertificateName
  }
  else {
    Write-Host "Creating a self signed certificat with the name : $($Rule.CertificateName)" -ForegroundColor Cyan
    $policy = New-AzKeyVaultCertificatePolicy -ValidityInMonths 12 `
      -SubjectName $Rule.SubjectName -IssuerName self `
      -RenewAtNumberOfDaysBeforeExpiry 30
    $certificate = Add-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $Rule.CertificateName -CertificatePolicy $policy
  }

  Write-Host "Getting the Secret id of the certificate named : $($Rule.CertificateName)" -ForegroundColor Cyan
  Start-Sleep -s 10 #Wait for the certificate to be available
  $certificate = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $Rule.CertificateName
  $secretId = $certificate.SecretId.Replace($certificate.Version, "")

  #Specify the Certificate
  Write-Host "Pointing the TLS/SSL certificate to our key vault" -ForegroundColor Cyan
  $sslCert01 = Get-AzApplicationGatewaySslCertificate -ApplicationGateway $appgw | where-object { $_.Name -like "$($Rule.CertificateName)" }
  if (!$sslCert01) {
    Write-Host "Creating the Certificat $($Rule.CertificateName)"
    Add-AzApplicationGatewaySslCertificate -ApplicationGateway $appgw -Name $($Rule.CertificateName) -KeyVaultSecretId $secretId
    $sslCert01 = Get-AzApplicationGatewaySslCertificate -ApplicationGateway $appgw | where-object { $_.Name -like "$($Rule.CertificateName)" }
  }
  #endregion

  #region Listener
  #region Application Gateway rule
  $AppGw = Get-AzApplicationGateway -Name $AppGwName -ResourceGroupName $RgName
  Write-Host "Creating pool and front-end ports" -ForegroundColor Cyan

  #Specify the Front End Port
  $fp01 = Get-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw | where-object { $_.Port -like "443" }
  if (!$fp01) {
    Write-Host "Creating the FrontendPort feport-443"
    Add-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw -Name "feport-443" -Port 443
    $fp01 = Get-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw | where-object { $_.Port -like "443" }
  }

  $fp02 = Get-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw | where-object { $_.Port -like "80" }
  if (!$fp02) {
    Write-Host "Creating the FrontendPort $($Rule.ApplicationName)-feport-80"
    Add-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw -Name "feport-80" -Port 80
    $fp02 = Get-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw | where-object { $_.Port -like "80" }
  }

  #Specify the HTTP listener
  Write-Host "Creating listeners, rules, and autoscale" -ForegroundColor Cyan
  $fipconfig01 = Get-AzApplicationGatewayFrontendIPConfig -ApplicationGateway $AppGw | Where-Object { $_.PublicIPAddress -ne $null }

  $listener01 = Get-AzApplicationGatewayHttpListener -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-ln-443" }
  if (!$listener01) {
    Write-Host "Creating the listener $($Rule.ApplicationName)-ln-443)"
    Add-AzApplicationGatewayHttpListener -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-ln-443" -Protocol Https `
      -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp01 -SslCertificate $sslCert01 -Hostname $Rule.Hostname
    $listener01 = Get-AzApplicationGatewayHttpListener -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-ln-443" }
  }

  $listener02 = Get-AzApplicationGatewayHttpListener -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-ln-80" }
  if (!$listener02) {
    Write-Host "Creating the listener $($Rule.ApplicationName)-ln-80)"
    Add-AzApplicationGatewayHttpListener -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-ln-80" -Protocol Http `
      -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp02 -Hostname $Rule.Hostname
    $listener02 = Get-AzApplicationGatewayHttpListener -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-ln-80" }
  }

  #Add the redirection configuration
  $redirectConfig = Get-AzApplicationGatewayRedirectConfiguration -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-rqrt-https" }
  if (!$redirectConfig) {
    Write-Host "Adding the redirection configuration"  -ForegroundColor Cyan
    Add-AzApplicationGatewayRedirectConfiguration -ApplicationGateway $appgw `
      -Name "$($Rule.ApplicationName)-rqrt-https" `
      -RedirectType Permanent `
      -TargetListener $listener01 `
      -IncludePath $true `
      -IncludeQueryString $true
    $redirectConfig = Get-AzApplicationGatewayRedirectConfiguration -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-rqrt-https" }
  }
  #endregion

  #region HTTP header rewrite
  #Specify your HTTP header rewrite rule configuration
  $RewriteRuleSet = Get-AzApplicationGatewayRewriteRuleSet -ApplicationGateway $appgw | Where-Object { $_.Name -eq "appservice-rwrst1" }
  if (!$RewriteRuleSet) {
    Write-Host "Adding the HTTP header rewrite rule configuration appservice-rwrst" -ForegroundColor Cyan

#gaikovoi  https://blog.gaikovoi.dev/2020/04/azure-application-gateway-http-headers.html
    $LoginRedirectToAADcondition = New-AzApplicationGatewayRewriteRuleCondition -Variable "http_resp_Location" -Pattern "(.*)(redirect_uri=https%3A%2F%2F).*\.azurewebsites\.net(.*)$" -IgnoreCase
    $LoginRedirectToAADresponseHeaderConfiguration = New-AzApplicationGatewayRewriteRuleHeaderConfiguration -HeaderName "Location" -HeaderValue "{http_resp_Location_1}{http_resp_Location_2}{var_host}{http_resp_Location_3}" 
    $LoginRedirectToAADactionSet = New-AzApplicationGatewayRewriteRuleActionSet -ResponseHeaderConfiguration $LoginRedirectToAADresponseHeaderConfiguration 
    $LoginRedirectToAADrewriteRule = New-AzApplicationGatewayRewriteRule -Name LoginRedirectToAAD -ActionSet $LoginRedirectToAADactionSet -Condition $LoginRedirectToAADcondition
  
    $CallbackFromAADcondition = New-AzApplicationGatewayRewriteRuleCondition -Variable "http_resp_Location" -Pattern "(https:\/\/).*\.azurewebsites\.net(.*)$" -IgnoreCase
    $CallbackFromAADresponseHeaderConfiguration = New-AzApplicationGatewayRewriteRuleHeaderConfiguration -HeaderName "Location" -HeaderValue "https://{var_host}{http_resp_Location_2}" 
    $CallbackFromAADactionSet = New-AzApplicationGatewayRewriteRuleActionSet -ResponseHeaderConfiguration $CallbackFromAADresponseHeaderConfiguration 
    $CallbackFromAADrewriteRule = New-AzApplicationGatewayRewriteRule -Name CallbackFromAAD -ActionSet $CallbackFromAADactionSet -Condition $CallbackFromAADcondition
#gaikovoi

# #MS :
#     $LoginRedirectToAADcondition = New-AzApplicationGatewayRewriteRuleCondition -Variable "http_resp_Location" -Pattern "(https?):\/\/.*azurewebsites\.net(.*)$" -IgnoreCase
#     $LoginRedirectToAADresponseHeaderConfiguration = New-AzApplicationGatewayRewriteRuleHeaderConfiguration -HeaderName "Location" -HeaderValue "{http_resp_Location_1}://myapp1-api-dev.dld23.com{http_resp_Location_2}" 
#     $LoginRedirectToAADactionSet = New-AzApplicationGatewayRewriteRuleActionSet -ResponseHeaderConfiguration $LoginRedirectToAADresponseHeaderConfiguration 
#     $LoginRedirectToAADrewriteRule = New-AzApplicationGatewayRewriteRule -Name MSrewrite-http-headers -ActionSet $LoginRedirectToAADactionSet -Condition $LoginRedirectToAADcondition
#  # + gaikovoi
#     $LoginRedirectToAADcondition = New-AzApplicationGatewayRewriteRuleCondition -Variable "http_resp_Location" -Pattern "(.*)(redirect_uri=https%3A%2F%2F).*\.azurewebsites\.net(.*)$" -IgnoreCase
#     $LoginRedirectToAADresponseHeaderConfiguration = New-AzApplicationGatewayRewriteRuleHeaderConfiguration -HeaderName "Location" -HeaderValue "{http_resp_Location_1}{http_resp_Location_2}{var_host}{http_resp_Location_3}" 
#     $LoginRedirectToAADactionSet = New-AzApplicationGatewayRewriteRuleActionSet -ResponseHeaderConfiguration $LoginRedirectToAADresponseHeaderConfiguration 
#     $LoginRedirectToAADrewriteRule2 = New-AzApplicationGatewayRewriteRule -Name LoginRedirectToAAD -ActionSet $LoginRedirectToAADactionSet -Condition $LoginRedirectToAADcondition
    
    
#     $CallbackFromAADcondition = New-AzApplicationGatewayRewriteRuleCondition -Variable "http_resp_Location" -Pattern "(https:\/\/).*\.azurewebsites\.net(.*)$" -IgnoreCase
#     $CallbackFromAADresponseHeaderConfiguration = New-AzApplicationGatewayRewriteRuleHeaderConfiguration -HeaderName "Location" -HeaderValue "https://{var_host}{http_resp_Location_2}" 
#     $CallbackFromAADactionSet = New-AzApplicationGatewayRewriteRuleActionSet -ResponseHeaderConfiguration $CallbackFromAADresponseHeaderConfiguration 
#     $CallbackFromAADrewriteRule = New-AzApplicationGatewayRewriteRule -Name CallbackFromAAD -ActionSet $CallbackFromAADactionSet -Condition $CallbackFromAADcondition
  
# #MS

    Add-AzApplicationGatewayRewriteRuleSet -ApplicationGateway $appgw -Name appservice-rwrst1 -RewriteRule $LoginRedirectToAADrewriteRule,$CallbackFromAADrewriteRule
    #Set-AzApplicationGatewayRewriteRuleSet -ApplicationGateway $appgw -Name appservice-rwrst1 -RewriteRule $LoginRedirectToAADrewriteRule,$CallbackFromAADrewriteRule,$LoginRedirectToAADrewriteRule2
    $RewriteRuleSet = Get-AzApplicationGatewayRewriteRuleSet -ApplicationGateway $appgw | Where-Object { $_.Name -eq "appservice-rwrst1" }
  }
  #region

  #region Backend Pool
  #Specify the Health Probe
  $ProbeConfig = Get-AzApplicationGatewayProbeConfig -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-hpb" }
  if (!$ProbeConfig) {
    Write-Host "Adding the Health Probe configuration"  -ForegroundColor Cyan
    $match = New-AzApplicationGatewayProbeHealthResponseMatch -StatusCode "200-399","401"
    Add-AzApplicationGatewayProbeConfig -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-hpb" -Protocol Https -Path $Rule.ProbePath -Interval 30 -Timeout 30 -UnhealthyThreshold 3 -Match $match -PickHostNameFromBackendHttpSettings
    $ProbeConfig = Get-AzApplicationGatewayProbeConfig -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-hpb" }
  }

  #Specify the Backend Address Pool
  $pool = Get-AzApplicationGatewayBackendAddressPool -ApplicationGateway $appgw | where-object { $_.Name -like "$($Rule.ApplicationName)-pool1" }
  if (!$pool) {
    Write-Host "Creating the Pool $($Rule.ApplicationName)-pool1"
    Add-AzApplicationGatewayBackendAddressPool -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-pool1" `
      -BackendFqdns $Rule.BackendFqdns
    $pool = Get-AzApplicationGatewayBackendAddressPool -ApplicationGateway $appgw | where-object { $_.Name -like "$($Rule.ApplicationName)-pool1" }
  }
  
  #Specify the Backend Http
  $poolSetting01 = Get-AzApplicationGatewayBackendHttpSetting -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-be-htst1" }
  if (!$poolSetting01) {
    Write-Host "Adding Backend setting $($Rule.ApplicationName)-be-htst1" -ForegroundColor Cyan
    Add-AzApplicationGatewayBackendHttpSetting -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-be-htst1" -Port 443 `
      -Protocol Https -CookieBasedAffinity Disabled -HostName $Rule.BackendFqdns -Probe $ProbeConfig
    $poolSetting01 = Get-AzApplicationGatewayBackendHttpSetting -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-be-htst1" }
  }

  #Specify the routing rule
  $rule01 = Get-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-rqrt-https" }
  if (!$rule01) {
    Write-Host "Adding Request Routing Rule $($Rule.ApplicationName)-rqrt-https" -ForegroundColor Cyan
    Add-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-rqrt-https" -RuleType basic `
      -BackendHttpSettings $poolSetting01 -HttpListener $listener01 -BackendAddressPool $pool -RewriteRuleSet $rewriteRuleSet
  }

  $rule02 = Get-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-rqrt-http" }
  if (!$rule02) {
    Write-Host "Adding Request Routing Rule $($Rule.ApplicationName)-rqrt-http" -ForegroundColor Cyan
    Add-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-rqrt-http" -RuleType basic `
      -HttpListener $listener02 -RedirectConfiguration $redirectConfig -RewriteRuleSet $rewriteRuleSet
  }

  #Pushing the configuration on the Application Gateway
  Write-Host "Updating the Application Gateway : $AppGwName" -ForegroundColor Cyan
  Set-AzApplicationGateway -ApplicationGateway $appgw
  #endregion

}