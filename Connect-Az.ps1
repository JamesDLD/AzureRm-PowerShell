<#
.SYNOPSIS
  Connect to an Azure AD tenant and one subscription using a service principal id and password located in a json file.
.DESCRIPTION
  REQUIRED : Internet access & Already connected to an Azure tenant
  REQUIRED : PowerShell Az modules
.PARAMETER LogFile
   Optional
   Log file path
.PARAMETER LogFile
   Optional
   Secret file path, default is "./secret/backend-main-jdld-1.json"
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
.EXAMPLE
  Authenticate a service principal
   .\Connect-Az.ps1
  Authenticate a user account
   .\Connect-Az.ps1 -AuthenticateThrough "Credential" -SecretFilePath "./secret/whp-dev-fr.json"
#>

param(
  [Parameter(Mandatory=$false,HelpMessage='Log file path')]
  [String]
  $LogFile,
  [Parameter(Mandatory=$false,HelpMessage='Secret file path')]
  [String]
  $SecretFilePath="./secret/backend-main-jdld-1.json",
  [Parameter(Mandatory=$false,HelpMessage='Authenticate through a user account (Credential) or a service principal (ServicePrincipal)')]
  [String]
  $AuthenticateThrough="ServicePrincipal"
)

################################################################################
#                                 Function
################################################################################
#region function
Function Generate_Log_Action([string]$Action, [ScriptBlock]$Command, [string]$LogFile){
	$Output = "Info : $Action  ... "
	Write-Host $Output -ForegroundColor Cyan
    ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S]  : ") + "Info" + " : " + $Action) | Out-File -FilePath $LogFile -Append -Force
	Try{
		$Result = Invoke-Command -ScriptBlock $Command 
	}
	Catch {
		$ErrorMessage = $_.Exception.Message
		$Output = "On action $Action : $ErrorMessage"
        ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S]  : ") + "Error" + " : " + $Output) | Out-File -FilePath $LogFile -Append -Force
		Write-Error $Output
		$Result = "Error"
	}
	Return $Result
}
#endregion

################################################################################
#                                 Variable
################################################################################
#region variable
Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$workfolder = Split-Path $script:MyInvocation.MyCommand.Path
$date = Get-Date -UFormat "%d-%m-%Y"

#If not provided, creating the log file
if($LogFile -eq "")
{
    $LogPath = $workfolder + "\logs"
    if(!(Test-Path $LogPath)){mkdir $LogPath}
    $logFile = $LogPath + "\$date-" + $MyInvocation.MyCommand.Name + ".log"
}
#endregion

################################################################################
#                                 Authentication
################################################################################
#region authentication
$Action = "Getting the json secret file : $SecretFilePath"
$Command = {Get-Content -Raw -Path $SecretFilePath | ConvertFrom-Json -AsHashtable -ErrorAction Stop}
$Login = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Login -eq "Error"){Exit 1}

$Action = "Generating the credential variable"
$SecureString = ConvertTo-SecureString -AsPlainText $($Login.client_secret) -Force
$Command = {New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $($Login.client_id), $SecureString -ErrorAction Stop}
$Credential = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Credential -eq "Error"){Exit 1}

$Action = "Connecting to the Azure AD Tenant using the json secret file : $SecretFilePath"
$Command = {
  switch($AuthenticateThrough){
    Credential {
      Connect-AzAccount -Credential $credential -TenantId $($Login.tenant_id) -ErrorAction Stop
    }
    default {
      Connect-AzAccount -ServicePrincipal -Credential $credential -TenantId $($Login.tenant_id) -ErrorAction Stop
    }
  }
}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}

$Action = "Getting the Azure subscription contained in the json secret file : $SecretFilePath"
$Command = {Get-AzSubscription -SubscriptionId $($Login.subscription_id) -ErrorAction Stop}
$AzureRmSubscription = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($AzureRmSubscription -eq "Error"){Exit 1}

$Action = "Setting the Azure context based on the subscription contained in the json secret file : $SecretFilePath"
$Command = {Get-AzSubscription -SubscriptionName $AzureRmSubscription.Name | Set-AzContext -ErrorAction Stop}
$AzureRmContext = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($AzureRmContext -eq "Error"){Exit 1}

$Action = "Selecting the Azure the subscription contained in the json secret file : $SecretFilePath"
$Command = {Select-AzSubscription -Name $AzureRmSubscription.Name -Context $AzureRmContext -Force -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}
#endregion
