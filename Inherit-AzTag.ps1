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
   .\Inherit-AzTag.ps1 -resource_group "apps-jdld-sand1-rg1"
#>

param(
  [Parameter(Mandatory=$false,HelpMessage='Action')]
  [String]
  $action="inherit_from_rg",
  [Parameter(Mandatory=$true,HelpMessage='Resource Group')]
  [String]
  $resource_group
)

#Variable
$count=0

#Action
switch($action){
  inherit_from_rg {
    Try{
      #List all Resources within the Resource Group
      $RGTags = (Get-AzResourceGroup -Name $resource_group).Tags
      $Resources = Get-AzResource -ResourceGroupName $resource_group -ErrorAction Stop

      #For each Resource apply the Tag of the Resource Group
      Foreach ($resource in $Resources)
      {
        $resourceid = $resource.resourceId
        $resourcetags = $resource.Tags

        If ($resourcetags -eq $null)
        {
          Write-Output "---------------------------------------------"
          Write-Output "NEW - Applying the following Tags to $($resourceid)" $RGTags
          Write-Output "---------------------------------------------"
          Set-AzResource -ResourceId $resourceid -Tag $RGTagS -Force
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
            Write-Output "UPDTATE - Applying the following Tags to $($resourceid)" $resourcetags
            Write-Output "---------------------------------------------"
            Set-AzResource -ResourceId $resourceid -Tag $resourcetags -Force
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
