Folder's golden rule
------------
-	Store secrets
-	File containing password are ignored by any git pushing


Secret file
------------
-	Content sample of a json secret file used by a script, for example "Connect-Az.ps1" and "Create-AzContainer.ps1".
```
{
    "tenant_id":"xxxxx",
    "subscription_id":"xxxxx",
    "client_id":"xxxxx",
    "client_secret":"xxxxx"
}
```
