$TenantID = "<TenantID>"
$header = @{
    "Content-Type" = "application/x-www-form-urlencoded"
}

#V1
$EndpointAutorize = "https://login.microsoftonline.com/$TenantID/oauth2/authorize"
$EndpointToken = "https://login.microsoftonline.com/$TenantID/oauth2/token"
#V2
$EndpointToken = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token"
$EndpointAutorize = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/authorize"

## Client Credential
$Body = @{
    "grant_type"    = "client_credentials"
    "client_id"     = "<ClientID>"
    "client_secret" = "<Secret>"
    "scope"         = "https://graph.microsoft.com/.default"
}
$tokenResponse = Invoke-RestMethod -Method Post -Headers $header -Uri $EndpointToken -Body $Body
$tokenResponse.access_token

#ImplicitFlow
$QueryParm = "?client_id=<ClientID>&&response_type=id_token token&redirect_uri=https://localhost:3030&scope=openid User.Read offline_access&response_mode=fragment&state=12345&nonce=678910&resource=https://graph.microsoft.com/&api-version=2019-08-01"
$QueryParm = "?client_id=<ClientID>&&response_type=id_token token&redirect_uri=https://localhost:3030&scope=openid+offline_access&response_mode=fragment&state=12345&nonce=678910"

#Code
$codeChallenge = "_d3jWpJ7JZ1lZ-TsA-bw4qdcpPmqUIzN7Ww_Ypy0Gn0"
$codeVerify = "Kf_bt1AOZZBAXXF7HDsPXqFKaLePA-lltZothtIR1qEs"
$QueryParm = "?client_id=<ClientID>&&response_type=code&redirect_uri=https://localhost:3030&scope=openid User.Read offline_access&response_mode=query&state=12345&nonce=678910&code_challenge=$codeChallenge&code_challenge_method=S256"
$EndpointAutorize + $QueryParm


$Body = @{
    "grant_type" = "authorization_code"
    "code"="<CODE>"
    "redirect_uri"="https://localhost:3030"
    "client_id" = "<ClientID>"
    "client_secret" = "<Secret>"
    "scope" = "openid offline_access https://graph.microsoft.com/User.Read"
    "code_verifier" = $codeVerify
    "code_challenge_method" = "S256"
}


$Body = @{
    "client_id" = "<ClientID>"
    "scope" = "openid offline_access https://graph.microsoft.com/User.Read"
    "refresh_token"=$token.refresh_token
    "grant_type" = "refresh_token"
    "client_secret" = "<Secret>"
}
$Rtoken = Invoke-RestMethod -Method Post -Uri $EndpointToken -Body $Body -Headers $header

$Rtoken.access_token

Import-Module ADAL.PS
Import-Module MSAL.PS
(Get-Module -Name ADAL.PS).Path
(Get-Module -Name MSAL.PS).Path