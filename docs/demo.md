# Demo: Cognos → watsonx.ai over a Private-Only Path

**Runtime: ~7 minutes** (Part A: ~2 min portal config, Part B: ~2 min VPN
walkthrough, Part C: ~3 min live proof)

**Story:** This VM has no general internet access — only a private IPsec
tunnel to IBM Cloud. Part A shows the watsonx.ai connection in the Cognos
portal. Part B shows the tunnel itself, on both ends. Part C proves that
private path is actually load-bearing, not incidental, by breaking and
restoring it live.

## Intro

Before I jump into the live demo, let me orient you with this diagram — it maps exactly what you're about to see.

On the left is an AWS EC2 Windows Server. Think of this as the stand-in for the on-premise side — it's running IBM Cognos Analytics, and it has no general internet access at all. The only way traffic gets out is through this tunnel here — a site-to-site IPsec VPN into IBM Cloud on the right. In production, we would split the Cognos installation and VPN server into separate VMs for further isolation, but since this is a demo it is configured in one VM.

On the IBM Cloud side, that tunnel terminates at a VPN gateway, which routes traffic privately to two IBM services: watsonx.ai and the IAM token service. Both are private endpoints — they're not reachable from the public internet, only through this tunnel.

The story of the demo is really about this dashed purple line. Cognos needs watsonx.ai to power its AI agents. That call goes from the LiteLLM proxy, up through RRAS, across the tunnel, and arrives at watsonx.ai — never touching the public internet at any point.

To prove it's genuinely load-bearing and not just incidental, I'm going to break the tunnel live and show the AI feature fail, then restore it and show it work again. Same request, only thing that changes is tunnel state.

Let's go.


## Part B — The VPN connection, both ends (~2 min)

*"Here's what actually makes that private hostname reachable."*

### B1. IBM Cloud side (console)
Navigate: **VPC Infrastructure → Network → VPN gateways** → click the
gateway.

Point out:
- **Public IPs** (two, for redundancy) — *"this is the address our VM
  dials into"*
- **Connections** tab → click the connection → **Status: Up**,
  both **Tunnels** showing **Up**

*"That status is live — it's the same object the VM authenticates
against."*

### B2. AWS side (console)
Navigate: **EC2 → Security Groups** → select the instance's security
group.

Point out:
- **Inbound rules**: RDP (admin IP only) + UDP 500/4500, scoped to the
  two IBM Cloud gateway IPs from B1 — nothing else
- **Outbound rules**: same two IPs only — no general internet egress

*"Two rules, two IP addresses, matching exactly what we just saw on the
IBM Cloud side. That's the entire attack surface for this VM."*

**Callout — how this differs in production:**

*"For this demo, Cognos and the VPN tunnel are on the same box, so this
security group is doing double duty — it's both 'what can reach Cognos'
and 'what can reach the tunnel.' In a production layout, we'd split
those into two machines:*

- *A small, dedicated **gateway VM** — its only job is terminating this
  IPsec tunnel. It's the one with a public IP and this security group.*
- *The **Cognos VM** stays fully private — no public IP at all, security
  group scoped to internal traffic only, never talks to the internet or
  to IBM Cloud's gateway IPs directly.*

*Cognos reaches watsonx.ai by routing through the gateway VM instead of
terminating the tunnel itself — the gateway forwards traffic between the
tunnel and Cognos's internal network segment. Practically, that means
enabling IP forwarding on the gateway, and Cognos's own routes for the
IBM Cloud VPC subnet and CSE range point at the **gateway's private IP**
as the next hop, rather than at a tunnel interface of its own.*

*The benefit: even if the Cognos VM were ever compromised, there's no
public entry point on it at all — the only externally reachable thing in
this whole setup is a single-purpose gateway box with nothing valuable
running on it."*

### B3. The VM's own tunnel state (PowerShell — no AWS console equivalent)
```powershell
Get-VpnS2SInterface -Name "IBMCloud-VPN"
```
→ `Connected`

*"This is the Windows side of the same tunnel we just saw as 'Up' in the
IBM Cloud console — standard Site-to-Site IPsec, no client software, no
login."*

---

---

1. Show can't access internet

## Part A — Portal-side watsonx.ai connection (~2 min)

**Manage → watsonx.ai connections → Create connection:**
- Type: **IBM watsonx.ai**
- Service endpoint: `https://private.jp-tok.ml.cloud.ibm.com`
  (*"private — this hostname only resolves over the tunnel we'll look
  at next"*)
- API key + Project ID
- **Create and finish**

---

## Part C — Live proof (~3 min)

### 0:00 – 0:30 — Confirm no general internet access
```powershell
Test-NetConnection -ComputerName google.com -Port 443
```
→ Fails / times out. *"Consistent with the security group rules we just
looked at — this box genuinely can't reach the open internet."*

### 0:30 – 1:15 — Break the tunnel on purpose
```powershell
Disconnect-VpnS2SInterface -Name "IBMCloud-VPN"
Remove-VpnS2SInterface -Name "IBMCloud-VPN"
```

Switch to the browser → open a report in Cognos → ask the AI Assistant to
summarize it.

→ **Fails**: *"Recommendations are temporarily unavailable..."*

*"The report lives on this box. The AI model doesn't — it's the
watsonx.ai connection from Part A, reachable only through the tunnel we
just took down."*

*(Optional: flip back to the IBM Cloud console's Connections tab —
status now shows **Down**, tunnels down.)*

### 1:15 – 1:45 — Reconnect
```powershell
Add-VpnS2SInterface `
  -Name "IBMCloud-VPN" `
  -Destination "<GW_IP_1 from 1.2>" `
  -Protocol IKEv2 `
  -AuthenticationMethod PSKOnly `
  -SharedSecret "<PSK>" `
  -IPv4Subnet "<SUBNET_CIDR>:10"
Connect-VpnS2SInterface -Name "IBMCloud-VPN"
```
*(Optional: refresh the IBM Cloud console — status flips back to **Up**.)*

*"Comes right back up — same PSK, same policy, nothing exotic."*

### 1:45 – 2:45 — Show it working
Same report, same "Summarize" action in the browser.

→ **Succeeds** — a real AI-generated summary streams in.

*"Identical request. The only thing that changed is tunnel state. That's
the private connectivity actually doing the work, not just sitting
there."*

### 2:45 – 3:00 — Wrap
*"Cognos on a standard cloud VM, zero general internet access, talking
to watsonx.ai purely over a private IPsec tunnel into IBM Cloud. The AI
backend is never publicly exposed at any point in this chain."*

---

## Pre-demo checklist
- [ ] `watsonx.ai` connection already created and set as AI Agent
      Connection (Part A can be shown live *or* pre-built and just
      narrated, depending on time available)
- [ ] IBM Cloud console and AWS console both logged in and navigated
      close to the VPN gateway / security group screens beforehand —
      avoid live login/navigation delays
- [ ] Tunnel currently `Connected` before starting Part C
- [ ] Test report already open/bookmarked in Cognos for fast access
- [ ] Confirm `Test-NetConnection ... google.com` fails *before* going
      live — re-verify egress lockdown wasn't accidentally loosened
      during setup



NOTE:
1. before demo pre run the commands once in terminal so u can up up up