<#
.SYNOPSIS
  Inherit the resource group's tag to all it's sub resources.
.DESCRIPTION
  REQUIRED : Connected to an Azure subscription with the contributor role on the resource group
.PARAMETER action
   Mandatory
   Supported values : inherit_from_rg
.PARAMETER resource_group
   Mandatory
   Resource group name
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
.EXAMPLE
  1. Inherit all tags of the resource group "apps-jdld-sand1-rg1" to all it's sub resources
   .\Inherit-AzTag.ps1 -resource_group "rg-usabilla-dev"

  1. Inherit all tags from all resource groups to all their sub resources except for some Resource Group
  $rgs_toskip = @("databricks-managed-rg1")
  $rgs = get-azresourcegroup | Where-Object { $_.ResourceGroupName -notin $rgs_toskip }

  foreach ($rg in $rgs.ResourceGroupName)
  {
    write-host "$rg"
    .\Inherit-AzTag.ps1 -resource_group $rg
    write-host ""
  }
#>



param(
  [Parameter(Mandatory=$false,HelpMessage='Action')]
  [String]
  $action="inherit_from_rg",
  [Parameter(Mandatory=$true,HelpMessage='Resource Group')]
  [String]
  $resource_group
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
$count=0
$ResourceTypesToExclude = @("Microsoft.Insights/autoscaleSettings","Microsoft.Compute/virtualMachines/extensions","Microsoft.ClassicNetwork/virtualNetworks","Microsoft.ClassicStorage/storageAccounts")
#Local log file
$LogPath = $workfolder + "\logs"
if (!(Test-Path $LogPath)) { mkdir $LogPath }
$logFile = $LogPath + "\$date-" + $MyInvocation.MyCommand.Name + ".log"

#Action
switch($action){
  inherit_from_rg {
    Try{
      #List all Resources within the Resource Group
      $RGTags = (Get-AzResourceGroup -Name $resource_group).Tags
      $Resources = Get-AzResource -ResourceGroupName $resource_group -ErrorAction Stop | Where-Object { $_.ResourceType -notin $ResourceTypesToExclude }

      #For each Resource apply the Tag of the Resource Group
      Foreach ($resource in $Resources)
      {
        $resourceid = $resource.resourceId
        $resourcetags = $resource.Tags

        If ($resourcetags -eq $null)
        {
          Write-Output "---------------------------------------------"
          $Action = "NEW - Applying the following Tags to $($resourceid) : $([string[]]$($RGTags | out-string -stream))"
          $Command = {Set-AzResource -ResourceId $resourceid -Tag $RGTagS -Force -ErrorAction Stop}
          $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
          if($Result -eq "Error"){Exit 1}
          Write-Output "---------------------------------------------"

          $count++ 
        }
        Else
        {
          $TagUpdate=$false     
          Foreach ($RGTag in $RGTags.GetEnumerator())
          {       
            #Checking if Tags keys of the resource group are all in the resource's tag keys
            If ($resourcetags.Keys -inotcontains $RGTag.Key)
            {                        
              Write-Output "------------------------------------------------"
              Write-Output "Key = $($RGTag.Key) doesn't exist" 
              $resourcetags.Add($RGTag.Key,$RGTag.Value)
              $TagUpdate=$true
            }    
            Else
            {
                if ($resourcetags.Item($RGTag.Key) -ne $RGTag.Value)
                {
                  Write-Output "------------------------------------------------"
                  Write-Output "Key = $($RGTag.Key) doesn't have the RG Tag value = $($RGTag.Value), it's value is = $($resourcetags.Item($RGTag.Key))" 
                  $resourcetags.Remove($RGTag.Key)
                  $resourcetags.Add($RGTag.Key,$RGTag.Value)
                  $TagUpdate=$true
                }
            }
          }
          if($TagUpdate)
          {
            Write-Output "---------------------------------------------"            
            $Action = "UPDTATE - Applying the following Tags to $($resourceid) : $([string[]]$($RGTags | out-string -stream))"
            $Command = {Set-AzResource -ResourceId $resourceid -Tag $resourcetags -Force -ErrorAction Stop}
            $Result = Generate_Log_Action -Action $Action -Command $Command -LogFile $logFile
            if($Result -eq "Error"){Exit 1}
            Write-Output "---------------------------------------------"  
            $count++
          }
        }   
      }

      $body = "$count resources have been tagged"
      $status = "OK"
    }
    Catch {$body = $_.Exception.Message;$status = "Unauthorized"}
  }
  default {
    $status = "BadRequest"
    $body="Invalid action. Allowed values : inherit_from_rg."
  }
}
Write-Output "Status = $status"
Write-Output "$body"
