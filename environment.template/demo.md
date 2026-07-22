Get-VpnS2SInterface -Name "IBMCloud-VPN"


Disconnect-VpnS2SInterface -Name "IBMCloud-VPN"
Remove-VpnS2SInterface -Name "IBMCloud-VPN"
Get-VpnS2SInterface -Name "IBMCloud-VPN"

Add-VpnS2SInterface `
  -Name "IBMCloud-VPN" `
  -Destination "<>" `
  -Protocol IKEv2 `
  -AuthenticationMethod PSKOnly `
  -SharedSecret "<>" `
  -IPv4Subnet "<>","<>"
Connect-VpnS2SInterface -Name "IBMCloud-VPN"