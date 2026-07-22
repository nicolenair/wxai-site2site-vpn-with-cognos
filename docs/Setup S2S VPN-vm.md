# Site-to-Site (S2S) VPN — IBM Cloud VPC ↔ Any Cloud/On-Prem VM

## Part 2 — Peer VM side (provider-agnostic)

Any OS capable of route-based IKEv2 with a PSK works. Examples:

### Windows Server (RRAS) — used in original validation
```powershell
Install-WindowsFeature -Name RemoteAccess -IncludeManagementTools
Install-WindowsFeature -Name Routing
Install-WindowsFeature -Name RSAT-RemoteAccess-PowerShell

Install-RemoteAccess -VpnType VpnS2S

Set-VpnServerConfiguration -CustomPolicy `
  -AuthenticationTransformConstants SHA256128 `
  -CipherTransformConstants AES256 `
  -DHGroup Group14 `
  -EncryptionMethod AES256 `
  -IntegrityCheckMethod SHA256 `
  -PfsGroup PFS2048 `
  -SALifeTimeSeconds 28800
Restart-Service RemoteAccess

Add-VpnS2SInterface `
  -Name "IBMCloud-VPN" `
  -Destination "<GW_IP_1 from 1.2>" `
  -Protocol IKEv2 `
  -AuthenticationMethod PSKOnly `
  -SharedSecret "<PSK>" `
  -IPv4Subnet "<SUBNET_CIDR>:10"

Connect-VpnS2SInterface -Name "IBMCloud-VPN"

Get-NetIPInterface | Where-Object {$_.InterfaceAlias -like "*IBMCloud*"} ## select ifindex

```

## 3. Test
```bash
$env:API_KEY="<ENTER YOUR IBM CLOUD API KEY>"

$TOKEN = (curl.exe -s -X POST "https://private.iam.cloud.ibm.com/identity/token" `
  -H "Content-Type: application/x-www-form-urlencoded" `
  -H "Accept: application/json" `
  --data-urlencode "grant_type=urn:ibm:params:oauth:grant-type:apikey" `
  --data-urlencode "apikey=$env:API_KEY" | ConvertFrom-Json).access_token
```
Then disconnect the tunnel and repeat — the same call should now time out,
confirming the private path genuinely depends on the tunnel.

## Common failure signatures
| Symptom | Cause |
|---|---|
| `Connection refused` from peer | Peer's OS firewall or security group blocking inbound UDP 500/4500 |
| Tunnel connects, but nothing reachable | Missing route for the CSE range (`166.8.0.0/14`), not just the VPC subnet |
| `cannot_authenticate_connection` / mismatched IKE ID | `--peer-ike-identity-value` doesn't match what the OS actually sends (usually its private IP, not hostname or public IP) |
| Works, then breaks after VM/gateway restart | Public IP or PSK changed on recreation — connection object needs updating with the new values |
