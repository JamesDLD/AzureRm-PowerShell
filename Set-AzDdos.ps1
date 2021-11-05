<#
.SYNOPSIS
  Manage DDoS on Azure Virtual Networks
.DESCRIPTION
  REQUIRED : Internet access & Already connected to an Azure tenant
  REQUIRED : PowerShell modules, see variables
.PARAMETER logFile
   Optional
   Log file path
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    
.EXAMPLE
    #Define the existing target DDoS protection plan Id
    $DdosProtectionId = "/subscriptions/xxxxx/resourceGroups/xxxxx/providers/Microsoft.Network/ddosProtectionPlans/xxxxx""

    #Audit which Virtual Network are compliant, compliant means that where have the correct $DdosProtectionId
   ./Set-AzDdos.ps1 -Audit -DdosProtectionId $DdosProtectionId

   #Audit and Remediate which Virtual Network are compliant, compliant means that where have the correct $DdosProtectionId
   ./Set-AzDdos.ps1 -Audit -Remediate -DdosProtectionId $DdosProtectionId
#>

param(
    [Parameter(Mandatory = $false, HelpMessage = 'Log file path')]
    [string]$logFile = $null,
    [switch]$Audit,
    [switch]$Remediate,
    [Parameter(Mandatory = $true, HelpMessage = 'The DDoS protection plan plan like /subscriptions/xxxxx/resourceGroups/xxxxx/providers/Microsoft.Network/ddosProtectionPlans/xxxxx')]
    [string]$DdosProtectionId
)

################################################################################
#                                 Function
################################################################################
#region function
Function Generate_Log_Action([string]$Action, [ScriptBlock]$Command, [string]$LogFile) {
    $Output = "Info : $Action  ... "
    Write-Host $Output -ForegroundColor Cyan
    ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S]  : ") + "Info" + " : " + $Action) | Out-File -FilePath $LogFile -Append -Force
    Try {
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

Function virtualNetwork_array {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][String] $AzureSubscriptionName,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][String] $Name,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][String] $ResourceGroupName,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][String] $Tag_application,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][String] $DdosProtectionPlan
    )
    Process {
        $private:tableObj = New-Object PSObject
    
        $tableObj | Add-Member -Name AzureSubscriptionName -MemberType  NoteProperty -Value $AzureSubscriptionName
        $tableObj | Add-Member -Name Name -MemberType NoteProperty -Value $Name
        $tableObj | Add-Member -Name ResourceGroupName -MemberType NoteProperty -Value $ResourceGroupName
        $tableObj | Add-Member -Name Tag_application -MemberType NoteProperty -Value $Tag_application
        $tableObj | Add-Member -Name DdosProtectionPlan -MemberType NoteProperty -Value $DdosProtectionPlan
    
        return $tableObj
    }
} 
#endregion

################################################################################
#                                 Variable
################################################################################
Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$AzureRmSubscriptions = Get-AzSubscription
$virtualNetwork_array = @()
$workfolder = Split-Path $script:MyInvocation.MyCommand.Path
$date = Get-Date -UFormat "%d-%m-%Y"
#Module Name, Minimum Version
$PowerShellModules = @(
    @{ 
        Name           = "Az.Accounts"
        MinimumVersion = "2.5.2"
    },
    @{ 
        Name           = "Az.Network"
        MinimumVersion = "4.10.0"
    }
)

#If not provided, creating the log file
if ($logFile -eq "") {
    $LogPath = $workfolder + "/logs"
    Write-Host "$LogPath" -ForegroundColor Cyan
    if (!(Test-Path $LogPath)) { mkdir $LogPath }
    $logFile = $LogPath + "/$date-" + $MyInvocation.MyCommand.Name + ".log"
}

ForEach ($PowerShellModule in $PowerShellModules) {
    $Action = "Importing Module $($PowerShellModule.Name) with MinimumVersion $($PowerShellModule.MinimumVersion)"
    $Command = { Import-Module -Name $($PowerShellModule.Name) -MinimumVersion $($PowerShellModule.MinimumVersion) -ErrorAction Stop }
    $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if ($Result -eq "Error") { Exit 1 }
}
#endregion

################################################################################
#                                 Action
################################################################################
foreach ($AzureRmSubscription in $AzureRmSubscriptions) {
    $Action = "Getting the AzureRm context for the SubscriptionName : $($AzureRmSubscription.Name)"
    $Command = { Get-AzSubscription -SubscriptionName $AzureRmSubscription.Name | Set-AzContext -ErrorAction Stop }
    $AzureRmContext = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if ($AzureRmContext -eq "Error") { Exit 1 }

    $Action = "Selecting the AzureRm SubscriptionName : $($AzureRmSubscription.Name)"
    $Command = { Select-AzSubscription -Name $AzureRmSubscription.Name -Context $AzureRmContext -Force -ErrorAction Stop }
    $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if ($Result -eq "Error") { Exit 1 }

    $Action = "Getting the Virtual Networks from the SubscriptionName : $($AzureRmSubscription.Name)"
    $Command = { Get-AzVirtualNetwork -ErrorAction Stop } 
    $virtualNetworks = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if ($virtualNetworks -eq "Error") { Exit 1 }

    foreach ($virtualNetwork in $virtualNetworks) {

        $Compliant = if ($virtualNetwork.DdosProtectionPlan) { if ($virtualNetwork | Where-Object { $_.DdosProtectionPlan.Id -eq $DdosProtectionId }) { "Compliant" }else { "Not Compliant" } }else { "Not Compliant" }

        if ($Remediate -and $Compliant -eq "Not Compliant") {
            $virtualNetwork.DdosProtectionPlan = New-Object Microsoft.Azure.Commands.Network.Models.PSResourceId
            $virtualNetwork.DdosProtectionPlan.Id = $DdosProtectionId
            $virtualNetwork.EnableDdosProtection = $true
            $Action = "Associating on Virtual Network: $($virtualNetwork.Name) the DDoS plan id: $DdosProtectionId"
            $Command = { $virtualNetwork | Set-AzVirtualNetwork -ErrorAction Stop }
            $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
            if ($Result -eq "Error") { Exit 1 }
        }

        $virtualNetwork_array += virtualNetwork_array -AzureSubscriptionName $AzureRmSubscription.Name `
            -Name $virtualNetwork.Name `
            -ResourceGroupName $virtualNetwork.ResourceGroupName `
            -Tag_application $(if ($virtualNetwork.Tag.Item("application")) { $virtualNetwork.Tag.Item("application") }  else { "unknown tag key" }) `
            -DdosProtectionPlan $Compliant
    }
}

################################################################################
#                                 Output
################################################################################
if ($Audit) {
    $Action = "Exporting the Virtual Network summary audit result in to the file : $($workfolder + "\logs" + "\$date-Summary-$($MyInvocation.MyCommand.Name).csv")"
    $Command = { $virtualNetwork_array | export-csv $($workfolder + "\logs" + "\$date-Summary-$($MyInvocation.MyCommand.Name).csv") -notypeinformation -ErrorAction Stop }
    $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if ($Result -eq "Error") { Exit 1 }
}
