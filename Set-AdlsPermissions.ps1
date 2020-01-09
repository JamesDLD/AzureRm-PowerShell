[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true,Position=1)] [string] $StorageAccountName,
  [Parameter(Mandatory=$True,Position=2)] [string] $AccessKey,
  [Parameter(Mandatory=$True,Position=3)] [string] $FilesystemName,
  [Parameter(Mandatory=$True,Position=4)] [string] $Path,
  [Parameter(Mandatory=$True,Position=5)] [string] $PermissionString
)

# Rest documentation:
# https://docs.microsoft.com/en-us/rest/api/storageservices/datalakestoragegen2/path/update
# http://sql.pawlikowski.pro/2019/03/10/connecting-to-azure-data-lake-storage-gen2-from-powershell-using-rest-api-a-step-by-step-guide/

$date = [System.DateTime]::UtcNow.ToString("R") # ex: Sun, 10 Mar 2019 11:50:10 GMT

$n = "`n"
$method = "PATCH"

$stringToSign = "$method$n" #VERB
$stringToSign += "$n" # Content-Encoding + "\n" +  
$stringToSign += "$n" # Content-Language + "\n" +  
$stringToSign += "$n" # Content-Length + "\n" +  
$stringToSign += "$n" # Content-MD5 + "\n" +  
$stringToSign += "$n" # Content-Type + "\n" +  
$stringToSign += "$n" # Date + "\n" +  
$stringToSign += "$n" # If-Modified-Since + "\n" +  
$stringToSign += "$n" # If-Match + "\n" +  
$stringToSign += "$n" # If-None-Match + "\n" +  
$stringToSign += "$n" # If-Unmodified-Since + "\n" +  
$stringToSign += "$n" # Range + "\n" + 
$stringToSign +=    
                    <# SECTION: CanonicalizedHeaders + "\n" #>
                    "x-ms-acl:$PermissionString" + $n +
                    "x-ms-date:$date" + $n + 
                    "x-ms-version:2018-11-09" + $n # 
                    <# SECTION: CanonicalizedHeaders + "\n" #>

$stringToSign +=    
                    <# SECTION: CanonicalizedResource + "\n" #>
                    "/$StorageAccountName/$FilesystemName/$Path" + $n + 
                    "action:setAccessControl"
                    <# SECTION: CanonicalizedResource + "\n" #>

$sharedKey = [System.Convert]::FromBase64String($AccessKey)
$hasher = New-Object System.Security.Cryptography.HMACSHA256
$hasher.Key = $sharedKey

$signedSignature = [System.Convert]::ToBase64String($hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign)))


$authHeader = "SharedKey ${StorageAccountName}:$signedSignature"

$headers = @{"x-ms-date"=$date} 
$headers.Add("x-ms-version","2018-11-09")
$headers.Add("Authorization",$authHeader)
$headers.Add("x-ms-acl",$PermissionString)

$URI = "https://$StorageAccountName.dfs.core.windows.net/" + $FilesystemName + "/" + $Path + "?action=setAccessControl"

Try {
  Invoke-RestMethod -method $method -Uri $URI -Headers $headers # returns empty response
  $true
}
catch {
  $ErrorMessage = $_.Exception.Message
  $StatusDescription = $_.Exception.Response.StatusDescription
  $false

  Throw $ErrorMessage + " " + $StatusDescription
}