 <#
.SYNOPSIS
  Create AD groups from a csv containing two columns, the first one contains the group name, the second one contains the group's description.
.DESCRIPTION
  REQUIRED : PowerShell ActiveDirectory module
.PARAMETER LogFile
   Optional
   Log file path
.PARAMETER filepath
   Mandatory
   Csv file path containing two columns, the first one contain the group name, the second one contains the groups description.
.PARAMETER OU
   Optional
   Organisation Unit where to create the AD groups
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
.EXAMPLE
    Default usage =>
    $filepath="./logs/group.csv"
   .\Create-AdGroupFromCsv.ps1 -filepath $filepath

    Create AD groups in a specific Organisation Unit =>
    $OU="OU=Offices,DC=Contoso,DC=local"
    $filepath="./logs/group.csv"
   .\Create-AdGroupFromCsv.ps1 -filepath $filepath -OU $OU
#>

param(
    [Parameter(Mandatory=$false,HelpMessage='Log file path')]
    [String]
    $LogFile,

    [Parameter(Mandatory=$true,HelpMessage='Csv file path containing two columns, the first one contain the group name, the second one contains the groups description.')]
    [String]
    $filepath,

    [Parameter(Mandatory=$false,HelpMessage='Organisation Unit where to create the AD groups.')]
    [String]
    $OU
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
  
#Module Name
$PowerShellModules = @(
             ("ActiveDirectory")
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
    $Action = "Importing the Module $($PowerShellModule)"
    $Command = {Import-Module $PowerShellModule -ErrorAction Stop}
    $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($Result -eq "Error"){Exit 1}
}
#endregion

################################################################################
#                                 Action
################################################################################
#region create AD groups
$Action = "Importing the cvs file located here : $($filepath)"
$Command = {Import-CSV -Delimiter "|" $filepath -Header name,description -ErrorAction Stop}
$Groups = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Groups -eq "Error"){Exit 1}

ForEach ($Group in $Groups)
{
    if($OU)
    {
        $Action = "Creating the AD group : $($Group.name) in the Organisation Unit : $OU"
        $Command = {New-ADGroup –name $($Group.name) -GroupScope Global -Description $($Group.Description) –path $OU -ErrorAction Stop}
        $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($Result -eq "Error"){Exit 1}
    }else {
        $Action = "Creating the AD group : $($Group.name)"
        $Command = {New-ADGroup –name $($Group.name) -GroupScope Global -Description $($Group.Description) -ErrorAction Stop} 
        $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($Result -eq "Error"){Exit 1}
    }
}
#endregion
