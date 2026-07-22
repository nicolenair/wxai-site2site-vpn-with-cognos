# Site-to-Site (S2S) VPN — IBM Cloud VPC ↔ Any Cloud/On-Prem VM

Persistent, unattended tunnel for a server (e.g. Cognos) to reach IBM
Cloud's private network. Unlike Client VPN, needs no per-user login and no
Secrets Manager cert — auth is a shared PSK between two gateways.

Run `source env.sh` before starting.

## Prerequisite: the peer VM needs a genuine 1:1 public IP

This is provider-agnostic but non-negotiable: IPsec/NAT-T requires UDP 500
and UDP 4500 to arrive at the peer on those **exact** ports. A NAT/PAT
setup that remaps external ports (e.g. `31571 → 500`) breaks the protocol
entirely — no IBM-side configuration can work around it.

- **AWS**: EC2 instance with an Elastic IP directly attached (no ALB/NAT
  gateway in front of the IPsec ports).
- **Azure**: VM with a Public IP resource directly associated to the NIC.
- **IBM Cloud**: VSI with a **Floating IP** (`ibmcloud is floating-ip-reserve`).
- **On-prem**: a real routable public IP on the firewall/router terminating
  the tunnel, or the VM itself if it's directly exposed.

Confirm before proceeding: `ssh` (or any service) into the VM using its
public IP directly on the **unmapped** port — if your provider silently
remapped that port too, you have a NAT'd IP, not a 1:1 one, and S2S will
not work until that's fixed.

## Part 1 — IBM Cloud side

### Prereq
Login to ibm cloud cli & set target region & resource group

### 1.1 Network (skip if reusing an existing VPC/subnet)
```bash
ibmcloud is vpc-create $VPC_NAME
ibmcloud is subnet-create $SUBNET_NAME $VPC_NAME --zone ${IBM_REGION}-1 --ipv4-address-count 256
```

### 1.2 VPN gateway
```bash
ibmcloud is vpn-gateway-create $VPN_GATEWAY_NAME $SUBNET_NAME --mode route
ibmcloud is vpn-gateway $VPN_GATEWAY_NAME   # note the two Public IPs
```

### 1.3 IKE/IPsec policies (widely-compatible combo)
```bash
ibmcloud is ike-policy-create $IKE_POLICY_NAME sha256 14 aes256 2
ibmcloud is ipsec-policy-create $IPSEC_POLICY_NAME sha256 aes256 group_14
```

### 1.4 Connection
`PEER_PUBLIC_IP` / `PEER_PRIVATE_IP` must be set in `env.sh` first (get
these once the VM exists in Part 2). The peer IKE identity is normally
the VM's **private** IP — that's what most OSes send by default when no
explicit local identity is configured.
```bash
ibmcloud is vpn-gateway-connection-create $VPN_CONNECTION_NAME $VPN_GATEWAY_NAME \
  $PEER_PUBLIC_IP $PSK \
  --peer-ike-identity-type ipv4_address --peer-ike-identity-value $PEER_PRIVATE_IP

ibmcloud is vpn-gateway-connection-update $VPN_GATEWAY_NAME $VPN_CONNECTION_NAME \
  --ike-policy $IKE_POLICY_NAME --ipsec-policy $IPSEC_POLICY_NAME
```
Route-based gateways do **not** take `--local-cidr`/`--peer-cidr` on the
connection — traffic selection happens via VPC routing tables and the
peer's own OS routes instead.

<!-- ### 1.5 Security group — restrict to the VPN gateway only
Lock the peer VM's security group so it can only exchange traffic with the
two gateway public IPs (defense in depth against the CSE-range being
broadly reachable — see note in the C2S README):
```bash
GW_IP_1=$(ibmcloud is vpn-gateway $VPN_GATEWAY_NAME --output JSON | python3 -c "import sys,json;print(json.load(sys.stdin)['members'][0]['ip']['address'])")
GW_IP_2=$(ibmcloud is vpn-gateway $VPN_GATEWAY_NAME --output JSON | python3 -c "import sys,json;print(json.load(sys.stdin)['members'][1]['ip']['address'])")

for DIR in inbound outbound; do
  ibmcloud is security-group-rule-add <peer-vm-sg-id> $DIR any --remote $GW_IP_1
  ibmcloud is security-group-rule-add <peer-vm-sg-id> $DIR any --remote $GW_IP_2
done
``` -->