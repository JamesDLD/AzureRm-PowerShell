<#
.SYNOPSIS
  Audit Azure Virtual Network and extract the result in a csv file
.DESCRIPTION
  REQUIRED : Internet access & Already connected to an Azure tenant
  REQUIRED : PowerShell modules
    ModuleType Version    Name
    ---------- -------    ----
    Script     0.6.1      Az.Network
    Script     0.6.1      Az.profile
.PARAMETER LogFile
   Optional
   Log file path
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
.EXAMPLE
   .\Audit-AzVirtualNetwork.ps1
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
Function VnetSummary_array{
[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $AzureSubscriptionName,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $VnetName,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $VnetResourceGroupName,
		[Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $AddressPrefixes,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $SubnetsCount,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $PeeringsCount,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $PeeringsLimit
	)
	Process {
        $private:tableObj=New-Object PSObject

        $tableObj | Add-Member -Name AzureSubscriptionName -MemberType  NoteProperty -Value $AzureSubscriptionName
        $tableObj | Add-Member -Name VnetName -MemberType NoteProperty -Value $VnetName
        $tableObj | Add-Member -Name VnetResourceGroupName -MemberType NoteProperty -Value $VnetResourceGroupName
        $tableObj | Add-Member -Name AddressPrefixes -MemberType NoteProperty -Value $AddressPrefixes
        $tableObj | Add-Member -Name SubnetsCount -MemberType NoteProperty -Value $SubnetsCount
        $tableObj | Add-Member -Name PeeringsCount -MemberType NoteProperty -Value $PeeringsCount
        $tableObj | Add-Member -Name PeeringsLimit -MemberType NoteProperty -Value $PeeringsLimit

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
$VnetSummary_array = @()
$workfolder = Split-Path $script:MyInvocation.MyCommand.Path
$date = Get-Date -UFormat "%d-%m-%Y"

#If not provided, creating the log file
if($LogFile -eq "")
{
    $LogPath = $workfolder + "\logs"
    if(!(Test-Path $LogPath)){mkdir $LogPath}
    $logFile = $LogPath + "\$date-" + $MyInvocation.MyCommand.Name + ".log"
}

$Action = "Importing the Module Az.Profile with MinimumVersion 0.6.1"
$Command = {Import-Module Az.Profile -MinimumVersion 0.6.1 -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}

$Action = "Importing the Module Az.Network with MinimumVersion 0.6.1"
$Command = {Import-Module Az.Network -MinimumVersion 0.6.1 -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}
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

    $Action = "Getting the vnet from the SubscriptionName : $($AzureRmSubscription.Name)"
    $Command = {Get-AzVirtualNetwork -ErrorAction Stop}
    $Vnets = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($Result -eq "Error"){Exit 1}

    foreach ($Vnet in $Vnets)
    {
        $Action = "Getting the vnet peering limit on the region : $($Vnet.Location) on the SubscriptionName : $($AzureRmSubscription.Name)"
        $Command = {Get-AzNetworkUsage -Location $Vnet.Location}
        $NetworkUsage = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($Result -eq "Error"){Exit 1}
           
        $PeeringsLimit = $($NetworkUsage | Where-Object {$_.ResourceType -like "Peerings per Virtual Network"}).Limit

        $VnetSummary_array += VnetSummary_array -AzureSubscriptionName $AzureRmSubscription.Name `
            -VnetName $Vnet.Name `
            -VnetResourceGroupName $Vnet.ResourceGroupName `
            -AddressPrefixes $Vnet.AddressSpace.AddressPrefixes `
            -SubnetsCount $Vnet.Subnets.Count `
            -PeeringsCount $Vnet.VirtualNetworkPeerings.Count `
            -PeeringsLimit $PeeringsLimit
    }
}

################################################################################
#                                 Output
################################################################################
$Action = "Exporting the Vnet summary audit result in to the file : $($workfolder + "\logs" + "\$date-VnetSummary.csv")"
$Command = {$VnetSummary_array | export-csv $($workfolder + "\logs" + "\$date-VnetSummary.csv") -notypeinformation -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}