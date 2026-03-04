# Oracle Free Tier Hunter

> 🌐 **Language / Язык:** English | [Русский](README.ru.md)

Automated hunter for Oracle Cloud **VM.Standard.A1.Flex** free tier instance (4 OCPU / 24 GB RAM).

Oracle Always Free ARM instances are in high demand and almost always show "Out of host capacity". The only reliable way to get one is to keep retrying until a slot opens up. This tool does exactly that — automatically, 24/7, without keeping your computer on.

---

## How it works

1. GitHub Actions triggers on a cron schedule every 30 minutes
2. Installs OCI CLI and configures it from GitHub Secrets
3. **Automatically fetches available Availability Domains** for your region — no hardcoding needed
4. Makes up to 20 attempts per run, rotating across all ADs
5. On success or a critical error sends a Telegram notification
6. On a normal "no capacity" response — exits silently and waits for the next run

---

## Repository structure

```
.
├── .github/
│   └── workflows/
│       └── hunter.yml       # GitHub Actions workflow (runs every 30 min)
└── oracle_sniper.sh         # Bash script for local / manual runs
```

---

## Setup

### Step 1 — OCI API Key

If you don't have an OCI API key yet:

1. Open [Oracle Cloud Console](https://cloud.oracle.com) → click your profile icon (top right) → **My profile**
2. Scroll to **API keys** → **Add API key**
3. Choose **Generate API key pair** → download both keys
4. Oracle will show you a config preview — copy the `fingerprint`, `tenancy`, `user`, and `region` values from it

> Official docs: [Required Keys and OCIDs](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm)

### Step 2 — Find your resource OCIDs

| Value | Where to find |
|-------|---------------|
| `OCI_COMPARTMENT_ID` | Profile icon → **Tenancy** → copy **OCID** (same as tenancy for root compartment) |
| `OCI_SUBNET_ID` | **Networking → Virtual Cloud Networks** → your VCN → **Subnets** → copy OCID |
| `OCI_IMAGE_ID` | **Compute → Images** → select your OS (e.g. Ubuntu 22.04 Minimal, ARM-compatible) → copy OCID |

### Step 3 — GitHub Secrets

Go to your repository: **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Description |
|--------|-------------|
| `OCI_USER_OCID` | Your user OCID (`ocid1.user...`) |
| `OCI_TENANCY_OCID` | Your tenancy OCID (`ocid1.tenancy...`) |
| `OCI_FINGERPRINT` | API key fingerprint (format: `xx:xx:xx:...`) |
| `OCI_REGION` | Target region, e.g. `eu-frankfurt-1`, `us-ashburn-1` |
| `OCI_API_KEY` | Full contents of your private key file (including `-----BEGIN/END-----`) |
| `OCI_SSH_PUB_KEY` | Contents of your public SSH key (`~/.ssh/id_rsa.pub` or similar) |
| `OCI_COMPARTMENT_ID` | Compartment OCID (usually same as tenancy for root) |
| `OCI_SUBNET_ID` | Subnet OCID in your target region |
| `OCI_IMAGE_ID` | OS image OCID (must be ARM-compatible for A1.Flex) |
| `TELEGRAM_TOKEN` | Telegram bot token |
| `TELEGRAM_TO_ID` | Your Telegram chat ID |

### Step 4 — Enable the workflow

Push the repo to GitHub. Go to the **Actions** tab — `Oracle Cloud Hunter` should appear. Run it manually first (**Run workflow** button) to verify your credentials work.

---

## Telegram notifications

The bot sends a message **only on real events** — not on every run:

- `✅` — instance successfully provisioned
- `⚠️` — workflow error (auth failure, limit exceeded, etc.)

Normal "no capacity" runs are silent.

### How to set up a Telegram bot

1. Open Telegram → search for **@BotFather** → send `/newbot`
2. Follow the prompts — at the end BotFather gives you a token like `7412345678:AAHdqTcvCH...` → this is your `TELEGRAM_TOKEN`
3. Start a chat with your new bot (send it any message)
4. Open in browser (replace `<TOKEN>` with yours):
   ```
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```
5. Find `"chat": { "id": 123456789 }` in the response → this is your `TELEGRAM_TO_ID`

---

## Local run (oracle_sniper.sh)

Requires OCI CLI installed and configured (`pip install oci-cli` + `oci setup config`).

```bash
# Required env vars
export OCI_COMPARTMENT_ID="ocid1.tenancy..."
export OCI_IMAGE_ID="ocid1.image..."
export OCI_SUBNET_ID="ocid1.subnet..."

# Run
bash oracle_sniper.sh
```

Optional environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_KEY_PATH` | `~/oracle_key.pub` | Path to your SSH public key |
| `LOG_FILE` | `~/oracle_sniper.log` | Main log file path |
| `ERROR_LOG` | `~/oracle_unknown_error.log` | Unknown error log |
| `SLEEP_INTERVAL` | `60` | Seconds between attempts on "no capacity" |
| `MAX_ATTEMPTS` | `0` (unlimited) | Max attempts before stopping |
| `NTFY_TOPIC` | — | [ntfy.sh](https://ntfy.sh) topic for push notifications |

---

## Important notes

**GitHub Actions minutes:**
- **Public repo** (default): unlimited minutes — workflow runs every 30 min as-is
- **Private repo**: 2,000 min/month free. Change the cron in `hunter.yml` to `0 */2 * * *` (every 2h) to stay within the limit

**Tuning attempts per run:**
Set the `HUNT_ATTEMPTS` repository variable to control how many attempts are made per run (default: 15).
Go to **Settings → Secrets and variables → Actions → Variables → New variable**.
Useful for private repos where you want to balance coverage vs. minutes used.

**Auto-disable warning:** GitHub disables scheduled workflows after **60 days of repository inactivity**. Run the workflow manually once a month to keep it active.
