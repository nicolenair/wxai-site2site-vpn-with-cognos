# Post-Reboot Checklist

## What to redo after an EC2 stop/start (not terminate)

### Stays the same — no action needed
- Private/public IP (Elastic IP), EBS volume contents, IBM Cloud
  connection config
- **Postgres** — native EDB Windows service, starts automatically with
  Windows (confirm once with `Get-Service -Name "postgresql*"` after a
  restart, since some installs default to Manual rather than Automatic
  startup type)
- Persistent routes — no need to verify

### Restarts automatically, but needs one manual fix
| Item | Action |
|---|---|
| Agentic containers (`ba-agentic-app`, `litellm-proxy`, `my-opensearch-ext`, `redis-server`, `litellm-db`) | Come up on their own when Cognos itself starts — no manual `podman start` needed |
| `WATSONX_IAM_URL` on `litellm-proxy` | **Must be reapplied** — doesn't persist through the container recreation that happens on restart:<br>`podman update --env "WATSONX_IAM_URL=https://private.iam.cloud.ibm.com/identity/token" litellm-proxy`<br>`podman restart litellm-proxy` |

### Needs fully manual restart
| Item | Command |
|---|---|
| WSL2 / LDAP | `wsl` then `sudo systemctl start slapd` |
| S2S VPN tunnel | `Connect-VpnS2SInterface -Name "IBMCloud-VPN"` |
| Papercut SMTP | Re-launch it manually (whatever command/shortcut was used originally) — it's a bare process, not a registered service, so it won't auto-start |

### Quick post-reboot order of operations
1. `Connect-VpnS2SInterface -Name "IBMCloud-VPN"`
2. `wsl` → `sudo systemctl start slapd`
3. Launch Papercut
4. Start Cognos (brings up all agentic containers automatically)
5. `podman update --env "WATSONX_IAM_URL=https://private.iam.cloud.ibm.com/identity/token" litellm-proxy` → `podman restart litellm-proxy`
6. Confirm Postgres service is `Running` (`Get-Service -Name "postgresql*"`)