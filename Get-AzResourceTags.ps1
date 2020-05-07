<#
.SYNOPSIS
  Get tag values from a list of tag keys for all Resources for each subscription you are able to connect to.
.DESCRIPTION
  REQUIRED : Internet access & Already connected to an Azure tenant
  REQUIRED : PowerShell modules, see variables
.PARAMETER TagKeys
   Mandatory
   Array of Tag Keys
.PARAMETER LogFile
   Optional
   Log file path
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
.EXAMPLE
   ./Get-AzResourceTags.ps1 -TagKeys @("env","project","project_owner","region")
#>

param(
    [Parameter(Mandatory = $false, HelpMessage = 'Tag keys to audit')]
    [Array]
    $TagKeys,
    [Parameter(Mandatory = $false, HelpMessage = 'Log file path')]
    [String]
    $LogFile
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
#endregion

################################################################################
#                                 Variable
################################################################################
Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$workfolder = Split-Path $script:MyInvocation.MyCommand.Path
$date = Get-Date -UFormat "%d-%m-%Y"
$p=1 #Pourcentage
#Module Name, Minimum Version
$PowerShellModules = @(
    ("Az.Accounts", "1.7.3"),
    ("Az.Resources", "1.12.0")
)

#If not provided, creating the log file
if ($LogFile -eq "") {
    $LogPath = $workfolder + "\logs"
    if (!(Test-Path $LogPath)) { mkdir $LogPath }
    $logFile = $LogPath + "\$date-" + $MyInvocation.MyCommand.Name + ".log"
}

#CSV file to export our results
$CsvPath = $workfolder + "\logs\$date-" + $MyInvocation.MyCommand.Name + ".csv"
"Subscription Name,Resource Group Name,Resource Name,Resource Location,Resource Type,$($TagKeys -join ",")" | Out-File -FilePath $CsvPath -Force

ForEach ($PowerShellModule in $PowerShellModules) {
    $Action = "Importing the Module $($PowerShellModule[0]) with MinimumVersion $($PowerShellModule[1])"
    $Command = { Import-Module $PowerShellModule[0] -MinimumVersion $($PowerShellModule[1]) -ErrorAction Stop }
    $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if ($Result -eq "Error") { Exit 1 }
}

#endregion

################################################################################
#                                 Action
################################################################################
#region Authentication
$Action = "Signing in with Azure PowerShell"
$Command = { Connect-AzAccount -ErrorAction Stop }
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if ($Result -eq "Error") { Exit 1 }

$Action = "Getting all Azure Subscriptions"
$Command = { Get-AzSubscription -ErrorAction Stop }
$Subscriptions = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if ($Subscriptions -eq "Error") { Exit 1 }
#endregion

#region Audit
foreach ($AzureRmSubscription in $Subscriptions) {
    Write-Progress -Activity "Auditing subscription $($AzureRmSubscription.Name)" -Status "Progress:" -PercentComplete (($p / @($Subscriptions).Count) *100);
    $p++

    $Action = "Setting the Azure context for the subscription $($AzureRmSubscription.Name)"
    $Command = {Get-AzSubscription -SubscriptionName $AzureRmSubscription.Name | Set-AzContext -ErrorAction Stop}
    $AzureRmContext = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($AzureRmContext -eq "Error"){Exit 1}
    
    $Action = "Selecting the Azure the subscription $($AzureRmSubscription.Name)"
    $Command = {Select-AzSubscription -Name $AzureRmSubscription.Name -Context $AzureRmContext -Force -ErrorAction Stop}
    $AzSubscription = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($AzSubscription -eq "Error"){Exit 1}

    $Action = "Getting all Resources of the Azure the subscription $($AzureRmSubscription.Name)"
    $Command = {Get-AzResource -ErrorAction Stop}
    $Resources = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($Resources -eq "Error"){Exit 1}

    foreach ($Resource in $Resources) {
        $resourcetags = $Resource.Tags
        If ($null -eq $resourcetags)
        {
            "$($AzureRmSubscription.Name),$($Resource.ResourceGroupName),$($Resource.ResourceName),$($Resource.Location),$($Resource.Type),$("," * $($TagKeys.length - 1))" | Out-File -FilePath $CsvPath -Append -Force   
        }
        else{
            $TagKeyValues= New-Object Collections.ArrayList
            foreach ($TagKey in $TagKeys)
            {
                    #Checking if Tags keys of the resource group are all in asked tag keys
                    If ($resourcetags.Keys -inotcontains $TagKey)
                    {                        
                        $TagKeyValues.Add("") | Out-Null
                    }    
                    else {
                        $TagKeyValues.Add($resourcetags.Item($TagKey)) | Out-Null
                    }
            }
            "$($AzureRmSubscription.Name),$($Resource.ResourceGroupName),$($Resource.ResourceName),$($Resource.Location),$($Resource.Type),$($TagKeyValues -join ",")" | Out-File -FilePath $CsvPath -Append -Force   
        }

    }                        
}
#endregion