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

