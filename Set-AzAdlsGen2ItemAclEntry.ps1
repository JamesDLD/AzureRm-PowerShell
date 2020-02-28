<#
.SYNOPSIS
  Set ADSL Gen 2 ACL by applying the Standard and Default ACL and all sub object and the Executive permission on the roots folders.
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
    https://docs.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-directory-file-acl-powershell
.EXAMPLE
    #Variable
    $SubscriptionName="Your Azure Subscription Name"
    $ResourceGroupName="The ADLS Gen 2resource group name"
    $AdlsGen2Name="The ADLS Gen 2 name"
    $FilesystemName="The ADLS Gen 2 name file system name"
    $Path="foler1/subfolder2/landing"
    $ObjectId="The Azure AD user, service principal or group Object ID"
    $AccessControlType="Specify 'Group' or 'User' respectively for an AD group or a User/ServicePrincipal"
    $Permission="rwx"
    $SetExecutePermissionRootDirectories = $True

    #Variable
   .\Set-AzAdlsGen2ItemAclEntry.ps1 -SubscriptionName $SubscriptionName -ResourceGroupName $ResourceGroupName -AdlsGen2Name $AdlsGen2Name -FilesystemName $FilesystemName -Path $Path -ObjectId $ObjectId -AccessControlType $AccessControlType -Permission $Permission -SetExecutePermissionRootDirectories $SetExecutePermissionRootDirectories 
#>

