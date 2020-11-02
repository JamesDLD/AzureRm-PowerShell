<#
.SYNOPSIS
Creating an Application Gateway with the following parameters
- Create a self signed certificate or re use an existing one if it exists in the Key Vault
- Create a Backend Pool that points to Backend FQDNs
- Create 2 frontend ports if they doesn't exist : feport-80 and feport-443

.DESCRIPTION
Prerequisites : 
- Application Gateway
- Key Vault
This article descibes how to create those resources through Terraform : https://medium.com/faun/build-an-azure-application-gateway-with-terraform-8264fbd5fa42/?WT.mc_id=DOP-MVP-5003548

.NOTES
   AUTHOR: James Dumont le Douarec

.EXAMPLE
./Publish-AzAppOnApg.ps1
#>

## Global variables
$AzureRmSubscriptionName = "mvp-sub1"
$RgName = "infr-hub-prd-rg1"
$AppGwName = "mvp-hub-agw1"
$KeyVaultName = "mvp-hub-kv1"

$Rules = @(
  @{
    ApplicationName = "myapp1apiprd" #only letters!
    CertificateName = "myapp1apiprddld23com"
    SubjectName     = "CN=myapp1-api-prd.dld23.com"
    Hostname       = "myapp1-api-prd.dld23.com"
    BackendFqdn    = "tf1-data-adls-gen2-prd.azurewebsites.net"
    ProbePath       = "/"
    ProbeProtocol   = "Https"
    ProbePort       =  443
    AuthenticationOnApp  = $True
  };
  @{
    ApplicationName = "myapp1apistg" #only letters!
    CertificateName = "myapp1apistgdld23com"
    SubjectName     = "CN=myapp1-api-stg.dld23.com"
    Hostname       = "myapp1-api-stg.dld23.com"
    BackendFqdn    = "stg-myapp1-apiapp1.azurewebsites.net"
    ProbePath       = "/"
    ProbeProtocol   = "Https"
    ProbePort       =  443
  };
  @{
    ApplicationName = "myapp1apidev" #only letters!
    CertificateName = "myapp1apidevdld23com"
    SubjectName     = "CN=myapp1-api-dev.dld23.com"
    Hostname       = "myapp1-api-dev.dld23.com"
    BackendFqdn    = "dev-myapp1-apiapp1.azurewebsites.net"
    ProbePath       = "/"
    ProbeProtocol   = "Https"
    ProbePort       =  443
    AuthenticationOnApp  = $True
  };
)

## Connectivity
# Login first with Connect-AzAccount if not using Cloud Shell
$AzureRmContext = Get-AzSubscription -SubscriptionName $AzureRmSubscriptionName | Set-AzContext -ErrorAction Stop
Select-AzSubscription -Name $AzureRmSubscriptionName -Context $AzureRmContext -Force -ErrorAction Stop | Out-Null

