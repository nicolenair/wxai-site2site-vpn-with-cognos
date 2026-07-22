# IBM Cognos Analytics — Install, Content Store, LDAP, Agentic AI

Windows Server host. Values below reference `env.sh` (bash-style names —
translate to plain values for PowerShell steps).

## 1. Prerequisites
- Windows Server, 4+ CPU cores, 32GB+ RAM, 15GB+ free on the Windows
  directory's drive (per IBM's stated minimums)
- Java 8 (Cognos requires it even if newer Java is present elsewhere):
  install Eclipse Temurin 8 — https://adoptium.net/temurin/releases/?version=8
  — check "Add to PATH" / "Set JAVA_HOME" during setup.
- Container runtime for the supporting services (Postgres, LDAP,
  OpenSearch, the agentic AI service itself): Podman or Docker.
- Cognos installed (but not configured)

## 2. Content store — PostgreSQL

Download postgres from here: https://www.postgresql.org/download/, and start postgres

Check that it is running

```
Get-Service -Name "postgresql*"
```

Use psql to test
```
Get-ChildItem "C:\Program Files\PostgreSQL" -Recurse -Filter "psql.exe" -ErrorAction SilentlyContinue
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres
```

**In Cognos Configuration** → Data Access → Content Manager → new
PostgreSQL resource:
| Field | Value |
|---|---|
| Database server and port | `$CM_DB_HOST:$CM_DB_PORT` |
| User ID and password | `$CM_DB_USER` / `$CM_DB_PASSWORD` |
| Database name | `$CM_DB_NAME` |
| Schema name | `$CM_DB_SCHEMA` |
| SSL Encryption Enabled | False (unless you've configured Postgres SSL) |

Save (disk icon) **before** testing — Cognos Configuration doesn't
persist changes until explicitly saved. Right-click the resource → Test.


# 3. Setup virtualization & podman

Run
```
wsl.exe --install --no-distribution
wsl --install 
```

Download & install podman: https://github.com/containers/podman/blob/main/docs/tutorials/podman-for-windows.md


Run to start podman
```
podman machine init
podman machine start
```

## 4. Authentication — LDAP

Simplest test setup for LDAP on windows is WSL2 +
`slapd` 

```
wsl --install #wsl -d Ubuntu
```

Inside the Ubuntu/WSL shell:
```bash
sudo apt update && sudo apt install slapd ldap-utils -y
sudo dpkg-reconfigure slapd
```
Answers: domain `$LDAP_DOMAIN`, org `$LDAP_ORG`, admin password
`$LDAP_ADMIN_PASSWORD`, keep the database on purge = No.

```bash
sudo systemctl start slapd
cat <<EOF | ldapadd -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"
dn: ou=people,$LDAP_BASE_DN
objectClass: organizationalUnit
ou: people

dn: $TEST_USER_DN
objectClass: inetOrgPerson
uid: testuser
cn: Test User
sn: User
userPassword: $TEST_USER_PASSWORD
EOF
```
`slapd` runs as a systemd service inside WSL2 — it survives closing the
terminal, but WSL2 itself can idle-shutdown; if `sudo systemctl status
slapd` shows inactive after a break, `wsl` then restart it.

Run to add ldap tools
```
Install-WindowsFeature -Name RSAT-ADDS
```

**In Cognos Configuration** → Security → Authentication → new LDAP
resource ("LDAP - General default values"):
| Field | Value |
|---|---|
| Host and port | `$LDAP_HOST_PORT` |
| Base Distinguished Name | `$LDAP_BASE_DN` |
| User lookup | `(&(objectClass=inetOrgPerson)(uid=${userID}))` |
| Bind user DN and password | `$LDAP_ADMIN_DN` / `$LDAP_ADMIN_PASSWORD` |
| Use bind credentials for search? | **True** — most LDAP servers, including this one, reject anonymous search |
| Use TLS | False |

Save, start Cognos, log into the portal with `testuser` / `$TEST_USER_PASSWORD`
to confirm.

## 5. Agentic AI

### 4.1 Base configuration
Cognos Configuration → **Agentic AI → Configuration**:
| Field | Value |
|---|---|
| Enable Agentic AI? | True |
| Cognos Analytics Base URL | `$CA_BASE_URL` |
| postgresql password | $CM_DB_PASSWORD |
| LiteLLM Master Key | set dummy value |
| LiteLLM Salt Key | set dummy value |
| Opensearch Admin Password | $INITIAL_OPENSEARCH_ADMIN_PASSWORD |

**`Cognos Analytics Base URL` must never be `localhost`** — the agentic
service runs in its own container with its own network namespace, where
`localhost` refers to itself, not the Windows host. Use the host's actual
private IP. If the container can't reach this address at all, check:
- The URL resolves and something responds: `curl http://<host-ip>:9300/bi/v1`
  from the host itself
- Windows Firewall allows inbound TCP 9300 from the container's virtual
  network (`New-NetFirewallRule -DisplayName "Cognos Dispatcher" -Direction Inbound -LocalPort 9300 -Protocol TCP -Action Allow`)
- `host.containers.internal` (Podman's DNS alias for the host) may resolve
  to a link-local address that **doesn't route anywhere real** — if so,
  use the host's actual IP directly instead of that alias.

### Set the following firewall rule:
```
New-NetFirewallRule -DisplayName "Cognos Dispatcher 9300" -Direction Inbound -LocalPort 9300 -Protocol TCP -Action Allow
```

### Fix token URL in LiteLLM proxy configuration

podman update --env "WATSONX_IAM_URL=https://private.iam.cloud.ibm.com/identity/token" litellm-proxy
podman restart litellm-proxy



### 4.2 Model — must actually exist in your watsonx.ai project
Check what's available before configuring a model ID:
```bash
curl -X GET "https://<region>.ml.cloud.ibm.com/ml/v1/foundation_model_specs?version=2023-05-29" \
  -H "Authorization: Bearer $TOKEN"
```
Use a `model_id` from that response. A
plausible-looking model name that isn't actually deployed fails with a
generic "we're having trouble connecting to our Agents" error in the
portal — check the agentic container's logs for the real reason:
```powershell
podman logs $AGENTIC_CONTAINER_NAME --tail 30
```



### 4.3 Portal-side connection setup (in addition to Cognos Configuration)

Beyond the fields in **Cognos Configuration → Agentic AI →
Configuration**, the watsonx.ai connection itself is actually created and
activated in the **web portal**, not the desktop tool. Do this after the
service is reachable (Section 4.1) and before expecting agents to work.

**1. Manage → System → Agentic AI** — confirm:
| Field | Value |
|---|---|
| Allow agentic AI features | On |
| Enable agentic AI feature for all tenants | On |
| Agentic service URL | `http://localhost:9000` (portal → agentic container, same host) |

**2. Manage → watsonx.ai connections → Create connection:**
| Field | Value |
|---|---|
| Name | `watsonx.ai` |
| Type | IBM watsonx.ai |
| Service endpoint | `https://private.<region>.ml.cloud.ibm.com` |
| Authentication type | API key |
| API key | `$WATSONX_API_KEY` |
| ID type | Project ID |
| Project ID | `$WATSONX_PROJECT_ID` |

Click **Create and finish**.

**3. Activate it as the agent's model source** — on the new connection's
row, **⋯ menu → Set as AI Agent Connection**. Without this step the
connection exists but agents never use it.

**4. Verify** — a **Model Gateway** entry named **LiteLLM** appears
automatically once the connection is set as the AI Agent Connection —


### 4.4 OpenSearch (needed for report search/summarization specifically)
Cognos ships its own 3-node OpenSearch cluster, but on some Windows/Podman
hosts it fails a bootstrap memory-lock check and never starts. If you see failed opensearch containers on podman,
run a single external node yourself instead — **on the same container
network as the agentic service**, so they can reach each other without
going through the host's (unreliable) port-forwarding layer at all:

```powershell
podman run -d --name $OPENSEARCH_CONTAINER_NAME --network $AGENTIC_NETWORK_NAME `
  -e "discovery.type=single-node" `
  -e "bootstrap.memory_lock=false" `
  -e "DISABLE_SECURITY_PLUGIN=true" `
  -e "DISABLE_INSTALL_DEMO_CONFIG=true" `
  -e "OPENSEARCH_INITIAL_ADMIN_PASSWORD=$INITIAL_OPENSEARCH_ADMIN_PASSWORD" `
  docker.io/library/opensearch:3.4.0
```

(`DISABLE_SECURITY_PLUGIN=true` is required — OpenSearch 3.x defaults to
HTTPS-only, but Cognos's agentic service connects over plain HTTP.)

Set **External OpenSearch URL** in Cognos Configuration to:
```
http://$OPENSEARCH_CONTAINER_NAME:9200
```
Container **names** resolve automatically between containers on the same
user-defined Podman network — no IP hardcoding needed, and it survives
container recreation.

### 4.5 Index a report before summarizing it
A brand-new report returns "index exists but contains no documents" until
explicitly indexed — open the report, use its context menu's **Add to AI
index** action (or equivalent) before asking an agent to summarize it.

## Known gaps / not covered here
- **Share Agent** (emailing/sharing summaries) needs a separate SMTP
  server configuration step, not covered in this doc.
- **Report ID lost between turns**: if a summarization request returns a
  generic error mentioning `SUMMARY_ERROR_EDIT_MODE` or similar undefined
  symbols, it's a product-side bug triggered by missing report context —
  re-invoke the agent from inside the actual open report, not a blank
  chat panel.

## Test

You can generate a sample csv and use for testing the agentic ai with VPN enabled, and without VPN showing that the service only works with VPN

```
$data = @"
Region,Product,Month,Revenue,UnitsSold
North,Widget A,January,15000,300
North,Widget B,January,22000,440
South,Widget A,January,18000,360
South,Widget B,January,9500,190
East,Widget A,January,12000,240
East,Widget B,January,27000,540
West,Widget A,January,16500,330
West,Widget B,January,19000,380
North,Widget A,February,17200,344
North,Widget B,February,24500,490
South,Widget A,February,19800,396
South,Widget B,February,10200,204
East,Widget A,February,13500,270
East,Widget B,February,29500,590
West,Widget A,February,18100,362
West,Widget B,February,20800,416
"@

$data | Out-File -FilePath "$env:USERPROFILE\Desktop\sales_data.csv" -Encoding utf8
Write-Output "Created: $env:USERPROFILE\Desktop\sales_data.csv"
```

## SMTP

You can use Papercut SMTP for testing SMTP & report sharing agent