param(
    [Parameter(Mandatory=$True,HelpMessage='Azure Subscription Name')]
    [String]
    $SubscriptionName,
    [Parameter(Mandatory=$True,HelpMessage='Resource Group Name')]
    [String]
    $ResourceGroupName,
    [Parameter(Mandatory=$True,HelpMessage='Azure Data Lake Storage Gen 2 Name')]
    [String]
    $AdlsGen2Name,
    [Parameter(Mandatory=$True,HelpMessage='Azure Data Lake Storage Gen 2 Name')]
    [String]
    $FilesystemName,
    [Parameter(Mandatory=$True,HelpMessage='Azure Data Lake Storage Gen 2 Name')]
    [String]
    $Path,
    [Parameter(Mandatory=$True,HelpMessage='Azure AD user, service principal or group object Id.')]
    [String]
    $ObjectId,
    [Parameter(Mandatory=$True,HelpMessage='Access Control type, could be Group or User')]
    [String]
    $AccessControlType,
    [Parameter(Mandatory=$True,HelpMessage='ACL Permission')]
    [String]
    $Permission,
    [Parameter(Mandatory=$False,HelpMessage='Set Execute Permission to Root Directories')]
    [Bool]
    $SetExecutePermissionRootDirectories = $True,
    [Parameter(Mandatory=$False,HelpMessage='Log file path')]
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
#region variable
Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$workfolder = Split-Path $script:MyInvocation.MyCommand.Path
$date = Get-Date -UFormat "%d-%m-%Y"
$PowerShellModules = @(
            ("Az.Accounts","1.7.2"),
            ("Az.Storage","1.9.1")
        )
$root_paths=@('/')
if($Path -ne "/")
{
    for($i=0 ; $i -lt $($Path.Split("/").Count-1) ; $i++)
    {$root_paths+=$Path.Split("/")[0..$i] -join "/"}
}
        
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
#region connection
$Action = "Getting the Subscription $SubscriptionName"
$Command = {Get-AzSubscription -SubscriptionName $SubscriptionName -ErrorAction Stop}
$AzSubscription = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($AzSubscription -eq "Error"){Exit 1}

$Action = "Selecting the Subscription $SubscriptionName"
$Command = {Select-AzSubscription -SubscriptionId $AzSubscription.SubscriptionId -ErrorAction Stop}
$AzSubscription = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($AzSubscription -eq "Error"){Exit 1}

$Action = "Obtaining authorization by using the storage account key"
$Command = {Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $AdlsGen2Name -ErrorAction Stop}
$storageAccount = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($storageAccount -eq "Error"){Exit 1}
$Context = $storageAccount.Context

#endregion

#region Set Execute permission on root directory, this is required to traverse the child items of a directory
if($SetExecutePermissionRootDirectories -and $Path -ne "/")
{
  foreach($root_path in $root_paths)
  {
    $Action="Getting the path : $root_path"
    $Command = {Get-AzDataLakeGen2Item -Context $Context -FileSystem $FilesystemName -Path $root_path -ErrorAction Stop}
    $Parent = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
    if($Parent -eq "Error"){Exit 1}

    $acl=$Parent.ACL
    [Collections.Generic.List[System.Object]]$aclnew =$acl
    $ParentItemScope=$True

    # To avoid duplicate ACL, remove the ACL entries that will be added later.
    foreach ($a in $aclnew)
    {
        if ($a.AccessControlType -eq $AccessControlType -and $a.EntityId -eq $ObjectId -and "$($a.Permissions.ToSymbolicString())" -eq "--x" -and $a.DefaultScope -eq $False)
        {
            $ParentItemScope=$False
        }
    }

    if($ParentItemScope)
    {
        $Action="Adding Item Scope $AccessControlType scope ACL Permission : --x the child items under path : $($Parent.Path) for Object id : $ObjectId"
        $Command = {New-AzDataLakeGen2ItemAclObject -AccessControlType $AccessControlType -EntityId $ObjectId -Permission "--x" -InputObject $aclnew -ErrorAction Stop}
        $aclnew = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($aclnew -eq "Error"){Exit 1}   
        
        $Action="Updating ACL on server"
        $Command = {Update-AzDataLakeGen2Item -Context $Context -FileSystem $FilesystemName -Path $($Parent.Path) -Acl $aclnew -ErrorAction Stop}
        $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($Result -eq "Error"){Exit 1}    
    }
  }
}
#endregion

#region Set privilege and given path and sub objects
$Action="Getting the child items under path : $Path"
$Command = {Get-AzDataLakeGen2ChildItem -Context $Context -FileSystem $FilesystemName -Path $Path -Recurse -FetchPermission -ErrorAction Stop}
$Childs = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
if($Childs -eq "Error"){Exit 1}

$p=1
foreach ($Child in $Childs)
{
    Write-Progress -Activity "Privileges assignment in Progress" -Status "Progress:" -PercentComplete (($p / @($Childs).Count) *100);
    $p++

    # Create the new ACL object.
    $acl=$Child.ACL
    [Collections.Generic.List[System.Object]]$aclnew =$acl
    $DefaultScope=$ItemScope=$True
    $Cleaning=$False
    [Collections.Generic.List[System.Object]]$acltoclean = @()

    foreach ($a in $aclnew)
    {
        if ($a.AccessControlType -eq $AccessControlType -and $a.EntityId -eq $ObjectId)
        {
            if($a.DefaultScope -eq $True) 
            {
                if("$($a.Permissions.ToSymbolicString())" -eq $Permission)
                {
                    $DefaultScope=$False
                }
                # To avoid duplicate ACL with another Permission, record the ACL entry to delete.
                else {
                    $acltoclean.Add($a)
                    $Cleaning=$True
                }
            }
            elseif ($a.DefaultScope -eq $False)
            {
                if("$($a.Permissions.ToSymbolicString())" -eq $Permission)
                {
                    $ItemScope=$False
                }
                # To avoid duplicate ACL with another Permission, record the ACL entry to delete.
                else {
                    $acltoclean.Add($a)
                    $Cleaning=$True
                }
            }
        }
        # To avoid ACL with wrong AccessControlType, record the ACL entry to delete.
        elseif ($a.AccessControlType -ne $AccessControlType -and $a.EntityId -eq $ObjectId) {
            $acltoclean.Add($a)
            $Cleaning=$True
        }
    }
 
    # To avoid duplicate ACL with wrong AccessControlType, remove the ACL entries.
    foreach ($a in $acltoclean)
    {
        $aclnew.Remove($a)
    }

    if($DefaultScope -and $Child.IsDirectory)
    {
        $Action="Adding Default Scope $AccessControlType scope ACL Permission : $Permission the child items under path : $($Child.Path) for Object id : $ObjectId"
        $Command = {New-AzDataLakeGen2ItemAclObject -AccessControlType $AccessControlType -EntityId $ObjectId -Permission $Permission -DefaultScope -InputObject $aclnew -ErrorAction Stop}
        $aclnew = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($aclnew -eq "Error"){Exit 1}
    }

    if($ItemScope)
    {
        $Action="Adding Item Scope $AccessControlType scope ACL Permission : $Permission the child items under path : $($Child.Path) for Object id : $ObjectId"
        $Command = {New-AzDataLakeGen2ItemAclObject -AccessControlType $AccessControlType -EntityId $ObjectId -Permission $Permission -InputObject $aclnew -ErrorAction Stop}
        $aclnew = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($aclnew -eq "Error"){Exit 1}     
    }

    if($($DefaultScope -and $Child.IsDirectory) -or $ItemScope -or $Cleaning)
    {
        $Action="Updating ACL on server for path : $($Child.Path)"
        $Command = {Update-AzDataLakeGen2Item -Context $Context -FileSystem $FilesystemName -Path $($Child.Path) -Acl $aclnew -ErrorAction Stop}
        $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
        if($Result -eq "Error"){Exit 1}    
    }
}
#endregion