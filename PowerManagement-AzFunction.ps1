<#
.SYNOPSIS
  Get, Start or Stop Azure resources like Application Gateways or VM through an Azure function configured with an Http trigger.
.DESCRIPTION
  REQUIRED : Azure function with an Http trigger
  REQUIRED : The Azure function is configured with a sytem identity and has power management privilege on the resources you will manage the power status.
.PARAMETER action
   Mandatory
   Supported values : get, start or stop
.PARAMETER type
   Mandatory
   Supported values : virtualMachines or applicationGateways
.PARAMETER name
   Mandatory
   Name of the resource you want to get, start or stop
.PARAMETER resource_group
   Mandatory
   Resource group name of the resource you want to get, start or stop
.NOTES
   AUTHOR: James Dumont le Douarec
   HttpStatusCode Enum: https://docs.microsoft.com/en-us/dotnet/api/system.net.httpstatuscode?view=netframework-4.8
.LINK
    https://github.com/JamesDLD/AzureRm-PowerShell
    https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-first-function-powershell
.EXAMPLE
  1. Get the status of the vm "iis1" located in the resource group "apps-jdld-sand1-rg1"
   curl --header "Content-Type: application/json" --request POST --data '{"action":"get","type":"virtualMachines","name":"iis1","resource_group":"apps-jdld-sand1-rg1"}' https://pws-powermgnt-apps2.azurewebsites.net/api/powermgnt?code=<API Token>

  2. Stop the Application Gateway "appgateway1" located in the resource group "infr-jdld-noprd-rg1"
   curl --header "Content-Type: application/json" --request POST --data '{"action":"stop","type":"applicationGateways","name":"appgateway1","resource_group":"infr-jdld-noprd-rg1"}' https://pws-powermgnt-apps2.azurewebsites.net/api/powermgnt?code=<API Token>
#>

using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$body = $Request.Body
$action = $body.action
$type = $body.type
$name = $body.name
$resource_group = $body.resource_group

# Ensure that the system identity is enable.
if ($env:MSI_SECRET -and (Get-Module -ListAvailable Az.Accounts)) {

    Try{
      Write-Output "Connecting to Azure using the Azure function MSI."
      $body = Connect-AzAccount -Identity -ErrorAction Stop
      $status = [HttpStatusCode]::OK
    }
    Catch {$body = $_.Exception.Message;$status = [HttpStatusCode]::Unauthorized}

    if ($action -and $type -and $name -and $resource_group) {
        
        switch($type){
          virtualMachines {
            switch($action){
              get {
                Try{
                  $body = Get-AzVm -ResourceGroupName $resource_group -Name $name -status -ErrorAction Stop
                  $status = [HttpStatusCode]::OK
                }
                Catch {$body = $_.Exception.Message;$status = [HttpStatusCode]::Unauthorized}
              }
              start {
                Try{
                  $body = Start-AzVm -ResourceGroupName $resource_group -Name $name -NoWait -ErrorAction Stop
                  $status = [HttpStatusCode]::OK
                }
                Catch {$body = $_.Exception.Message;$status = [HttpStatusCode]::Unauthorized}
              }
              stop {
                Try{
                  $body = Stop-AzVm -ResourceGroupName $resource_group -Name $name -NoWait -Force -ErrorAction Stop
                  $status = [HttpStatusCode]::OK
                }
                Catch {$body = $_.Exception.Message;$status = [HttpStatusCode]::Unauthorized}
              }
              default {
                $status = [HttpStatusCode]::BadRequest
                $body="Invalid action. Allowed values : get, start, stop ..."
              }
            }
          }
          applicationGateways {
            switch($action){
              get {
                Try{
                  $body = Get-AzApplicationGateway -ResourceGroupName $resource_group -Name $name -ErrorAction Stop
                  $status = [HttpStatusCode]::OK
                }
                Catch {$body = $_.Exception.Message;$status = [HttpStatusCode]::Unauthorized}
              }
              start {
                Try{
                  $AppGw = Get-AzApplicationGateway -ResourceGroupName $resource_group -Name $name -ErrorAction Stop
                  $body = Start-AzApplicationGateway -ApplicationGateway $AppGw -ErrorAction Stop
                  $status = [HttpStatusCode]::OK
                }
                Catch {$body = $_.Exception.Message;$status = [HttpStatusCode]::Unauthorized}
              }
              stop {
                Try{
                  $AppGw = Get-AzApplicationGateway -ResourceGroupName $resource_group -Name $name -ErrorAction Stop
                  $body = Stop-AzApplicationGateway -ApplicationGateway $AppGw -ErrorAction Stop
                  $status = [HttpStatusCode]::OK
                }
                Catch {$body = $_.Exception.Message;$status = [HttpStatusCode]::Unauthorized}
              }
              default {
                $status = [HttpStatusCode]::BadRequest
                $body="Invalid action. Allowed values : get, start, stop ..."
              }
            }
          }
          default {
            $status = [HttpStatusCode]::BadRequest
            $body="Invalid type. Allowed values : virtualMachines, applicationGateways."
          }
        }

    }
    else {
        $status = [HttpStatusCode]::BadRequest
        $body = "Please pass the following parameters : action, type, name, resource_group."
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
