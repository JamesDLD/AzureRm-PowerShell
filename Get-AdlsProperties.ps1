[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true, Position = 1, HelpMessage = "The Azure Storage account name.")] [string] $StorageAccountName,
    [Parameter(Mandatory = $true, Position = 2, HelpMessage = "The filesystem identifier.")] [string] $FilesystemName,
    [Parameter(Mandatory = $true, Position = 3, HelpMessage = "ADLS Access Key.")] [string] $AccessKey,
    [Parameter(Mandatory = $true, Position = 4, HelpMessage = "The file or directory path.")] [string] $path
)
 
# Rest documentation:
# https://docs.microsoft.com/en-us/rest/api/storageservices/datalakestoragegen2/path/getproperties
# Call sample : ./Get-AdlsProperties.ps1 $sa_name $container_name $access_key "fr"
 
$date = [System.DateTime]::UtcNow.ToString("R")
 
$n = "`n"
$method = "HEAD"
 
# $stringToSign = "GET`n`n`n`n`n`n`n`n`n`n`n`n"
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
"x-ms-date:$date" + $n + 
"x-ms-version:2018-11-09" + $n # 
<# SECTION: CanonicalizedHeaders + "\n" #>
 
$stringToSign +=    
<# SECTION: CanonicalizedResource + "\n" #>
#HEAD https://{accountName}.{dnsSuffix}/{filesystem}/{path}?action={action}
"/$StorageAccountName/$FilesystemName/$path" + $n + 
"action:getAccessControl" + $n + 
"upn:true"
<# SECTION: CanonicalizedResource + "\n" #>
 
$sharedKey = [System.Convert]::FromBase64String($AccessKey)
$hasher = New-Object System.Security.Cryptography.HMACSHA256
$hasher.Key = $sharedKey
$signedSignature = [System.Convert]::ToBase64String($hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign)))
$authHeader = "SharedKey ${StorageAccountName}:$signedSignature"
 
$headers = @{"x-ms-date" = $date } 
$headers.Add("x-ms-version", "2018-11-09")
$headers.Add("Authorization", $authHeader)
 
$URI = "https://$StorageAccountName.dfs.core.windows.net/" + $FilesystemName + "/" + $path + "?action=getAccessControl&upn=true"
$result = Invoke-RestMethod -method "$method" -Uri $URI -Headers $headers
 
$result