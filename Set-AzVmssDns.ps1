## Global variables
$AzureRmSubscriptionName = "mvp-sub1"
$RgName = "train-jdld-dev1-rg1"
$VMScaleSetName = "demo-vmss1"

## Connectivity
# Login first with Connect-AzAccount if not using Cloud Shell
$AzureRmContext = Get-AzSubscription -SubscriptionName $AzureRmSubscriptionName | Set-AzContext -ErrorAction Stop
Select-AzSubscription -Name $AzureRmSubscriptionName -Context $AzureRmContext -Force -ErrorAction Stop

# Get the current model of the scale set and store it in a local PowerShell object named $vmss
$Vmss = Get-AzVmss -ResourceGroupName $RgName -VMScaleSetName $VMScaleSetName

# Add DNS servers on the IP configuration
$Vmss.VirtualMachineProfile.NetworkProfile.networkInterfaceConfigurations.DnsSettings.DnsServers.Add("10.0.1.4")
$Vmss.VirtualMachineProfile.NetworkProfile.networkInterfaceConfigurations.DnsSettings.DnsServers.Add("10.0.1.5")

# Update the model of the scale set with the new configuration in the local PowerShell object
Update-AzVmss -ResourceGroupName $RgName -VMScaleSetName $VMScaleSetName -virtualMachineScaleSet $vmss

# Bring VMs up-to-date with the latest scale set model and Restart it
$AzVmssVMs = Get-AzVmssVM -ResourceGroupName $RgName -VMScaleSetName $VMScaleSetName
foreach ($AzVmssVM in $AzVmssVMs) {
    $reply = Read-Host -Prompt "This action will manually upgrade $($AzVmssVM.Name) to the latest model. While upgrading, the instance WILL be restarted. Do you want to upgrade $($AzVmssVM.Name)? Continue?[y/n]"
    if ( $reply -match "[yY]" ) { 
        Update-AzVmssInstance -ResourceGroupName $RgName -VMScaleSetName $VMScaleSetName -InstanceId $AzVmssVM.InstanceId

        Restart-AzVmss -ResourceGroupName $RgName -VMScaleSetName $VMScaleSetName -InstanceId $AzVmssVM.InstanceId
    }
}  