<#
.SYNOPSIS
  Tag management through an Azure function configured with an Http trigger.
.DESCRIPTION
  REQUIRED : Azure function with an Http trigger
  REQUIRED : The Azure function is configured with a sytem identity and the privilege to manage the tags within your resource group.
.PARAMETER action
   Mandatory
   Supported values : inherit_from_rg
.PARAMETER resource_group
   Mandatory
   Resource group name of the resource you want to get, start or stop
.NOTES
   AUTHOR: James Dumont le Douarec
   HttpStatusCode Enum: https://docs.microsoft.com/en-us/dotnet/api/system.net.httpstatuscode?view=netframework-4.8
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
    https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-first-function-powershell
    https://github.com/sympa18/CheckandApplyTags
.EXAMPLE
  1. Inherit all tags of the resource group "apps-jdld-sand1-rg1" to all it's sub resources
   curl --header "Content-Type: application/json" --request POST --data '{"action":"inherit_from_rg","resource_group":"apps-jdld-sand1-rg1"}' https://demo-pwsh-azfun1.azurewebsites.net/api/tag?code=<API Token>
#>

using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$body = $Request.Body
$action = $body.action
$resource_group = $body.resource_group

# Ensure that the system identity is enable.
if ($env:MSI_SECRET -and (Get-Module -ListAvailable Az.Accounts)) {

    Try{
      Write-Output "Connecting to Azure using the Azure function MSI."
      $body = Connect-AzAccount -Identity -ErrorAction Stop
      $status = [HttpStatusCode]::OK
    }
    Catch {$body = $_.Exception.Message;$status = [HttpStatusCode]::Unauthorized}

    if ($action -and $resource_group) {
        
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

                If ($null -eq $nuresourcetagsll)
                {
                  Write-Output "---------------------------------------------"
                  Write-Output "Applying the following Tags to $($resourceid)" $RGTags
                  Write-Output "---------------------------------------------"
                  $Settag = Set-AzResource -ResourceId $resourceid -Tag $RGTagS -Force
                    
                }
                Else
                {
                  $RGTagFinal = @{}
                  $RGTagFinal = $RGTags                  
                  Foreach ($resourcetag in $resourcetags.GetEnumerator())
                  {          
                    If ($RGTags.Keys -inotcontains $resourcetag.Key)
                    {                        
                            Write-Output "------------------------------------------------"
                            Write-Output "Keydoesn't exist in RG Tags adding to Hash Table" $resourcetag
                            Write-Output "------------------------------------------------"
                            $RGTagFinal.Add($resourcetag.Key,$resourcetag.Value)
                    }    
                  }
                  Write-Output "---------------------------------------------"
                  Write-Output "Applying the following Tags to $($resourceid)" $RGTagFinal
                  Write-Output "---------------------------------------------"
                  $Settag = Set-AzResource -ResourceId $resourceid -Tag $RGTagFinal -Force
                }   
              }

              $body = $RGTags
              $status = [HttpStatusCode]::OK
            }
            Catch {$body = $_.Exception.Message;$status = [HttpStatusCode]::Unauthorized}
          }
          default {
            $status = [HttpStatusCode]::BadRequest
            $body="Invalid action. Allowed values : inherit_from_rg."
          }
        }
    }
    else {
        $status = [HttpStatusCode]::BadRequest
        $body = "Please pass the following parameters : action, resource_group."
    }
}
else {
    $status = [HttpStatusCode]::Unauthorized
    $body = "Please make that you have enabled the System assigned identity on your Azure function."
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $status
    Body = $body
})
