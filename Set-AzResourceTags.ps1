 <#
.SYNOPSIS
  Set tag keys and values on Resources based upon a list provided from a csv file (use ',' as delimiter).
.DESCRIPTION
  REQUIRED : Internet access & Already connected to an Azure tenant
  REQUIRED : PowerShell modules, see variables
  REQUIRED : Contributor privileges on the resource you want to tag
.PARAMETER CsvFilePath
   Mandatory
   Columns : Subscription Name,Resource Group Name,Resource Name,Resource Location,Resource Type,tagkey1,tagkey2,tagkey3,tagkey4,tagkey....
.PARAMETER LogFile
   Optional
   Log file path
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
.EXAMPLE
   ./Set-AzResourceTags.ps1 -CsvFilePath "./ResourcesToTag.csv"
#>

param(
    [Parameter(Mandatory = $true, HelpMessage = 'Csv file path')]
    [String]
    $CsvFilePath,
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
$Warnings=@()
#Module Name, Minimum Version
$PowerShellModules = @(
    ("Az.Accounts", "1.7.5"),
    ("Az.Resources", "1.13.0")
)

#If not provided, creating the log file
if ($LogFile -eq "") {
    $LogPath = $workfolder + "\logs"
    if (!(Test-Path $LogPath)) { mkdir $LogPath }
    $logFile = $LogPath + "\$date-" + $MyInvocation.MyCommand.Name + ".log"
}

ForEach ($PowerShellModule in $PowerShellModules) {
    $Action = "Importing the Module $($PowerShellModule[0]) with MinimumVersion $($PowerShellModule[1])"
    $Command = { Import-Module $PowerShellModule[0] -MinimumVersion $($PowerShellModule[1]) -ErrorAction Stop }
    $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if ($Result -eq "Error") { Exit 1 }
}

#endregion

$Action = "Importing the csv file $CsvFilePath"
$Command = { Import-Csv $CsvFilePath -ErrorAction Stop }
$CsvRgs = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if ($CsvRgs -eq "Error") { Exit 1 }


################################################################################
#                                 Action
################################################################################

foreach($CsvRg in $CsvRgs)
{
    #Variables
    $SubscriptionName = $CsvRg.'Subscription Name'
    $RgName = $CsvRg.'Resource Group Name'
    $ResourceName = $CsvRg.'Resource Name'
    $ResourceType = $CsvRg.'Resource Type'
    $TargetTagsFromCsv = $CsvRg | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne 'Subscription Name' -and $_.Name -ne 'Resource Name' -and $_.Name -ne 'Resource Group Name' -and $_.Name -ne 'Resource Location' -and $_.Name -ne 'Resource Type'}

    $TargetTags = New-Object System.Collections.Hashtable
    foreach($TargetTagFromCsv in $TargetTagsFromCsv)
    {
        $TagKey=$TargetTagFromCsv.Name
        if($CsvRg.$($TargetTagFromCsv.Name))
        {
            $TagValue=$CsvRg.$($TargetTagFromCsv.Name)
        }else{
            $TagValue="to_be_determined"
        }
        $TargetTags.Add($TagKey,$TagValue) | Out-Null
    }

    Write-Progress -Activity "Parsing subscription : $SubscriptionName, checking tags on Resource Group : $RgName" -Status "Progress:" -PercentComplete (($p / @($CsvRgs).Count) *100);
    $p++

    #Authentication
    $AzContext = Get-AzContext
    if($null -eq $AzContext)
    {
        $Action = "Signing in with Azure PowerShell"
        $Command = { Connect-AzAccount -ErrorAction Stop }
        $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if ($Result -eq "Error") { Exit 1 }
        $AzContext = Get-AzContext
    }
    
    if($AzContext.Subscription.Name -ne $SubscriptionName)
    {
        $Action = "Setting the Azure context for the subscription $SubscriptionName"
        $Command = {Get-AzSubscription -SubscriptionName $SubscriptionName | Set-AzContext -ErrorAction Stop}
        $AzureRmContext = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($AzureRmContext -eq "Error"){Exit 1}
        
        $Action = "Selecting the Azure the subscription $SubscriptionName"
        $Command = {Select-AzSubscription -Name $SubscriptionName -Context $AzureRmContext -Force -ErrorAction Stop}
        $AzSubscription = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($AzSubscription -eq "Error"){Exit 1}
    }

    $Action = "Getting the Resource $ResourceName within the Resource Group : $RgName"
    Write-Host "Info : $Action  ... " -ForegroundColor Cyan
    ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S]  : ") + "Info" + " : " + $Action) | Out-File -FilePath $LogFile -Append -Force
    try{
        $Resource = Get-AzResource -ResourceGroupName $RgName -Name $ResourceName -ResourceType $ResourceType -ErrorAction Stop
        $resourcetags=$Resource.Tags
        if($resourcetags)
        {
            $Action = "Merging current tags with wished tags on $ResourceName within the Resource Group : $RgName"
            $Command = {Update-AzTag -ResourceId $Resource.ResourceId -Tag $TargetTags -Operation Merge -ErrorAction Stop}
            $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
            if($Result -eq "Error"){Exit 1}
        }else{
            $Action = "Adding new wished tags on $ResourceName within the Resource Group : $RgName"
            $Command = {New-AzTag -ResourceId $Resource.ResourceId -Tag $TargetTags -ErrorAction Stop}
            $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
            if($Result -eq "Error"){Exit 1}
        }
    }
    catch{
        $WarningMessage="Not updating the Resource : $RgName in Resource Group : $RgName in subscription : $SubscriptionName because of the error message : $($_.Exception.Message)"
        $Warnings+=$WarningMessage
        ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S]  : ") + "Warning" + " : " + $WarningMessage) | Out-File -FilePath $LogFile -Append -Force
    }
}

if($Warnings)
{
    Write-Host "Warning" -ForegroundColor Yellow
    $Warnings
}