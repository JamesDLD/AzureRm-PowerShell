<#
.SYNOPSIS
  Get Azure Public Ip Address and extract the result in a csv file
.DESCRIPTION
  REQUIRED : Internet access & Already connected to an Azure tenant
  REQUIRED : PowerShell modules, see variables
.PARAMETER LogFile
   Optional
   Log file path
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
.EXAMPLE
   .\Audit-AzPublicIpAddress.ps1
#>

param(
  [Parameter(Mandatory=$false,HelpMessage='Log file path')]
  [String]
  $LogFile
)

################################################################################
#                                 Function
################################################################################
#region function
Function PipSummary_array{
[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $AzureSubscriptionName,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $Name,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $ResourceGroupName,
		[Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $Location,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $AssociatedObject
	)
	Process {
        $private:tableObj=New-Object PSObject

        $tableObj | Add-Member -Name AzureSubscriptionName -MemberType  NoteProperty -Value $AzureSubscriptionName
        $tableObj | Add-Member -Name Name -MemberType NoteProperty -Value $Name
        $tableObj | Add-Member -Name ResourceGroupName -MemberType NoteProperty -Value $ResourceGroupName
        $tableObj | Add-Member -Name Location -MemberType NoteProperty -Value $Location
        $tableObj | Add-Member -Name AssociatedObject -MemberType NoteProperty -Value $AssociatedObject

        return $tableObj
	}
} 
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
$AzureRmSubscriptions = Get-AzSubscription 
$PipSummary_array = @()
$workfolder = Split-Path $script:MyInvocation.MyCommand.Path
$date = Get-Date -UFormat "%d-%m-%Y"
#Module Name, Minimum Version
$PowerShellModules = @(
             ("Az.Accounts","1.3.0"),
             ("Az.Network","1.1.0")
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
foreach ($AzureRmSubscription in $AzureRmSubscriptions)
{
    $Action = "Getting the AzureRm context for the SubscriptionName : $($AzureRmSubscription.Name)"
    $Command = {Get-AzSubscription -SubscriptionName $AzureRmSubscription.Name | Set-AzContext -ErrorAction Stop}
    $AzureRmContext = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($AzureRmContext -eq "Error"){Exit 1}

    $Action = "Selecting the AzureRm SubscriptionName : $($AzureRmSubscription.Name)"
    $Command = {Select-AzSubscription -Name $AzureRmSubscription.Name -Context $AzureRmContext -Force -ErrorAction Stop}
    $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($Result -eq "Error"){Exit 1}

    $Action = "Getting the Public Ip Address from the SubscriptionName : $($AzureRmSubscription.Name)"
    $Command = {Get-AzPublicIpAddress -ErrorAction Stop}
    $Pips = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($Pips -eq "Error"){Exit 1}

    foreach ($Pip in $Pips)
    {
        $AssociatedObject=""
        if($Pip.IpConfiguration){$AssociatedObject=$Pip.IpConfiguration.Id.Split("/")[8]}
        else{$AssociatedObject=0}

        $PipSummary_array += PipSummary_array -AzureSubscriptionName $AzureRmSubscription.Name `
            -Name $Pip.Name `
            -ResourceGroupName $Pip.ResourceGroupName `
            -Location $Pip.Location `
            -AssociatedObject $AssociatedObject 
    }
}

################################################################################
#                                 Output
################################################################################
$Action = "Exporting the Pip summary audit result in to the file : $($workfolder + "\logs" + "\$date-PipSummary.csv")"
$Command = {$PipSummary_array | export-csv $($workfolder + "\logs" + "\$date-PipSummary.csv") -notypeinformation -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}