Foreach ($Rule in $Rules) {

  $AppGw = Get-AzApplicationGateway -Name $AppGwName -ResourceGroupName $RgName

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
    Write-Host "Creating the Certificat $($Rule.CertificateName)" -ForegroundColor Cyan
    Add-AzApplicationGatewaySslCertificate -ApplicationGateway $appgw -Name $($Rule.CertificateName) -KeyVaultSecretId $secretId | Out-Null
    $sslCert01 = Get-AzApplicationGatewaySslCertificate -ApplicationGateway $appgw | where-object { $_.Name -like "$($Rule.CertificateName)" }
  }
  #endregion

  #region Listener
  #region Application Gateway rule
  #Specify the Front End Port
  Write-Host "Creating pool and front-end ports" -ForegroundColor Cyan
  $fp01 = Get-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw | where-object { $_.Port -like "443" }
  if (!$fp01) {
    Write-Host "Creating the FrontendPort feport-443" -ForegroundColor Cyan
    Add-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw -Name "feport-443" -Port 443 | Out-Null
    $fp01 = Get-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw | where-object { $_.Port -like "443" }
  }

  $fp02 = Get-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw | where-object { $_.Port -like "80" }
  if (!$fp02) {
    Write-Host "Creating the FrontendPort $($Rule.ApplicationName)-feport-80" -ForegroundColor Cyan
    Add-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw -Name "feport-80" -Port 80 | Out-Null
    $fp02 = Get-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw | where-object { $_.Port -like "80" }
  }

  #Specify the HTTP listener
  Write-Host "Creating listeners, rules, and autoscale" -ForegroundColor Cyan
  $fipconfig01 = Get-AzApplicationGatewayFrontendIPConfig -ApplicationGateway $AppGw | Where-Object { $_.PublicIPAddress -ne $null }

  $listener01 = Get-AzApplicationGatewayHttpListener -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-ln-443" }
  if (!$listener01) {
    Write-Host "Creating the listener $($Rule.ApplicationName)-ln-443" -ForegroundColor Cyan
    Add-AzApplicationGatewayHttpListener -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-ln-443" -Protocol Https `
      -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp01 -SslCertificate $sslCert01 -Hostname $Rule.Hostname | Out-Null
    $listener01 = Get-AzApplicationGatewayHttpListener -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-ln-443" }
  }

  $listener02 = Get-AzApplicationGatewayHttpListener -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-ln-80" }
  if (!$listener02) {
    Write-Host "Creating the listener $($Rule.ApplicationName)-ln-80" -ForegroundColor Cyan
    Add-AzApplicationGatewayHttpListener -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-ln-80" -Protocol Http `
      -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp02 -Hostname $Rule.Hostname | Out-Null
    $listener02 = Get-AzApplicationGatewayHttpListener -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-ln-80" }
  }

  #Add the redirection configuration
  $redirectConfig = Get-AzApplicationGatewayRedirectConfiguration -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-rqrt-https" }
  if (!$redirectConfig) {
    Write-Host "Adding the redirection configuration" -ForegroundColor Cyan
    Add-AzApplicationGatewayRedirectConfiguration -ApplicationGateway $appgw `
      -Name "$($Rule.ApplicationName)-rqrt-https" `
      -RedirectType Permanent `
      -TargetListener $listener01 `
      -IncludePath $true `
      -IncludeQueryString $true | Out-Null
    $redirectConfig = Get-AzApplicationGatewayRedirectConfiguration -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-rqrt-https" }
  }
  #endregion

  #region HTTP header rewrite
  #Specify your HTTP header rewrite rule configuration
  $RewriteRuleSet = Get-AzApplicationGatewayRewriteRuleSet -ApplicationGateway $appgw | Where-Object { $_.Name -eq "appservice-rwrst1" }
  if (!$RewriteRuleSet) {
    Write-Host "Adding the HTTP header rewrite rule configuration appservice-rwrst" -ForegroundColor Cyan 

    $CallbackFromAppServicecondition = New-AzApplicationGatewayRewriteRuleCondition -Variable "http_resp_Location" -Pattern "(https?):\/\/.*azurewebsites\.net(.*)$" -IgnoreCase
    $CallbackFromAppServiceresponseHeaderConfiguration = New-AzApplicationGatewayRewriteRuleHeaderConfiguration -HeaderName "Location" -HeaderValue "{http_resp_Location_1}://{var_host}{http_resp_Location_2}" 
    $CallbackFromAppServiceactionSet = New-AzApplicationGatewayRewriteRuleActionSet -ResponseHeaderConfiguration $CallbackFromAppServiceresponseHeaderConfiguration 
    $CallbackFromAppServicerewriteRule = New-AzApplicationGatewayRewriteRule -Name CallbackFromAppService -ActionSet $CallbackFromAppServiceactionSet -Condition $CallbackFromAppServicecondition

    Add-AzApplicationGatewayRewriteRuleSet -ApplicationGateway $appgw -Name appservice-rwrst1 -RewriteRule $CallbackFromAppServicerewriteRule | Out-Null
    $RewriteRuleSet = Get-AzApplicationGatewayRewriteRuleSet -ApplicationGateway $appgw | Where-Object { $_.Name -eq "appservice-rwrst1" }
  }
  #region

  #region Backend Pool
  #Specify the Health Probe
  $ProbeConfig = Get-AzApplicationGatewayProbeConfig -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-hpb" }
  if (!$ProbeConfig) {
    Write-Host "Adding the Health Probe configuration" -ForegroundColor Cyan
    $match = New-AzApplicationGatewayProbeHealthResponseMatch -StatusCode "200-399","401"
    Add-AzApplicationGatewayProbeConfig -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-hpb" -Protocol $Rule.ProbeProtocol `
      -Path $Rule.ProbePath -Interval 30 -Timeout 30 -UnhealthyThreshold 3 -Match $match -HostName $Rule.BackendFqdn | Out-Null
    $ProbeConfig = Get-AzApplicationGatewayProbeConfig -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-hpb" }
  }

  #Specify the Backend Address Pool
  $pool = Get-AzApplicationGatewayBackendAddressPool -ApplicationGateway $appgw | where-object { $_.Name -like "$($Rule.ApplicationName)-pool1" }
  if (!$pool) {
    Write-Host "Creating the Pool $($Rule.ApplicationName)-pool1" -ForegroundColor Cyan
    Add-AzApplicationGatewayBackendAddressPool -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-pool1" `
      -BackendFqdns $Rule.BackendFqdn | Out-Null
    $pool = Get-AzApplicationGatewayBackendAddressPool -ApplicationGateway $appgw | where-object { $_.Name -like "$($Rule.ApplicationName)-pool1" }
  }
  
  #Specify the Backend Http
  $poolSetting01 = Get-AzApplicationGatewayBackendHttpSetting -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-be-htst1" }
  if (!$poolSetting01) {
    Write-Host "Adding Backend setting $($Rule.ApplicationName)-be-htst1" -ForegroundColor Cyan
    if($Rule.AuthenticationOnApp)
    {
      Write-host "$($Rule.ApplicationName) PickHostNameFromBackendAddress" -ForegroundColor Red
      Add-AzApplicationGatewayBackendHttpSetting -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-be-htst1" -Port $Rule.ProbePort `
      -Protocol $Rule.ProbeProtocol -CookieBasedAffinity Disabled -Probe $ProbeConfig | Out-Null
    }else{
      Write-host "$($Rule.ApplicationName) Nothing" -ForegroundColor Red
      Add-AzApplicationGatewayBackendHttpSetting -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-be-htst1" -Port $Rule.ProbePort `
      -Protocol $Rule.ProbeProtocol -CookieBasedAffinity Disabled -Probe $ProbeConfig -PickHostNameFromBackendAddress | Out-Null
    }
    $poolSetting01 = Get-AzApplicationGatewayBackendHttpSetting -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-be-htst1" }
  }

  #Specify the routing rule
  $rule01 = Get-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-rqrt-https" }
  if (!$rule01) {
    Write-Host "Adding Request Routing Rule $($Rule.ApplicationName)-rqrt-https" -ForegroundColor Cyan
    Add-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-rqrt-https" -RuleType basic `
    -BackendHttpSettings $poolSetting01 -HttpListener $listener01 -BackendAddressPool $pool -RewriteRuleSet $RewriteRuleSet | Out-Null
  }

  $rule02 = Get-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw | Where-Object { $_.Name -eq "$($Rule.ApplicationName)-rqrt-http" }
  if (!$rule02) {
    Write-Host "Adding Request Routing Rule $($Rule.ApplicationName)-rqrt-http" -ForegroundColor Cyan
    Add-AzApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw -Name "$($Rule.ApplicationName)-rqrt-http" -RuleType basic `
      -HttpListener $listener02 -RedirectConfiguration $redirectConfig -RewriteRuleSet $RewriteRuleSet | Out-Null
  }

  #Pushing the configuration on the Application Gateway
  Write-Host "Updating the Application Gateway : $AppGwName" -ForegroundColor Cyan
  Set-AzApplicationGateway -ApplicationGateway $appgw | Out-Null
  #endregion

}