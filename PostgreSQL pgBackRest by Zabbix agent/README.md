# PostgreSQL pgBackRest by Zabbix agent

Zabbix 7.4 šablona pro monitoring záloh pgBackRestu (PostgreSQL 18) přes Zabbix agenta,
bez nutnosti instalovat další software (exporter apod.). Zdroje dat:

- **`pgbackrest info --output=json --stanza=<stanza>`** – spouští přímo Zabbix agent
  (UserParameter), master item vrací syrový JSON, ze kterého se přes dependent items
  a LLD odvozují všechny stavové/velikostní/časové hodnoty.
- **`pgbackrest check`** – spouští se **mimo Zabbix**, jednou denně přes systemd timer
  pod uživatelem `postgres`. Výstup se ukládá do log souboru, který Zabbix agent jen
  čte (`vfs.file.time`, `vfs.file.regmatch`, `vfs.file.regexp`).

Vendor: `lpavlicek`, verze šablony: `7.4-1`.

## Požadavky

- Zabbix 7.4 (server + agent, TimescaleDB jako backend)
- pgBackRest 2.57/2.58, PostgreSQL 18
- Ubuntu 24.04 / Debian 12+ / Debian 13
- `pgbackrest` binárka dostupná na `PATH` pro uživatele `zabbix`
- Uživatel `zabbix` musí umět přečíst:
  - repozitář/konfiguraci pgbackrestu (pro `pgbackrest info`) – řešeno členstvím
    v systémové skupině `postgres`
  - log soubor z `pgbackrest check` (viz níže)

## Instalace

### 1. UserParameter na Zabbix agentovi

Na každém monitorovaném hostu přidat do konfigurace Zabbix agenta (např.
`/etc/zabbix/zabbix_agentd.d/pgbackrest.conf`):

```
UserParameter=pgbackrest.info[*],pgbackrest info --output=json --stanza=$1
```

a restartovat agenta (`systemctl restart zabbix-agent`).

### 2. Oprávnění pro `pgbackrest info`

```bash
usermod -aG postgres zabbix
```

Zabbix agent musí být po přidání do skupiny restartován (nová skupina se
promítne až po restartu procesu).

### 3. Systemd timer pro `pgbackrest check`

`pgbackrest check` se spouští jednou denně mimo Zabbix, výstup jde do
`/var/log/pgbackrest/<stanza>-check.log` (cesta je konfigurovatelná přes makro
`{$PGBACKREST.CHECK.LOG.DIR}`).

**`/etc/systemd/system/pgbackrest-check@.service`**

```ini
[Unit]
Description=pgBackRest check for stanza %i
Wants=network-online.target
After=network-online.target postgresql.service

[Service]
Type=oneshot
User=postgres
Group=postgres
UMask=0027
ExecStart=/bin/sh -c '/usr/bin/pgbackrest check --stanza=%i --log-level-console=detail > /var/log/pgbackrest/%i-check.log 2>&1'
```

**`/etc/systemd/system/pgbackrest-check@.timer`**

```ini
[Unit]
Description=Daily pgBackRest check for stanza %i

[Timer]
OnCalendar=*-*-* 04:00:00
RandomizedDelaySec=900
Persistent=true
Unit=pgbackrest-check@%i.service

[Install]
WantedBy=timers.target
```

Aktivace (za `<stanza>` dosadit skutečný název stanzy):

```bash
systemctl daemon-reload
systemctl enable --now pgbackrest-check@<stanza>.timer
```

Ověřit, že adresář `{$PGBACKREST.CHECK.LOG.DIR}` (výchozí `/var/log/pgbackrest`)
má group-execute pro skupinu `postgres` (např. `0750 postgres:postgres`), jinak
se k souboru zabbix nedostane, i kdyby soubor samotný čitelný byl.

### 4. Import šablony a nastavení makra

Naimportovat `pgbackrest_template.yaml`, přiřadit šablonu hostu a povinně nastavit:

- `{$PGBACKREST.STANZA}` – název stanzy na daném hostu (bez tohoto makra
  zůstanou itemy "Not supported")

