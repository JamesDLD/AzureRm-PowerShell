[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true,Position=1)] [string] $StorageAccountName,
  [Parameter(Mandatory=$True,Position=2)] [string] $FilesystemName,
  [Parameter(Mandatory=$True,Position=3)] [string] $AccessKey,
  [Parameter(Mandatory=$True,Position=4)] [string] $Directory, # ex. "/", "/dir1/dir2"
  [Parameter(Mandatory=$False,Position=5)] [string] $MaxResults = "5000", # up to "5000"
  [Parameter(Mandatory=$False,Position=6)] [string] $Recursive = "false" # "true","false"
)

# Rest documentation:
# https://docs.microsoft.com/en-us/rest/api/storageservices/datalakestoragegen2/path/list

$date = [System.DateTime]::UtcNow.ToString("R")

$n = "`n"
$method = "GET"

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
                    "/$StorageAccountName/$FilesystemName" + $n + 
                    "directory:" + $Directory + $n +
                    "maxresults:" + $MaxResults + $n +
                    "recursive:$Recursive" + $n +
                    "resource:filesystem"# 
                    <# SECTION: CanonicalizedResource + "\n" #>

$sharedKey = [System.Convert]::FromBase64String($AccessKey)
$hasher = New-Object System.Security.Cryptography.HMACSHA256
$hasher.Key = $sharedKey

$signedSignature = [System.Convert]::ToBase64String($hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign)))


$authHeader = "SharedKey ${StorageAccountName}:$signedSignature"

$headers = @{"x-ms-date"=$date} 
$headers.Add("x-ms-version","2018-11-09")
$headers.Add("Authorization",$authHeader)

$Directory = [System.Web.HttpUtility]::UrlEncode($Directory)
$URI = "https://$StorageAccountName.dfs.core.windows.net/" + $FilesystemName + "?directory=$Directory&maxresults=$MaxResults&recursive=$Recursive&resource=filesystem"

$result = Invoke-RestMethod -method $method -Uri $URI -Headers $headers

$result