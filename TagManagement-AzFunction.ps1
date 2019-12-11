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
Write-Output "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$body = $Request.Body
$action = $body.action
$resource_group = $body.resource_group
$count=0

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

                If ($null -eq $resourcetags)
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
