<#
.SYNOPSIS
  Audit Azure policies and extract the result in csv files
.DESCRIPTION
  REQUIRED : Internet access & Already connected to an Azure tenant
  REQUIRED : PowerShell modules
    ModuleType Version    Name
    ---------- -------    ----
    Script     1.0.2      AzureRM.PolicyInsights
    Script     5.3.3      AzureRM.Profile
.PARAMETER LogFile
   Optional
   Log file path
.PARAMETER PolicySuffixesToFilterOn
   Mandatory
   Array containing the policies names you want to filter on
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
    https://docs.microsoft.com/en-us/azure/azure-policy/policy-compliance
.EXAMPLE
   $PolicySuffixesToFilterOn = @("*enforce-udr-under-vnet*","*enforce-nsg-under-vnet*")
   .\Audit-AzureRmPolicies.ps1 -PolicySuffixesToFilterOn $PolicySuffixesToFilterOn
#>

param(
  [Parameter(Mandatory=$true,HelpMessage='Azure policies suffixes to filter on')]
  [Array]
  $PolicySuffixesToFilterOn,

  [Parameter(Mandatory=$false,HelpMessage='Log file path')]
  [String]
  $LogFile
)

################################################################################
#                                 Function
################################################################################
#region function
Function PolicyStateSummary_array{
[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $AzureSubscriptionName,
		[Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $PolicySuffix,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $NonCompliantResources,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $NonCompliantPolicies
	)
	Process {
        $private:tableObj=New-Object PSObject

        $tableObj | Add-Member -Name AzureSubscriptionName -MemberType  NoteProperty -Value $AzureSubscriptionName
        $tableObj | Add-Member -Name PolicySuffix -MemberType NoteProperty -Value $PolicySuffix
        $tableObj | Add-Member -Name NonCompliantResources -MemberType NoteProperty -Value $NonCompliantResources
        $tableObj | Add-Member -Name NonCompliantPolicies -MemberType NoteProperty -Value $NonCompliantPolicies

        return $tableObj
	}
}

Function PolicyState_array{
[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $AzureSubscriptionName,
		[Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $PolicySuffix,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $ResourceGroup,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][Bool] $IsCompliant,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][String] $Resource
	)
	Process {
        $private:tableObj=New-Object PSObject

        $tableObj | Add-Member -Name AzureSubscriptionName -MemberType  NoteProperty -Value $AzureSubscriptionName
        $tableObj | Add-Member -Name PolicySuffix -MemberType NoteProperty -Value $PolicySuffix
        $tableObj | Add-Member -Name ResourceGroup -MemberType NoteProperty -Value $ResourceGroup
        $tableObj | Add-Member -Name IsCompliant -MemberType NoteProperty -Value $IsCompliant
        $tableObj | Add-Member -Name Resource -MemberType NoteProperty -Value $Resource

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
$AzureRmSubscriptions = Get-AzureRmSubscription
$PolicyStateSummary_array = @()
$PolicyState_array = @()

################################################################################
#                                 Prerequisites
################################################################################
#region prerequisite
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

$Action = "Importing the Module AzureRM.Profile with MinimumVersion 5.3.3"
$Command = {Import-Module AzureRM.Profile -MinimumVersion 5.3.3 -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}

$Action = "Importing the Module AzureRM.PolicyInsights with MinimumVersion 1.0.2"
$Command = {Import-Module AzureRM.PolicyInsights -MinimumVersion 1.0.2 -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}
#endregion

################################################################################
#                                 Action
################################################################################
foreach ($AzureRmSubscription in $AzureRmSubscriptions)
{
    $Action = "Getting the AzureRm context for the SubscriptionName : $($AzureRmSubscription.Name)"
    $Command = {Get-AzureRmSubscription -SubscriptionName $AzureRmSubscription.Name | Set-AzureRmContext -ErrorAction Stop}
    $AzureRmContext = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($AzureRmContext -eq "Error"){Exit 1}

    $Action = "Selecting the AzureRm SubscriptionName : $($AzureRmSubscription.Name)"
    $Command = {Select-AzureRmSubscription -Name $AzureRmSubscription.Name -Context $AzureRmContext -Force -ErrorAction Stop}
    $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($Result -eq "Error"){Exit 1}
    foreach($PolicySuffix in $PolicySuffixesToFilterOn)
    {
        $AzureRmPolicyStateSummary = $AzureRmPolicyStates = @()

        $Action = "[$($AzureRmSubscription.Name)] Getting the policy state summary for policies having the suffix : $PolicySuffix"
        $Command = {Get-AzureRmPolicyStateSummary -ErrorAction Stop}
        $AzureRmPolicyStateSummary = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($AzureRmPolicyStateSummary -eq "Error"){Exit 1}
        elseif($AzureRmPolicyStateSummary.PolicyAssignments -ne "" -and $AzureRmPolicyStateSummary.Results -ne "")
        {
            $AzureRmPolicyStateSummary = $AzureRmPolicyStateSummary | Where-Object { $_.PolicyAssignments.PolicyAssignmentId -like $PolicySuffix }
            if($AzureRmPolicyStateSummary)
            {
                $PolicyStateSummary_array += PolicyStateSummary_array -AzureSubscriptionName $AzureRmSubscription.Name -PolicySuffix $PolicySuffix.Replace("*","") -NonCompliantResources $AzureRmPolicyStateSummary.Results.NonCompliantResources -NonCompliantPolicies $AzureRmPolicyStateSummary.Results.NonCompliantPolicies
            }
        }

        $Action = "[$($AzureRmSubscription.Name)] Getting the policy state for policies having the suffix : $PolicySuffix"
        $Command = {Get-AzureRmPolicyState -ErrorAction Stop}
        $AzureRmPolicyStates = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($AzureRmPolicyStates -eq "Error"){Exit 1}
        elseif($AzureRmPolicyStates)
        {
            $AzureRmPolicyStates = $AzureRmPolicyStates | Where-Object { $_.PolicyAssignmentId -like $PolicySuffix }
            foreach($AzureRmPolicyState in $AzureRmPolicyStates)
            {
                $PolicyState_array += PolicyState_array -AzureSubscriptionName $AzureRmSubscription.Name -PolicySuffix $PolicySuffix.Replace("*","") -ResourceGroup $AzureRmPolicyState.ResourceGroup -IsCompliant $AzureRmPolicyState.IsCompliant -Resource "$($AzureRmPolicyState.ResourceId.Split("/")[-2])/$($AzureRmPolicyState.ResourceId.Split("/")[-1])"
            }
        }
    }
}

################################################################################
#                                 Output
################################################################################
$Action = "Exporting the Policy State summary result in to the file : $($workfolder + "\logs" + "\$date-PolicyStateSummary.csv")"
$Command = {$PolicyStateSummary_array | export-csv $($workfolder + "\logs" + "\$date-PolicyStateSummary.csv") -notypeinformation -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}

$Action = "Exporting the Policy State details result in to the file : $($workfolder + "\logs" + "\$date-PolicyStateDetail.csv")"
$Command = {$PolicyState_array | export-csv $($workfolder + "\logs" + "\$date-PolicyStateDetail.csv") -notypeinformation -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}