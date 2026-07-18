# Certificate Expiry by Zabbix agent

Monitors the remaining validity of X.509 certificate files on a Linux host via
Zabbix agent. This template is **general-purpose** — it discovers and checks
any certificate file(s) you point it at via a macro, and has no dependency on
FreeRADIUS or any other specific application. It happens to be used here to
watch the TLS/RadSec certificates of a FreeRADIUS deployment, but works
equally well for any service that keeps its certificates in files on disk
(web servers, mail servers, VPN gateways, internal CAs, ...).

## What it does

- Reads a list of certificate files from the `{$CERTFILES}` macro.
- Each file may hold a **single certificate** or a **PEM bundle** with
  several certificates (e.g. a certificate chain or a CA bundle) — every
  certificate found is discovered and monitored **individually**.
- Certificates are identified by their **Common Name (CN)**, not their full
  Subject DN (see [Security notes](#security-notes) for why).
- For each certificate, an item reports the number of days remaining until
  expiry (negative once expired), with configurable Warning/High thresholds
  per file.
- A separate check validates the `{$CERTFILES}` configuration itself
  (missing files, unreadable files, invalid thresholds, unsafe paths) so
  misconfiguration is visible instead of silently producing no data.

## Requirements

- Zabbix 7.4 (should also work on other reasonably recent 6.x/7.x versions;
  not tested there).
- Zabbix agent (classic or agent 2 — nothing agent-2-specific is used).
- Linux host with `bash`, `awk`, `sed`, `tr`, `openssl`, and GNU `date`.
  Verified on Debian 12+ and Ubuntu 24.04+; should work on any modern
  systemd-based distribution with the same tools available.
- The user the Zabbix agent runs as (usually `zabbix`) must have **read**
  access to every certificate file listed in `{$CERTFILES}`.

## Files in this directory

| File | Purpose |
|---|---|
| `Certificate Expiry by Zabbix agent.yaml` | The Zabbix template (import via Data collection → Templates → Import). |
| `cert_check.sh` | Helper script, deployed on every monitored host. |

## Installation

1. Copy `cert_check.sh` to the host, e.g. `/etc/zabbix/scripts/cert_check.sh`:
   ```
   chown root:zabbix /etc/zabbix/scripts/cert_check.sh
   chmod 750 /etc/zabbix/scripts/cert_check.sh
   ```
2. Make sure the `zabbix` user can read the certificate files you intend to
   monitor (adjust group membership or ACLs as needed — do **not** make the
   files world-readable just for this).
3. Register the UserParameters, e.g. in
   `/etc/zabbix/zabbix_agent2.d/userparams/cert_check.conf`:
   ```
   UserParameter=certfile.discovery[*],/etc/zabbix/scripts/cert_check.sh discovery "$1"
   UserParameter=certfile.expiry[*],/etc/zabbix/scripts/cert_check.sh value "$1" "$2"
   UserParameter=certfile.filecheck[*],/etc/zabbix/scripts/cert_check.sh filecheck "$1"
   ```
4. Restart the agent:
   ```
   systemctl restart zabbix-agent2
   ```
5. Import `Certificate Expiry by Zabbix agent.yaml` in Zabbix
   (Data collection → Templates → Import).
6. Link the template to the host and set `{$CERTFILES}` (see below).
7. Test directly on the host before waiting for the first Zabbix poll:
   ```
   zabbix_agent2 -t 'certfile.filecheck[<your {$CERTFILES} value>]'
   zabbix_agent2 -t 'certfile.discovery[<your {$CERTFILES} value>]'
   ```

## Configuration

### `{$CERTFILES}` macro

Comma-separated list of certificate files to monitor. Format per entry:

```
path:warning_days:high_days
```

Example:

```
/etc/freeradius/certs/radius.crt:30:7,/etc/freeradius/certs/radsecproxy-bundle.pem:60:10
```

This monitors two files:
- `radius.crt` — Warning if it expires in under 30 days, High if under 7.
- `radsecproxy-bundle.pem` — a bundle; **every** certificate found inside it
  is monitored, each with Warning at 60 days and High at 10 days.

Rules:
- Paths **must be absolute** and must not contain a `..` segment.
- Paths must not contain a comma (comma separates entries).
- `warning_days` and `high_days` must be plain non-negative integers.
- Entries that fail any of these rules are skipped by discovery and reported
  as a problem by the `certfile.filecheck` item/trigger (see below) — they
  do not silently disappear.

## What gets created

| Object | Description |
|---|---|
| Item `certfile.filecheck[{$CERTFILES}]` | Validates the `{$CERTFILES}` configuration itself. Returns `OK` or `PROBLEMS: ...`. |
| Trigger on the item above | Fires when the configuration has a problem (missing/unreadable file, invalid thresholds, unsafe path). |
| Discovery rule `certfile.discovery[{$CERTFILES}]` | Finds every certificate in every configured file. |
| Item prototype `certfile.expiry[...]` | Days remaining until expiry, per certificate (`{#CERTFILE}`, `{#CERTCN}`). |
| Trigger prototypes (High / Warning) | Based on the per-file `{#HIGHDAYS}` / `{#WARNDAYS}` thresholds from `{$CERTFILES}`. |

## Security notes

- **CN instead of full Subject**: Zabbix's UserParameter mechanism rejects a
  fixed set of characters in parameter values as a shell-injection
  precaution (`\ ' " `` * ? [ ] { } ~ $ ! & ; ( ) < > | # @` and newline).
  A certificate's full Subject DN can easily contain one of these (e.g. `@`
  in an `emailAddress` field), which would make that certificate
  un-monitorable. The Common Name alone is very unlikely to contain any of
  them, so it's used as the identifier instead. As defense in depth, the
  extracted CN is further sanitized (anything outside `[A-Za-z0-9 ._-]`
  becomes `_`) before it's ever used as an item key or LLD macro value.
- **Path validation**: every file path is required to be absolute and must
  not contain a `..` segment, so a `{$CERTFILES}` value can never be used to
  read files outside of what was explicitly configured (e.g.
  `/etc/freeradius/certs/../../../etc/shadow` is rejected).
- **No `set -e` / `set -o pipefail`**: deliberate choice, not an oversight.
  The script relies on explicit checks (`... || continue`, empty-result
  checks) so that one bad entry (a corrupt certificate inside an otherwise
  valid bundle, for example) is skipped without aborting discovery of the
  rest. Turning on `pipefail` would make an internal `openssl` failure
  abort the whole script immediately and silently, which is a worse
  outcome than the explicit handling already in place.
- The shared secret model used by other templates in this project (raw
  text stored in a local file, not a Zabbix macro) does not apply here —
  this template has no secrets, only file paths.

## Known limitations

- If a bundle contains two certificates with the **same CN** (unusual, but
  possible during a certificate rotation window), discovery can only
  represent one of them.
- Certificate content itself is trusted; this script does not attempt to
  protect against a maliciously crafted certificate file exploiting a bug
  in `openssl` itself.

## Troubleshooting

- `certfile.filecheck` shows `PROBLEMS: ...` → read the message, it names
  the exact file and issue (unreadable, invalid thresholds, unsafe path).
- A specific certificate doesn't show up after adding it to a bundle → run
  discovery manually (see step 7 above) and check whether its CN appears in
  the JSON output.
- `certfile.expiry` item shows "Not supported" → check the item's error
  message in Zabbix (Latest data), it will say `ZBX_NOTSUPPORTED: ...` with
  the specific reason (unreadable file, CN not found in the file, or an
  unsafe path).

## Version

Template `vendor.version`: `7.4-2`. See the project's top-level README /
CHANGELOG for the overall FreeRADIUS monitoring project this template is
part of.
