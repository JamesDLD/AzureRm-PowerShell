<#
.SYNOPSIS
  Audit Azure Ad Application and extract the result in a csv file.
  Outputs list of all Azure AD Apps along with their expiration date, display name, credentials (passwordcredentials or keycredentials), start date, key id. Useful to know the apps that are expiring and take action.
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
    https://blogs.msdn.microsoft.com/svarukala/2018/01/26/powershell-to-list-all-azure-ad-apps-with-expiration-dates/
    https://gist.github.com/svarukala/64ade1ca6f73a9d18236582e8770d1d4
.EXAMPLE
   .\Audit-AzAdApplication.ps1
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
$results = @()
$workfolder = Split-Path $script:MyInvocation.MyCommand.Path
$date = Get-Date -UFormat "%d-%m-%Y"
#Module Name, Minimum Version
$PowerShellModules = @(
             ("Az.Accounts","1.3.0"),
             ("Az.Resources","1.1.2")
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
$Action = "Getting all Azure Ad Application"
$Command = {Get-AzADApplication -ErrorAction Stop}
$AzADApplications = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($AzADApplications -eq "Error"){Exit 1}

foreach ($AzADApplication in $AzADApplications)
{
    #$owner = Get-AzADApplicationOwner -ObjectId $app.ObjectID -Top 1

    $Action = "Getting Azure Ad Credential of Application : $($AzADApplication.DisplayName) / Object id : $($AzADApplication.ObjectID)"
    $Command = {Get-AzADAppCredential -ObjectId $AzADApplication.ObjectID -ErrorAction Stop}
    $AzADAppCredential = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($AzADAppCredential -eq "Error"){Exit 1}

    $AzADAppCredential | 
    %{ 
        $results += [PSCustomObject] @{
                CredentialType = $_.Type;
                DisplayName = $AzADApplication.DisplayName; 
                ExpiryDate = $_.EndDate;
                StartDate = $_.StartDate;
                KeyID = $_.KeyId;
                #Owners = $owner.UserPrincipalName;
            }
        }                          
}

################################################################################
#                                 Output
################################################################################
$Action = "Exporting the Azure Ad Applications into the file : $($workfolder + "\logs" + "\$date-AzAdApplication.csv")"
$Command = {$results | export-csv $($workfolder + "\logs" + "\$date-AzAdApplication.csv") -notypeinformation -ErrorAction Stop}
$Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Result -eq "Error"){Exit 1}