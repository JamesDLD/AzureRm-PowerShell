<#
.SYNOPSIS
  Create a resource group, a storage account and a container.
  This script is useful to have a container ready to host blobs like Terraform tfstates.
.DESCRIPTION
  REQUIRED : Internet access
  REQUIRED : PowerShell modules, see variables
.PARAMETER LogFile
   Optional
   Log file path
.PARAMETER LogFile
   Mandatory
   Secret file path
.PARAMETER LogFile
   Mandatory
   Variable file path
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
    https://jamesdld.github.io/terraform/Best-Practice/BestPractice-1/
.EXAMPLE
    $SecretFile="./secret/vdc_int_1.json"
    $VariableFile="./variable/vdc_int_1.json"
   .\Create-AzContainer.ps1 -SecretFile $SecretFile -VariableFile $VariableFile
#>

param(
  [Parameter(Mandatory=$false,HelpMessage='Log file path')]
  [String]
  $LogFile,
  [Parameter(Mandatory=$true,HelpMessage='Secret file path')]
  [String]
  $SecretFile,
  [Parameter(Mandatory=$true,HelpMessage='Variable file path')]
  [String]
  $VariableFile
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
#                                 Prepare
################################################################################
#region prepare
Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$workfolder = Split-Path $script:MyInvocation.MyCommand.Path
$date = Get-Date -UFormat "%d-%m-%Y"

#Module Name, Minimum Version
$PowerShellModules = @(
             ("Az.Accounts","1.5.2"),
             ("Az.Resources","1.3.1"),
             ("Az.Storage","1.3.0")
        )

#If not provided, creating the log file
if($LogFile -eq "")
{
    $LogPath = $workfolder + "/log"
    if(!(Test-Path $LogPath)){mkdir $LogPath}
    $logFile = $LogPath + "/$date-" + $MyInvocation.MyCommand.Name + ".log"
}

ForEach ($PowerShellModule in $PowerShellModules)
{
    $Action = "Importing the Module $($PowerShellModule[0]) with MinimumVersion $($PowerShellModule[1])"
    $Command = {Import-Module $PowerShellModule[0] -MinimumVersion $($PowerShellModule[1]) -ErrorAction Stop}
    $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($Result -eq "Error"){Exit 1}
}

$Action = "Getting the json secret file : $SecretFile"
$Command = {Get-Content -Raw -Path $SecretFile | ConvertFrom-Json -AsHashtable -ErrorAction Stop}
$Login = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Login -eq "Error"){Exit 1}

$Action = "Getting the json variable file : $VariableFile"
$Command = {Get-Content -Raw -Path $VariableFile | ConvertFrom-Json -AsHashtable -ErrorAction Stop}
$Variable = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Variable -eq "Error"){Exit 1}

#Generating the credential variable
$SecureString = ConvertTo-SecureString -AsPlainText $($Login.client_secret) -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $($Login.client_id),$SecureString 
#endregion

################################################################################
#                                 Action
################################################################################
#region connection
$Action = "Connecting to the Azure AD Tenant using the json secret file : $SecretFile"
$Command = {Connect-AzAccount -ServicePrincipal -Credential $credential -TenantId $($Login.tenant_id) -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}

$Action = "Getting the Azure subscription contained in the json secret file : $SecretFile"
$Command = {Get-AzSubscription -SubscriptionId $($Login.subscription_id) -ErrorAction Stop}
$AzureRmSubscription = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($AzureRmSubscription -eq "Error"){Exit 1}

$Action = "Setting the Azure context based on the subscription contained in the json secret file : $SecretFile"
$Command = {Get-AzSubscription -SubscriptionName $AzureRmSubscription.Name | Set-AzContext -ErrorAction Stop}
$AzureRmContext = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($AzureRmContext -eq "Error"){Exit 1}

$Action = "Selecting the Azure the subscription contained in the json secret file : $SecretFile"
$Command = {Select-AzSubscription -Name $AzureRmSubscription.Name -Context $AzureRmContext -Force -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}
#endregion

#region azure resources
$Action = "Getting the Resource Group : $($Variable.resource_group_name)"
$Command = {Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -eq $Variable.resource_group_name} -ErrorAction Stop}
$Rg = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Rg -eq "Error"){Exit 1}

if(!$Rg) 
{
  $Action = "Creating the Resource Group : $($Variable.resource_group_name)"
  $Command = {New-AzResourceGroup -Name $Variable.resource_group_name -Location $Variable.location -Tag $Variable.tags -ErrorAction Stop}
  $Rg = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
  if($Rg -eq "Error"){Exit 1}
}

$Action = "Getting the Storage Account : $($Variable.storage_account_name)"
$Command = {Get-AzStorageAccount | Where-Object {$_.ResourceGroupName -eq $Variable.resource_group_name -and $_.StorageAccountName -eq $Variable.storage_account_name} -ErrorAction Stop}
$Sa = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Sa -eq "Error"){Exit 1}

if(!$Sa)
{
  $Action = "Creating the Storage Account : $($Variable.storage_account_name)"
  $Command = {New-AzStorageAccount -Name $Variable.storage_account_name -ResourceGroupName $Rg.ResourceGroupName -Location $Variable.location -SkuName $Variable.storage_account_sku_name -Tag $Variable.tags -ErrorAction Stop}
  $Sa = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
  if($Sa -eq "Error"){Exit 1}
}

$Action = "Getting the Storage Container : $($Variable.container_name)"
$Command = {Get-AzStoragecontainer -Context $Sa.Context | Where-Object {$_.Name -eq $Variable.container_name} -ErrorAction Stop}
$Container = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Container -eq "Error"){Exit 1}

if(!$Container)
{
  $Action = "Creating the Storage Container : $($Variable.container_name)"
  $Command = {New-AzStoragecontainer -Name $Variable.container_name -Context $Sa.Context -Permission blob -ErrorAction Stop}
  $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
  if($Result -eq "Error"){Exit 1}
}
#endregion