U hostů s odlišným zálohovacím plánem (např. denní `full` bez `incr/diff`)
přepsat na úrovni hostu makro `{$PGBACKREST.BACKUP.MAX.AGE:"full"}` na `26h`.

## Makra

| Makro | Výchozí hodnota | Význam |
|---|---|---|
| `{$PGBACKREST.STANZA}` | *(bez výchozí hodnoty)* | Název stanzy – **povinné nastavit per host** |
| `{$PGBACKREST.CHECK.LOG.DIR}` | `/var/log/pgbackrest` | Adresář s výstupem `pgbackrest-check@<stanza>.service` |
| `{$PGBACKREST.BACKUP.MAX.AGE:"full"}` | `8d` | Max. stáří poslední `full` zálohy |
| `{$PGBACKREST.BACKUP.MAX.AGE:"diff"}` | `26h` | Max. stáří poslední `diff` zálohy |
| `{$PGBACKREST.BACKUP.MAX.AGE:"incr"}` | `26h` | Max. stáří poslední `incr` zálohy |
| `{$PGBACKREST.CHECK.MAX.AGE}` | `32h` | Max. stáří check-logu (denní timer + rezerva) |

## Co šablona sleduje

**Stanza (bez LLD):**
- celkový stav stanzy (`status.code`/`message`) + value mapping s popisem kódů
- stáří a chybovost denního `pgbackrest check` logu (dle systemd timeru)

**LLD – repozitáře** (`{#REPO}`, libovolný počet, i s mezerami v číslování
jako repo1+repo3):
- stav daného repozitáře, min/max archivovaný WAL segment
- potvrzení z `pgbackrest check`, že se na dané repo skutečně podařilo
  zapsat/archivovat testovací WAL segment

**LLD – zálohy** (`{#REPO}` × `{#TYPE}`, jen reálně existující kombinace):
- čas poslední zálohy daného typu v daném repu (+ trigger na stáří)
- velikost skutečně zálohovaných dat (`info.delta`) a komprimovaná velikost
  na repu (`info.repository.delta`) – **ne** `info.size`/`info.repository.size`,
  což jsou celkové/kumulativní hodnoty stejné pro celý řetězec záloh
- počet záloh daného typu v repu (informativní, bez triggeru – retence se
  liší server od serveru i repo od repo)

## Value mappingy

- **`pgBackRest: stanza status code`** – kódy 0/1/2/3/4/5/6/99 dle zdrojového
  kódu pgbackrestu (`src/command/info/info.c`). Kódy 4 (mixed) a 5 (database
  mismatch) se objevují jen v agregovaném stavu celé stanzy, nikdy u
  jednotlivého repa.
- **`pgBackRest: boolean check result`** – 0/1 → No/Yes, použito u
  `pgbackrest: check log contains error`.

## Známá omezení

- `pgbackrest check` běží mimo Zabbix (systemd timer) – šablona jen čte jeho
  log, nespouští ho sama (vyžadovalo by spuštění pod uživatelem `postgres`,
  což jde nad rámec pouhého členství ve skupině).
- WAL archivace se sleduje jen nepřímo přes `check` (jednou denně) a přes
  min/max archivovaný segment z `info` (informativně, bez triggeru na
  "lag") – přímý WAL lag oproti aktuálnímu stavu PostgreSQL se nesleduje.
- Zaplnění S3 repozitáře se nemonitoruje (řešeno mimo tuto šablonu).

## Changelog

### 7.4-1 (2026-07-28)
- První verze šablony.
- Monitoring stavu stanzy a jednotlivých repozitářů (`pgbackrest info`).
- LLD pro repozitáře (libovolný počet, i s mezerami v číslování) a pro
  kombinace repo × typ zálohy (full/diff/incr) dle reálně existujících dat.
- Sledování stáří a chybovosti záloh, velikostí (skutečně zálohovaná data,
  ne celková velikost DB) a počtu záloh v retenci.
- Kontrola denního `pgbackrest check` (systemd timer mimo Zabbix) – stáří
  logu, chybové hlášky, potvrzení archivace WAL per repo.
- Value mappingy pro stavové kódy stanzy/repa a pro boolean check položky.
