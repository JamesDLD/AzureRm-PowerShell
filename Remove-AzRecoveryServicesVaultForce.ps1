<#
.SYNOPSIS
  Force the removal of a recovery services vault
.DESCRIPTION
  REQUIRED : Internet access & Already connected to an Azure tenant
  REQUIRED : PowerShell modules, see variables
.PARAMETER LogFile
   Optional
   Log file path
.PARAMETER SubscriptionName
   Mandatory
   Azure Subscription Name
.PARAMETER ResourceGroupName
   Mandatory
   Azure Resource Group Name containing the Recovery Services Vault
.PARAMETER VaultName
   Mandatory
   Azure Recovery Services Vault that you want to remove
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
    https://blogs.msdn.microsoft.com/mihansen/2017/11/04/deleting-an-azure-recovery-services-vault-with-all-backup-items/
.EXAMPLE
   .\Remove-AzRecoveryServicesVaultForce.ps1 -SubscriptionName $SubscriptionName -ResourceGroupName $MyRg -VaultName $MyRsv
#>

param(
  [Parameter(Mandatory=$false,HelpMessage='Log file path')]
  [String]$LogFile,

  [Parameter(Mandatory=$true)]
  [String]$SubscriptionName,

  [Parameter(Mandatory=$true)]
  [String]$ResourceGroupName,

  [Parameter(Mandatory=$true)]
  [String]$VaultName
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
Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$workfolder = Split-Path $script:MyInvocation.MyCommand.Path
$date = Get-Date -UFormat "%d-%m-%Y"
#Module Name, Minimum Version
$PowerShellModules = @(
             ("Az.Accounts","1.3.0"),
             ("Az.PolicyInsights","1.0.0")
        )

#If not provided, creating the log file
if($LogFile -eq "")
{
    $LogPath = $workfolder + "\logs"
    if(!(Test-Path $LogPath)){mkdir $LogPath}
    $logFile = $LogPath + "\$date-" + $MyInvocation.MyCommand.Name + ".log"
}

ForEach ($PowerShellModule in $PowerShellModules)
{
    $Action = "Importing the Module $($PowerShellModule[0]) with MinimumVersion $($PowerShellModule[1])"
    $Command = {Import-Module $PowerShellModule[0] -MinimumVersion $($PowerShellModule[1]) -ErrorAction Stop}
    $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($Result -eq "Error"){Exit 1}
}
#endregion

################################################################################
#                                 Action
################################################################################

$Action = "Getting the AzureRm context for the SubscriptionName : $($SubscriptionName)"
$Command = {Get-AzSubscription -SubscriptionName $SubscriptionName | Set-AzContext -ErrorAction Stop}
$AzureRmContext = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($AzureRmContext -eq "Error"){Exit 1}

$Action = "Selecting the AzureRm SubscriptionName : $($SubscriptionName)"
$Command = {Select-AzSubscription -Name $SubscriptionName -Context $AzureRmContext -Force -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}

$Action = "Getting the Recovery Services Vault : $VaultName in the resource group : $ResourceGroupName"
$Command = {Get-AzRecoveryServicesVault -Name $VaultName -ResourceGroupName $ResourceGroupName -ErrorAction Stop}
$RecoveryServicesVault = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($RecoveryServicesVault -eq "Error"){Exit 1}

$Action = "Setting the context with the Recovery Services Vault : $VaultName in the resource group : $ResourceGroupName"
$Command = {Set-AzRecoveryServicesVaultContext -Vault $RecoveryServicesVault -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}

$Action = "Getting the Services Backup Container of the Recovery Services Vault : $VaultName"
$Command = {Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -ErrorAction Stop}
$BackupContainers = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($BackupContainers -eq "Error"){Exit 1}

foreach($BackupContainer in $BackupContainers)
{
    $Action = "Getting the Services Backup Container item : $($BackupContainer.Name) of the Recovery Services Vault : $VaultName"
    $Command = {Get-AzRecoveryServicesBackupItem -Container $BackupContainer -WorkloadType AzureVM -ErrorAction Stop}
    $BackupItem = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($BackupItem -eq "Error"){Exit 1}

    $Action = "Disabling the Services Backup Container item : $($BackupContainer.Name) of the Recovery Services Vault : $VaultName"
    $Command = {Disable-AzRecoveryServicesBackupProtection -Item $BackupItem -RemoveRecoveryPoints -Force -ErrorAction Stop}
    $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($Result -eq "Error"){Exit 1}
}

$Action = "Removing the Recovery Services Vault : $VaultName"
$Command = {Remove-AzRecoveryServicesVault -Vault $RecoveryServicesVault -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}