# MikroTik Scheduled Cloudflare DDNS Updater

A MikroTik RouterOS script that dynamically updates Cloudflare DNS `A` records when your public IPv4 address changes. Run it on a schedule and It fetches your current IPv4 via `api.ipify.org`, and updates the IP on existing cloudflare DNS records.

## Prerequisites

- **RouterOS:** v7.10 or newer (required for `[:deserialize from=json]`).
- **Cloudflare API Token:** A scoped token with **Zone / DNS / Edit** permissions for the target zone.
- **Cloudflare Zone ID:** Found on your domain's **Overview** page in the Cloudflare dashboard.
- **Existing DNS `A` Records:** Any hostnames you list in `$records` must already exist as `A` records in Cloudflare. Missing records are logged as warnings and skipped rather than created.

## Configuration

Open script file and update the configuration block at the top:

- `cfToken`: Your scoped Cloudflare API token.
- `zoneId`: Your Cloudflare Zone ID.
- `records`: An array of FQDNs (`A` records) to update (for example, `"host1.example.com"`, `"host2.example.com"`).

## Installation on MikroTik Device

### Create script in WinBox or Webfig Script Editor

1. Open **WinBox** or **WebFig**.
2. Go to **System → Scripts** and click **+New** to create a new script (for example, `cf_ddns_example`).
3. Enable Policies: **read, write, policy & test**
4. Paste the script contents into the **Source** field and click OK to save.

## Testing & Verification

1. Force a test run by setting `cfLastIp` to a dummy value and running the script from the terminal:

   ```routeros
   :global cfLastIp "1.2.3.4"
   /system script run cf_ddns_example
   ```

2. Check the router logs to verify updates:

   ```routeros
   :log print where topics~"script"
   ```

3. Confirm that:

   - Existing `A` records in cloudflare are updated to your current IP.
   - Running the script a second time with the same IP skips updates (`IP unchanged`).

## Scheduling Automatic Runs

To check for IP changes periodically (for example, every 5 or 15 minutes), add a scheduler entry:

```routeros
/system scheduler add name="cf-ddns-example-sched" interval=15m on-event="/system script run cf_ddns_example" start-time=startup
```

Adjust `interval` (such as `15m` or `5m`) to suit how quickly you want DNS updates to propagate after an IP change.

## IP Variable Memory

The current IP is kept in global environment variable `cfLastIP`. It can be viewed or modified in **System → Scripts → Environment Tab**. Since this variable is held in memory, upon device reboot, the first run of the script will always run an update for the DNS records.